import 'dart:async';
import 'dart:typed_data';

import '../services/chat_offline_queue.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../utils/visibility_refresh_stub.dart'
    if (dart.library.html) '../utils/visibility_refresh_web.dart' as visibility_refresh;

/// Natives Chat-Modul â ohne WebView.
class ChatScreen extends StatefulWidget {
  final String companyId;
  final String? initialChatId;
  final String? title;
  final VoidCallback? onBack;
  final bool hideAppBar;

  /// Wird beim Ãffnen eines Chats aufgerufen â Badge sofort lokal zurücksetzen.
  final void Function(String chatId, int unreadInChat)? onChatOpened;

  const ChatScreen({
    super.key,
    required this.companyId,
    this.initialChatId,
    this.title,
    this.onBack,
    this.hideAppBar = false,
    this.onChatOpened,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _chatService = ChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  // ââ Chat-Listen-State ââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  StreamSubscription<List<ChatModel>>? _chatsSub;
  List<ChatModel> _chats = [];
  bool _chatsLoading = true;

  // ââ Nachrichten-State ââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  String? _selectedChatId;
  ChatModel? _selectedChat; // gecacht â kein zweiter Stream in AppBar nötig
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  List<ChatMessage> _messages = [];
  bool _messagesLoading = false;
  bool _messagesError = false;

  // ââ Web Visibility âââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  void Function()? _visibilityCallback;

  // ââ UI-Hilfszustand ââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  List<MitarbeiterForChat> _mitarbeiter = [];
  List<Uint8List> _pendingImages = [];
  bool _loadingMitarbeiter = false;
  bool _showNewChatModal = false;
  bool _showNewGroupModal = false;
  final _groupNameController = TextEditingController();
  final List<MitarbeiterForChat> _selectedGroupMembers = [];

  /// Ausstehende Nachrichten (Offline-Queue) für den aktuellen Chat.
  final List<Map<String, dynamic>> _pendingMessages = [];

  // ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Timer? _pendingCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToChats();
    if (kIsWeb) _setupVisibilityRefresh();

    if (widget.initialChatId != null && widget.initialChatId!.isNotEmpty) {
      _selectedChatId = widget.initialChatId;
      _subscribeToMessages(widget.initialChatId!);
    }
    if (!kIsWeb) {
      _startPendingCheckTimer();
      unawaited(_chatService.processOfflineQueue());
    }
  }

  void _startPendingCheckTimer() {
    _pendingCheckTimer?.cancel();
    _pendingCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _pendingMessages.isEmpty) return;
      try {
        final inQueue = await ChatOfflineQueue.getAll();
        final ids = inQueue.map((p) => p.id).toSet();
        if (mounted) {
          setState(() {
            _pendingMessages.removeWhere((p) => !ids.contains(p['id']));
          });
        }
      } catch (_) {}
    });
  }

  // ââ Chat-Listen-Stream ââââââââââââââââââââââââââââââââââââââââââââââââââââ
  void _subscribeToChats() {
    _chatsSub = _chatService.streamChats(widget.companyId).listen(
      (chats) {
        if (!mounted) return;
        setState(() {
          _chats = chats;
          _chatsLoading = false;
          // selectedChat synchron aktualisieren â kein zweiter Stream nötig
          if (_selectedChatId != null) {
            _selectedChat = chats.where((c) => c.id == _selectedChatId).firstOrNull;
          }
          // Badge-Reset bei initialChatId: einmalig nach erstem Laden
          if (widget.initialChatId != null && _chatsLoading) {
            final chat = chats.where((c) => c.id == widget.initialChatId).firstOrNull;
            if (chat != null) {
              final uid = _chatService.userId ?? '';
              widget.onChatOpened?.call(chat.id, chat.unreadCount[uid] ?? 0);
            }
          }
        });
      },
      onError: (_) {
        if (mounted) setState(() => _chatsLoading = false);
      },
    );
  }

  // ââ Nachrichten-Stream ââââââââââââââââââââââââââââââââââââââââââââââââââââ
  void _subscribeToMessages(String chatId) {
    _messagesSub?.cancel();
    if (mounted) {
      setState(() {
        _messages = [];
        _messagesLoading = true;
        _messagesError = false;
      });
    }

    _messagesSub = _chatService
        .streamMessages(widget.companyId, chatId)
        .listen(
      (msgs) {
        if (!mounted) return;
        final wasShort = _messages.length < msgs.length;
        // Pending entfernen, wenn Nachricht aus Stream von uns (nach Offline-Versand)
        final currentUid = _chatService.userId;
        if (currentUid != null && _selectedChatId != null) {
          for (final m in msgs) {
            if (m.from == currentUid && m.text != null && m.text!.isNotEmpty) {
              final idx = _pendingMessages.indexWhere((p) =>
                  p['chatId'] == _selectedChatId &&
                  p['text'] == m.text);
              if (idx >= 0) _pendingMessages.removeAt(idx);
            }
          }
        }
        setState(() {
          _messages = msgs;
          _messagesLoading = false;
        });
        // Auto-Scroll: nur wenn neue Nachricht am Ende ankam
        // oder Chat gerade frisch geöffnet wurde
        if (wasShort && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0, // reverse:true â 0 == unterste Nachricht
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() {
          _messagesLoading = false;
          _messagesError = true;
        });
      },
    );
  }

  void _unsubscribeFromMessages() {
    _messagesSub?.cancel();
    _messagesSub = null;
    if (mounted) setState(() {
      _messages = [];
      _messagesLoading = false;
      _messagesError = false;
    });
  }

  // ââ Web Tab-Visibility ââââââââââââââââââââââââââââââââââââââââââââââââââââ
  void _setupVisibilityRefresh() {
    _visibilityCallback = () {
      if (_selectedChatId != null && mounted) {
        // Stream läuft schon â nur markChatRead erneut aufrufen
        _chatService.markChatReadPublic(widget.companyId, _selectedChatId!);
      }
    };
    visibility_refresh.setOnVisible(_visibilityCallback!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _selectedChatId != null && mounted) {
      _chatService.markChatReadPublic(widget.companyId, _selectedChatId!);
    }
  }

  @override
  void dispose() {
    _pendingCheckTimer?.cancel();
    if (_visibilityCallback != null) {
      visibility_refresh.removeOnVisible(_visibilityCallback!);
    }
    WidgetsBinding.instance.removeObserver(this);
    _chatsSub?.cancel();
    _messagesSub?.cancel();
    _scrollController.dispose();
    _messageController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  // ââ Chat auswÃ¤hlen ââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  void _selectChat(ChatModel chat) {
    final uid = _chatService.userId ?? '';
    widget.onChatOpened?.call(chat.id, chat.unreadCount[uid] ?? 0);
    setState(() {
      _selectedChatId = chat.id;
      _selectedChat = chat;
    });
    _subscribeToMessages(chat.id);
  }

  void _deselectChat() {
    setState(() {
      _selectedChatId = null;
      _selectedChat = null;
      _pendingMessages.clear();
    });
    _unsubscribeFromMessages();
  }

  // ââ Hilfsmethoden âââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  String _chatDisplayName(ChatModel chat) {
    if (chat.name != null && chat.name!.isNotEmpty) return chat.name!;
    final uid = _chatService.userId ?? '';
    final others = chat.participantNames.where((p) => p.uid != uid).toList();
    return others.map((p) => p.name).where((n) => n.isNotEmpty).join(', ').isNotEmpty
        ? others.map((p) => p.name).where((n) => n.isNotEmpty).join(', ')
        : 'Chat';
  }

  /// Kombiniert Firestore-Nachrichten mit ausstehenden (Offline-Queue), sortiert nach Zeit.
  List<({ChatMessage? message, Map<String, dynamic>? pending})> _getDisplayMessages() {
    final pendingForChat = _pendingMessages
        .where((p) => p['chatId'] == _selectedChatId)
        .map((p) => (message: null as ChatMessage?, pending: Map<String, dynamic>.from(p)))
        .toList();
    final fromFirestore = _messages
        .map((m) => (message: m, pending: null as Map<String, dynamic>?))
        .toList();
    final combined = [...fromFirestore, ...pendingForChat];
    combined.sort((a, b) {
      final at = a.message?.createdAt ?? (a.pending!['createdAt'] as DateTime);
      final bt = b.message?.createdAt ?? (b.pending!['createdAt'] as DateTime);
      return at.compareTo(bt);
    });
    return combined;
  }

  /// WhatsApp-Style: 1 Haken=verschickt, 2 grau=zugestellt, 2 blau=gelesen.
  Widget _buildDeliveryStatus(bool isSent, ChatMessage? m, bool isPending) {
    if (!isSent || isPending || m == null) {
      if (isPending) {
        return Icon(Icons.schedule, size: 12, color: Colors.white.withOpacity(0.65));
      }
      return const SizedBox.shrink();
    }
    final uid = _chatService.userId;
    final chat = _selectedChat;
    if (uid == null || chat == null) {
      return Icon(Icons.done, size: 14, color: Colors.white.withOpacity(0.65));
    }
    final recipients = chat.participants.where((p) => p != uid).toList();
    final delivered = recipients.every((r) => m.deliveredTo.contains(r));
    final read = recipients.every((r) {
      final lr = chat.lastReadAt[r];
      if (lr == null || m.createdAt == null) return false;
      final lrAt = lr is Timestamp ? lr.toDate() : (lr is DateTime ? lr : null);
      return lrAt != null && !m.createdAt!.isAfter(lrAt);
    });
    final color = read ? Colors.blue.shade200 : Colors.white.withOpacity(0.65);
    // 1 Haken (grau) = gesendet, 2 Haken (grau) = zugestellt, 2 Haken (blau) = gelesen
    return Icon(
      (delivered || read) ? Icons.done_all : Icons.done,
      size: 14,
      color: color,
    );
  }

  String _formatTime(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) return 'Heute';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.day == yesterday.day && d.month == yesterday.month && d.year == yesterday.year) {
      return 'Gestern';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _getInitials(String name) {
    final s = name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').join('').toUpperCase();
    return s.length > 2 ? s.substring(0, 2) : (s.isEmpty ? '?' : s);
  }

  // ââ Mitarbeiter laden âââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Future<void> _loadMitarbeiter() async {
    setState(() => _loadingMitarbeiter = true);
    try {
      final list = await _chatService.loadMitarbeiter(widget.companyId);
      if (mounted) setState(() {
        _mitarbeiter = list;
        _loadingMitarbeiter = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMitarbeiter = false);
    }
  }

  Future<void> _openNewChat() async {
    _groupNameController.clear();
    _selectedGroupMembers.clear();
    setState(() {
      _showNewGroupModal = false;
      _showNewChatModal = true;
    });
    await _loadMitarbeiter();
  }

  Future<void> _openNewGroup() async {
    _groupNameController.clear();
    _selectedGroupMembers.clear();
    setState(() {
      _showNewChatModal = false;
      _showNewGroupModal = true;
    });
    await _loadMitarbeiter();
  }

  void _startDirectChat(MitarbeiterForChat m) async {
    await _chatService.startDirectChat(widget.companyId, m);
    if (!mounted) return;
    final chatId = ChatService.getDirectChatId(_chatService.userId!, m.uid);
    // Warte kurz bis streamChats das neue Dokument liefert
    final chat = _chats.where((c) => c.id == chatId).firstOrNull;
    setState(() => _showNewChatModal = false);
    if (chat != null) {
      _selectChat(chat);
    } else {
      // Noch nicht im Stream â direkt setzen, Stream holt es nach
      setState(() {
        _selectedChatId = chatId;
        _selectedChat = null;
      });
      _subscribeToMessages(chatId);
    }
  }

  void _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Gruppenname eingeben.')),
      );
      return;
    }
    if (_selectedGroupMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens einen Teilnehmer auswählen.')),
      );
      return;
    }
    try {
      final chatId = await _chatService.createGroupChat(
        widget.companyId, name, _selectedGroupMembers,
      );
      if (!mounted) return;
      setState(() => _showNewGroupModal = false);
      setState(() {
        _selectedChatId = chatId;
        _selectedChat = null;
      });
      _subscribeToMessages(chatId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  // ââ Bilder ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;
    final bytes = <Uint8List>[];
    for (final x in images) {
      final b = await x.readAsBytes();
      if (b.length <= 10 * 1024 * 1024) bytes.add(b);
    }
    if (mounted) setState(() => _pendingImages.addAll(bytes));
  }

  // ââ Nachricht senden ââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    if (_selectedChatId == null) return;

    _messageController.clear();
    final images = List<Uint8List>.from(_pendingImages);
    setState(() => _pendingImages = []);

    try {
      final resultId = await _chatService.sendMessageOrQueue(
        widget.companyId,
        _selectedChatId!,
        text,
        imageBytes: images.isNotEmpty ? images : null,
        imageNames: images.asMap().entries.map((e) => 'image_${e.key}.jpg').toList(),
      );
      if (resultId.startsWith('pending-') && mounted) {
        setState(() {
          _pendingMessages.add({
            'id': resultId,
            'chatId': _selectedChatId,
            'text': text,
            'hasImages': images.isNotEmpty,
            'createdAt': DateTime.now(),
          });
        });
      }
      // Stream liefert die neue Nachricht automatisch â kein manuelles Reload
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Senden fehlgeschlagen: $e')),
        );
      }
    }
  }

  // ââ AppBar ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  PreferredSizeWidget _buildAppBar(bool isNarrow, VoidCallback onBack) {
    if (isNarrow && _selectedChatId != null) {
      // Chat-Titel kommt aus _selectedChat (gecacht) â kein separater Stream
      final title = _selectedChat != null ? _chatDisplayName(_selectedChat!) : 'Chat';
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _deselectChat,
          color: AppTheme.primary,
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        scrolledUnderElevation: 1,
      );
    }
    return AppTheme.buildModuleAppBar(
      title: widget.title ?? 'Chat',
      onBack: onBack,
      actions: const [],
    );
  }

  // ââ Build âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final onBack = widget.onBack ?? () => Navigator.of(context).pop();

    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: _buildAppBar(isNarrow, onBack),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: isNarrow
                ? _selectedChatId == null
                    ? _buildChatList(isNarrow)
                    : _buildMessageView(isNarrow)
                : Row(
                    children: [
                      AnimatedContainer(
                        width: 320,
                        duration: const Duration(milliseconds: 200),
                        child: _buildChatList(isNarrow),
                      ),
                      Expanded(
                        child: _selectedChatId == null
                            ? _buildNoChatSelected(isNarrow)
                            : _buildMessageView(isNarrow),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );

    final content = Stack(
      children: [
        scaffold,
        if (_showNewChatModal) _buildNewChatModal(),
        if (_showNewGroupModal) _buildNewGroupModal(),
      ],
    );

    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selectedChatId != null) {
            _deselectChat();
          } else {
            widget.onBack!();
          }
        },
        child: content,
      );
    }
    return content;
  }

  // ââ Chat-Liste ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Widget _buildChatList(bool isNarrow) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Column(
        children: [
          // ââ Header ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nachrichten',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey[900],
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                _buildIconAction(Icons.edit_square, 'Neuer Chat', _openNewChat),
                const SizedBox(width: 6),
                _buildIconAction(Icons.group_add_outlined, 'Neue Gruppe', _openNewGroup),
                const SizedBox(width: 2),
              ],
            ),
          ),
          // ââ Liste ââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
          Expanded(
            child: _chatsLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _chats.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary.withOpacity(0.12),
                                      AppTheme.primary.withOpacity(0.06),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.forum_outlined,
                                    size: 32, color: AppTheme.primary.withOpacity(0.65)),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Noch keine Chats',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.grey[800],
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Starte einen neuen Chat oder\nerstelle eine Gruppe.',
                                style: TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _chats.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (_, i) {
                          final chat = _chats[i];
                          var unread = chat.unreadCount[_chatService.userId] ?? 0;
                          if (unread == 0 &&
                              chat.lastMessageFrom != null &&
                              chat.lastMessageFrom != _chatService.userId &&
                              chat.lastMessageAt != null) {
                            final lastRead = chat.lastReadAt[_chatService.userId];
                            DateTime? lastReadAt;
                            if (lastRead is Timestamp) lastReadAt = lastRead.toDate();
                            if (lastRead is DateTime) lastReadAt = lastRead;
                            if (lastReadAt == null || chat.lastMessageAt!.isAfter(lastReadAt)) {
                              unread = 1;
                            }
                          }
                          final hasUnread = unread > 0;
                          final name = _chatDisplayName(chat);
                          final isSelected = _selectedChatId == chat.id;

                          return Dismissible(
                            key: Key(chat.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            confirmDismiss: (_) async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  title: const Text('Chat löschen?'),
                                  content: const Text('Der Chat wird nur für dich entfernt.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Abbrechen'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: Text('Löschen',
                                          style: TextStyle(color: Colors.red.shade400)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _chatService.deleteChatForMe(widget.companyId, chat.id);
                                if (mounted && _selectedChatId == chat.id) _deselectChat();
                                return true;
                              }
                              return false;
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary.withOpacity(0.08)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: isSelected
                                    ? Border.all(color: AppTheme.primary.withOpacity(0.15), width: 1)
                                    : null,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _selectChat(chat),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 11),
                                  child: Row(
                                    children: [
                                      // Avatar
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppTheme.primary.withOpacity(0.8),
                                                  AppTheme.primary,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.primary.withOpacity(0.25),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              _getInitials(name),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          if (hasUnread)
                                            Positioned(
                                              top: -2,
                                              right: -2,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                      color: Colors.white, width: 1.5),
                                                ),
                                                constraints: const BoxConstraints(
                                                    minWidth: 18, minHeight: 18),
                                                child: Center(
                                                  child: Text(
                                                    '${unread > 99 ? "99+" : unread}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight: hasUnread
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      fontSize: 15,
                                                      color: Colors.grey[900],
                                                      letterSpacing: -0.1,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _formatTime(chat.lastMessageAt),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: hasUnread
                                                        ? AppTheme.primary
                                                        : Colors.grey[400],
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              chat.lastMessageText ?? 'Noch keine Nachrichten',
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: hasUnread
                                                    ? Colors.grey[700]
                                                    : Colors.grey[450],
                                                fontWeight: hasUnread
                                                    ? FontWeight.w500
                                                    : FontWeight.w400,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: AppTheme.primary),
        ),
      ),
    );
  }

  // ââ Kein Chat gewÃ¤hlt âââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Widget _buildNoChatSelected(bool isNarrow) {
    return Container(
      color: AppTheme.surfaceBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.12),
                    AppTheme.primary.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  size: 40, color: AppTheme.primary.withOpacity(0.55)),
            ),
            const SizedBox(height: 22),
            Text(
              'Wähle einen Chat aus',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'oder starte eine neue Unterhaltung.',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _openNewChat,
                  icon: const Icon(Icons.edit_square, size: 17),
                  label: const Text('Neuer Chat'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openNewGroup,
                  icon: const Icon(Icons.group_add_outlined, size: 17),
                  label: const Text('Neue Gruppe'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: AppTheme.primary.withOpacity(0.35)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ââ Nachrichtenansicht ââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Widget _buildMessageView(bool isNarrow) {
    if (_messagesError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Nachrichten konnten nicht geladen werden.',
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _subscribeToMessages(_selectedChatId!),
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ââ Chat-Header ââââââââââââââââââââââââââââââââââââââââââââââââââââââ
        if (_selectedChat != null && !isNarrow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primary.withOpacity(0.8), AppTheme.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getInitials(_chatDisplayName(_selectedChat!)),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _chatDisplayName(_selectedChat!),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.grey[900],
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // ââ Nachrichten ââââââââââââââââââââââââââââââââââââââââââââââââââââââ
        Expanded(
          child: Container(
            color: AppTheme.surfaceBg,
            child: _messagesLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _messages.isEmpty && _pendingMessages.where((p) => p['chatId'] == _selectedChatId).isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primary.withOpacity(0.10),
                                    AppTheme.primary.withOpacity(0.04),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.waving_hand_outlined,
                                  size: 28, color: AppTheme.primary.withOpacity(0.5)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Noch keine Nachrichten',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Schreib als Erstes!',
                              style: TextStyle(fontSize: 13, color: Colors.grey[450]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        reverse: true,
                        itemCount: _getDisplayMessages().length,
                        itemBuilder: (_, i) {
                          final items = _getDisplayMessages();
                          final item = items[items.length - 1 - i];
                          final m = item.message;
                          final pending = item.pending;
                          final text = m?.text ?? (pending?['text'] as String? ?? '');
                          final createdAt = m?.createdAt ?? (pending?['createdAt'] as DateTime?);
                          final isSent = m != null ? m.from == _chatService.userId : true;
                          final isPending = pending != null;
                          // Datum-Trennlinie
                          final showDate = i == items.length - 1 ||
                              (items[items.length - 2 - i].message?.createdAt?.day ??
                                  (items[items.length - 2 - i].pending?['createdAt'] as DateTime?)?.day) !=
                                  createdAt?.day;
                          return Column(
                            crossAxisAlignment:
                                isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (showDate && createdAt != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _formatDate(createdAt),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.2),
                                      ),
                                    ),
                                  ),
                                ),
                              Align(
                                alignment:
                                    isSent ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: EdgeInsets.only(
                                    bottom: 4,
                                    left: isSent ? 60 : 0,
                                    right: isSent ? 0 : 60,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSent
                                        ? AppTheme.primary
                                        : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(20),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: Radius.circular(isSent ? 20 : 5),
                                      bottomRight: Radius.circular(isSent ? 5 : 20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isSent
                                            ? AppTheme.primary.withOpacity(0.20)
                                            : Colors.black.withOpacity(0.06),
                                        blurRadius: isSent ? 10 : 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (text.isNotEmpty)
                                        Text(
                                          text,
                                          style: TextStyle(
                                            color: isSent ? Colors.white : Colors.grey[900],
                                            fontSize: 14.5,
                                            height: 1.45,
                                          ),
                                        ),
                                      if (m?.attachments != null)
                                        for (final a in m!.attachments!)
                                          if ((a.type).startsWith('image/'))
                                            Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: GestureDetector(
                                                onTap: () {},
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.network(
                                                    a.url,
                                                    fit: BoxFit.contain,
                                                    height: 150,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'ð ${a.name}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: isSent
                                                      ? Colors.white70
                                                      : Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                      if (pending != null && (pending['hasImages'] == true))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '📎 Bild(er) werden bei Netzverbindung gesendet',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSent
                                                  ? Colors.white70
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTime(createdAt),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isSent
                                                    ? Colors.white.withOpacity(0.65)
                                                    : Colors.grey[400],
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            if (isSent) ...[
                                              const SizedBox(width: 4),
                                              _buildDeliveryStatus(isSent, m, isPending),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ),
        // ââ Eingabebereich ââââââââââââââââââââââââââââââââââââââââââââââââââ
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade100)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                _pendingImages[i],
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _pendingImages.removeAt(i)),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.cancel,
                                      color: Colors.red.shade400, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Anhänge-Button
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _pickImages,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add_photo_alternate_outlined,
                              size: 20, color: Colors.grey[600]),
                        ),
                      ),
                    ),
                    // Texteingabe
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.grey.shade200, width: 1),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Nachricht...',
                            hintStyle: TextStyle(
                                color: Colors.grey[400], fontSize: 14.5),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 14.5),
                          maxLines: 4,
                          minLines: 1,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    // Senden-Button
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _sendMessage,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.send_rounded,
                            size: 19, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ââ Neuer-Chat-Modal ââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Widget _buildNewChatModal() {
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_comment_outlined,
                          size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Chat starten',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[400]),
                      onPressed: () => setState(() => _showNewChatModal = false),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade100),
              // Liste
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _mitarbeiter.length,
                        itemBuilder: (_, i) {
                          final m = _mitarbeiter[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _startDirectChat(m),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppTheme.primary.withOpacity(0.7),
                                          AppTheme.primary,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _getInitials(m.name),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[900],
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Colors.grey[300], size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ââ Neue-Gruppe-Modal âââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Widget _buildNewGroupModal() {
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.group_add_outlined,
                          size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Neue Gruppe',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[400]),
                      onPressed: () => setState(() => _showNewGroupModal = false),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade100),
              // Gruppenname
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  controller: _groupNameController,
                  decoration: InputDecoration(
                    labelText: 'Gruppenname',
                    hintText: 'z.B. Rettungsteam A',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Teilnehmer wählen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_selectedGroupMembers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_selectedGroupMembers.length} gewählt',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Mitarbeiterliste
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        itemCount: _mitarbeiter.length,
                        itemBuilder: (_, i) {
                          final m = _mitarbeiter[i];
                          final selected =
                              _selectedGroupMembers.any((s) => s.uid == m.uid);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  _selectedGroupMembers
                                      .removeWhere((s) => s.uid == m.uid);
                                } else {
                                  _selectedGroupMembers.add(m);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.primary.withOpacity(0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: selected
                                          ? LinearGradient(
                                              colors: [
                                                AppTheme.primary.withOpacity(0.7),
                                                AppTheme.primary,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      color: selected
                                          ? null
                                          : AppTheme.primary.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _getInitials(m.name),
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: Colors.grey[900],
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: selected
                                        ? const Icon(Icons.check_circle,
                                            color: AppTheme.primary, size: 22,
                                            key: ValueKey('checked'))
                                        : Icon(Icons.circle_outlined,
                                            color: Colors.grey[300], size: 22,
                                            key: const ValueKey('unchecked')),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _createGroup,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Gruppe erstellen',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
