import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../utils/visibility_refresh_stub.dart'
    if (dart.library.html) '../utils/visibility_refresh_web.dart' as visibility_refresh;

// ─────────────────────────────────────────────────────────────────────────────
//  Design-System  (Dark Professional – Rettungsdienst)
// ─────────────────────────────────────────────────────────────────────────────
class _D {
  static const bgDeep    = Color(0xFF0D1117);   // Haupt-Hintergrund
  static const bgPanel   = Color(0xFF161B22);   // Seitenpanel / Bars
  static const bgCard    = Color(0xFF1C2333);   // Karten / aktive Items
  static const bgInput   = Color(0xFF21262D);   // Eingabefelder
  static const bgModal   = Color(0xFF1C2333);   // Modals

  static const accent    = Color(0xFFCF3636);   // Signalrot
  static const accentLt  = Color(0xFFE05555);
  static const accentBg  = Color(0x1ACF3636);

  static const sentBubble  = Color(0xFF1D3557);
  static const sentText    = Color(0xFFE8EDF2);
  static const recvBubble  = Color(0xFF21262D);
  static const recvText    = Color(0xFFCDD5E0);

  static const textPrimary   = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted     = Color(0xFF484F58);

  static const border  = Color(0xFF30363D);

  static const radius   = 14.0;
  static const radiusSm = 8.0;
  static const radiusXl = 20.0;
}

/// Chat-Modul – natives Flutter ohne WebView.
class ChatScreen extends StatefulWidget {
  final String companyId;
  final String? initialChatId;
  final String? title;
  final VoidCallback? onBack;
  final bool hideAppBar;
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
  final _scrollController  = ScrollController();
  final _focusNode          = FocusNode();

  String? _selectedChatId;
  Future<List<ChatMessage>>? _messagesFuture;
  Timer? _refreshTimer;
  void Function()? _visibilityCallback;
  bool _inputFocused = false;
  bool _initialBadgeResetDone = false;

  // Modal-State
  List<MitarbeiterForChat> _mitarbeiter = [];
  List<Uint8List>           _pendingImages = [];
  bool _loadingMitarbeiter  = false;
  bool _showNewChatModal    = false;
  bool _showNewGroupModal   = false;
  final _groupNameController = TextEditingController();
  final List<MitarbeiterForChat> _selectedGroupMembers = [];

  // ── Lifecycle ────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(() {
      if (mounted) setState(() => _inputFocused = _focusNode.hasFocus);
    });
    if (kIsWeb) _setupVisibilityRefresh();
    if (widget.initialChatId != null && widget.initialChatId!.isNotEmpty) {
      _selectedChatId = widget.initialChatId;
      _refreshMessages();
      _startRefreshTimer();
      unawaited(_chatService.streamChats(widget.companyId).first.then((chats) {
        final chat = chats.where((c) => c.id == widget.initialChatId).firstOrNull;
        if (chat != null) {
          final uid = _chatService.userId ?? '';
          widget.onChatOpened?.call(chat.id, chat.unreadCount[uid] ?? 0);
        }
      }));
    }
  }

  void _setupVisibilityRefresh() {
    if (!kIsWeb) return;
    _visibilityCallback = () {
      if (_selectedChatId != null && mounted) _refreshMessages();
    };
    visibility_refresh.setOnVisible(_visibilityCallback!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _selectedChatId != null && mounted) {
      _refreshMessages();
    }
  }

  @override
  void dispose() {
    if (_visibilityCallback != null) visibility_refresh.removeOnVisible(_visibilityCallback!);
    WidgetsBinding.instance.removeObserver(this);
    _stopRefreshTimer();
    _messageController.dispose();
    _groupNameController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Timer / Refresh ──────────────────────────────────────
  void _refreshMessages() {
    if (_selectedChatId == null) return;
    _messagesFuture = _chatService.loadMessages(widget.companyId, _selectedChatId!);
    if (mounted) setState(() {});
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_selectedChatId != null && mounted) _refreshMessages();
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _initialBadgeResetDone = false;
  }

  // ── Helpers ──────────────────────────────────────────────
  String _chatDisplayName(ChatModel chat) {
    if (chat.name != null && chat.name!.isNotEmpty) return chat.name!;
    final uid = _chatService.userId ?? '';
    final others = chat.participantNames.where((p) => p.uid != uid).toList();
    return others.map((p) => p.name).where((n) => n.isNotEmpty).join(', ');
  }

  String _formatTime(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  String _getInitials(String name) {
    final s = name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').join('').toUpperCase();
    return s.length > 2 ? s.substring(0, 2) : (s.isEmpty ? '?' : s);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _D.textPrimary)),
      backgroundColor: _D.bgCard,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_D.radiusSm)),
    ));
  }

  // ── Aktionen ─────────────────────────────────────────────
  Future<void> _loadMitarbeiter() async {
    setState(() => _loadingMitarbeiter = true);
    try {
      final list = await _chatService.loadMitarbeiter(widget.companyId);
      if (mounted) setState(() { _mitarbeiter = list; _loadingMitarbeiter = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMitarbeiter = false);
    }
  }

  Future<void> _openNewChat() async {
    _groupNameController.clear(); _selectedGroupMembers.clear();
    setState(() { _showNewGroupModal = false; _showNewChatModal = true; });
    await _loadMitarbeiter();
  }

  Future<void> _openNewGroup() async {
    _groupNameController.clear(); _selectedGroupMembers.clear();
    setState(() { _showNewChatModal = false; _showNewGroupModal = true; });
    await _loadMitarbeiter();
  }

  void _startDirectChat(MitarbeiterForChat m) async {
    await _chatService.startDirectChat(widget.companyId, m);
    if (!mounted) return;
    final chatId = ChatService.getDirectChatId(_chatService.userId!, m.uid);
    setState(() {
      _showNewChatModal = false;
      _selectedChatId = chatId;
      _refreshMessages();
      _startRefreshTimer();
    });
  }

  void _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) { _showSnack('Bitte Gruppenname eingeben.'); return; }
    if (_selectedGroupMembers.isEmpty) { _showSnack('Bitte mindestens einen Teilnehmer wählen.'); return; }
    try {
      final chatId = await _chatService.createGroupChat(widget.companyId, name, _selectedGroupMembers);
      if (!mounted) return;
      setState(() {
        _showNewGroupModal = false;
        _selectedChatId = chatId;
        _refreshMessages();
        _startRefreshTimer();
      });
    } catch (e) {
      if (mounted) _showSnack('Fehler: $e');
    }
  }

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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    if (_selectedChatId == null) return;
    _messageController.clear();
    final images = List<Uint8List>.from(_pendingImages);
    setState(() => _pendingImages = []);
    try {
      await _chatService.sendMessage(
        widget.companyId, _selectedChatId!, text,
        imageBytes: images.isNotEmpty ? images : null,
        imageNames: images.asMap().entries.map((e) => 'image_${e.key}.jpg').toList(),
      );
      if (mounted) setState(() => _refreshMessages());
    } catch (e) {
      if (mounted) _showSnack('Senden fehlgeschlagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  //  WIDGETS
  // ══════════════════════════════════════════════════════════

  // ── AppBar ───────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(bool isNarrow, VoidCallback onBack) {
    if (isNarrow && _selectedChatId != null) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: StreamBuilder<List<ChatModel>>(
          stream: _chatService.streamChats(widget.companyId),
          builder: (context, snap) {
            ChatModel? chat;
            for (final c in snap.data ?? []) {
              if (c.id == _selectedChatId) { chat = c; break; }
            }
            final name = chat != null ? _chatDisplayName(chat) : 'Chat';
            final isGroup = chat?.name != null && chat!.name!.isNotEmpty;
            return AppBar(
              backgroundColor: _D.bgPanel,
              foregroundColor: _D.textPrimary,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => setState(() { _selectedChatId = null; _stopRefreshTimer(); }),
                color: _D.textSecondary,
              ),
              title: Row(children: [
                _avatar(_getInitials(name), radius: 17, isGroup: isGroup),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: 0.1)),
                ),
              ]),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: _D.border),
              ),
            );
          },
        ),
      );
    }
    return AppTheme.buildModuleAppBar(
      title: widget.title ?? 'Chat',
      onBack: onBack,
      actions: [
        _appBarBtn(Icons.add_comment_outlined, 'Neuer Chat', _openNewChat),
        _appBarBtn(Icons.group_add_outlined, 'Neue Gruppe', _openNewGroup),
      ],
    );
  }

  Widget _appBarBtn(IconData icon, String tip, VoidCallback fn) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(_D.radiusSm),
        onTap: fn,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: _D.textSecondary),
        ),
      ),
    ),
  );

  // ── Avatar ───────────────────────────────────────────────
  Widget _avatar(String initials, {double radius = 20, bool isGroup = false}) {
    return Container(
      width: radius * 2, height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: isGroup
              ? [const Color(0xFF2D4A6B), const Color(0xFF1D3557)]
              : [const Color(0xFF8B2020), const Color(0xFF5C1010)],
        ),
        boxShadow: [BoxShadow(color: _D.accent.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontSize: radius * 0.65, fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final onBack   = widget.onBack ?? () => Navigator.of(context).pop();

    final scaffold = Scaffold(
      backgroundColor: _D.bgDeep,
      appBar: _buildAppBar(isNarrow, onBack),
      body: isNarrow
          ? _selectedChatId == null ? _buildChatList(isNarrow) : _buildMessageView(isNarrow)
          : Row(children: [
              SizedBox(width: 320, child: _buildChatList(isNarrow)),
              Expanded(child: _selectedChatId == null ? _buildNoChatSelected() : _buildMessageView(isNarrow)),
            ]),
    );

    final content = Stack(children: [
      scaffold,
      if (_showNewChatModal) _buildNewChatModal(),
      if (_showNewGroupModal) _buildNewGroupModal(),
    ]);

    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selectedChatId != null) {
            setState(() { _selectedChatId = null; _stopRefreshTimer(); });
          } else {
            widget.onBack!();
          }
        },
        child: content,
      );
    }
    return content;
  }

  // ── Chat-Liste ───────────────────────────────────────────
  Widget _buildChatList(bool isNarrow) {
    return Container(
      decoration: const BoxDecoration(
        color: _D.bgPanel,
        border: Border(right: BorderSide(color: _D.border)),
      ),
      child: Column(children: [
        // Kopfzeile
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _D.border))),
          child: Row(children: [
            const Expanded(
              child: Text('Nachrichten',
                style: TextStyle(color: _D.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            ),
            _iconBtn(Icons.person_add_outlined, 'Neuer Chat', _openNewChat),
            const SizedBox(width: 6),
            _iconBtn(Icons.group_add_outlined,  'Neue Gruppe', _openNewGroup),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<ChatModel>>(
            stream: _chatService.streamChats(widget.companyId),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: _D.accent, strokeWidth: 2));
              final chats = snap.data!;
              if (chats.isEmpty) return _emptyList();
              return ListView.builder(
                itemCount: chats.length,
                itemBuilder: (_, i) => _chatTile(chats[i], isNarrow),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback fn) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(_D.radiusSm),
      onTap: fn,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: _D.bgCard,
          borderRadius: BorderRadius.circular(_D.radiusSm),
          border: Border.all(color: _D.border),
        ),
        child: Icon(icon, size: 18, color: _D.textSecondary),
      ),
    ),
  );

  Widget _emptyList() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: _D.bgCard, shape: BoxShape.circle, border: Border.all(color: _D.border)),
          child: const Icon(Icons.chat_bubble_outline_rounded, size: 28, color: _D.textMuted),
        ),
        const SizedBox(height: 16),
        const Text('Keine Chats', style: TextStyle(color: _D.textSecondary, fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('Starte einen neuen Chat\noder erstelle eine Gruppe.',
          style: TextStyle(color: _D.textMuted, fontSize: 13), textAlign: TextAlign.center),
      ]),
    ),
  );

  Widget _chatTile(ChatModel chat, bool isNarrow) {
    var unread = chat.unreadCount[_chatService.userId] ?? 0;
    if (unread == 0 && chat.lastMessageFrom != null &&
        chat.lastMessageFrom != _chatService.userId && chat.lastMessageAt != null) {
      final lr = chat.lastReadAt[_chatService.userId];
      DateTime? lrAt;
      if (lr is Timestamp) lrAt = lr.toDate();
      if (lr is DateTime)  lrAt = lr;
      if (lrAt == null || chat.lastMessageAt!.isAfter(lrAt)) unread = 1;
    }
    final hasUnread  = unread > 0;
    final isSelected = _selectedChatId == chat.id;
    final displayName = _chatDisplayName(chat);
    final isGroup = chat.name != null && chat.name!.isNotEmpty;

    return Dismissible(
      key: Key(chat.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: const Color(0xFF8B1A1A),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => _confirmDialog(ctx,
            title: 'Chat entfernen',
            content: 'Chat aus deiner Liste entfernen?\n(Für andere weiterhin sichtbar)',
            confirmLabel: 'Entfernen', isDanger: true),
        ) ?? false;
      },
      onDismissed: (_) async {
        await _chatService.deleteChatForMe(widget.companyId, chat.id);
        if (mounted && _selectedChatId == chat.id) setState(() { _selectedChatId = null; _stopRefreshTimer(); });
      },
      child: InkWell(
        onTap: () {
          final uid = _chatService.userId ?? '';
          widget.onChatOpened?.call(chat.id, chat.unreadCount[uid] ?? 0);
          setState(() { _selectedChatId = chat.id; _refreshMessages(); _startRefreshTimer(); });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? _D.accentBg : (hasUnread ? _D.bgCard.withOpacity(0.4) : Colors.transparent),
            border: Border(left: BorderSide(color: isSelected ? _D.accent : Colors.transparent, width: 3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            // Avatar + Badge
            Stack(clipBehavior: Clip.none, children: [
              _avatar(_getInitials(displayName), radius: 22, isGroup: isGroup),
              if (hasUnread) Positioned(
                top: -3, right: -3,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: _D.accent, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  alignment: Alignment.center,
                  child: Text('${unread > 99 ? "99+" : unread}',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: Text(displayName, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasUnread ? _D.textPrimary : _D.textSecondary,
                    fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14, letterSpacing: 0.1,
                  ))),
                Text(_formatTime(chat.lastMessageAt),
                  style: TextStyle(fontSize: 11,
                    color: hasUnread ? _D.accent : _D.textMuted,
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400)),
              ]),
              const SizedBox(height: 3),
              Text(chat.lastMessageText ?? 'Keine Nachrichten',
                overflow: TextOverflow.ellipsis, maxLines: 1,
                style: TextStyle(fontSize: 12.5, color: hasUnread ? _D.textSecondary : _D.textMuted)),
            ])),
          ]),
        ),
      ),
    );
  }

  // ── Kein Chat gewählt ────────────────────────────────────
  Widget _buildNoChatSelected() => Container(
    color: _D.bgDeep,
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF8B2020), Color(0xFF3D0D0D)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _D.accent.withOpacity(0.3), blurRadius: 24, spreadRadius: 2)],
          ),
          child: const Icon(Icons.forum_outlined, size: 36, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text('Wähle einen Chat',
          style: TextStyle(color: _D.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        const SizedBox(height: 8),
        const Text('oder starte eine neue Unterhaltung.',
          style: TextStyle(color: _D.textMuted, fontSize: 14)),
        const SizedBox(height: 28),
        Wrap(spacing: 12, runSpacing: 10, alignment: WrapAlignment.center, children: [
          _actionBtn(Icons.add_comment_outlined, 'Neuer Chat', _openNewChat, filled: true),
          _actionBtn(Icons.group_add_outlined,   'Neue Gruppe', _openNewGroup),
        ]),
      ]),
    ),
  );

  Widget _actionBtn(IconData icon, String label, VoidCallback fn, {bool filled = false}) => InkWell(
    borderRadius: BorderRadius.circular(_D.radiusSm),
    onTap: fn,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: filled ? _D.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(_D.radiusSm),
        border: Border.all(color: filled ? _D.accent : _D.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: filled ? Colors.white : _D.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: filled ? Colors.white : _D.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  // ── Nachrichtenansicht ───────────────────────────────────
  Widget _buildMessageView(bool isNarrow) {
    final chatId = _selectedChatId!;
    return Container(
      color: _D.bgDeep,
      child: StreamBuilder<List<ChatModel>>(
        stream: _chatService.streamChats(widget.companyId),
        builder: (context, chatSnap) {
          ChatModel? currentChat;
          for (final c in chatSnap.data ?? []) {
            if (c.id == chatId) { currentChat = c; break; }
          }
          return Column(children: [
            if (!isNarrow) _chatHeader(currentChat),
            Expanded(
              child: FutureBuilder<List<ChatMessage>>(
                future: _messagesFuture ?? _chatService.loadMessages(widget.companyId, chatId),
                builder: (context, snap) {
                  if (snap.hasError) return _errorView(snap.error);
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: _D.accent, strokeWidth: 2));
                  final msgs = snap.data!;
                  if (msgs.isEmpty) return _emptyMessages();
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    reverse: true,
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m = msgs[msgs.length - 1 - i];
                      return _bubble(m, m.from == _chatService.userId);
                    },
                  );
                },
              ),
            ),
            _inputArea(),
          ]);
        },
      ),
    );
  }

  Widget _chatHeader(ChatModel? chat) {
    final name = chat != null ? _chatDisplayName(chat) : 'Chat';
    final isGroup = chat?.name != null && chat!.name!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _D.bgPanel,
        border: Border(bottom: BorderSide(color: _D.border)),
      ),
      child: Row(children: [
        _avatar(_getInitials(name), radius: 19, isGroup: isGroup),
        const SizedBox(width: 12),
        Expanded(child: Text(name,
          style: const TextStyle(color: _D.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1))),
      ]),
    );
  }

  Widget _bubble(ChatMessage m, bool isSent) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        child: Container(
          decoration: BoxDecoration(
            color: isSent ? _D.sentBubble : _D.recvBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(_D.radius),
              topRight: const Radius.circular(_D.radius),
              bottomLeft: Radius.circular(isSent ? _D.radius : 4),
              bottomRight: Radius.circular(isSent ? 4 : _D.radius),
            ),
            border: Border.all(
              color: isSent ? const Color(0xFF2D4F7A) : _D.border, width: 0.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // Absendername in Gruppen
            if (!isSent && m.senderName != null && m.senderName!.isNotEmpty) ...[
              Text(m.senderName!,
                style: const TextStyle(color: _D.accent, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
              const SizedBox(height: 4),
            ],
            // Text
            if (m.text != null && m.text!.isNotEmpty)
              Text(m.text!,
                style: TextStyle(color: isSent ? _D.sentText : _D.recvText, fontSize: 14.5, height: 1.4)),
            // Anhänge
            if (m.attachments != null)
              for (final a in m.attachments!)
                if (a.type.startsWith('image/'))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_D.radiusSm),
                      child: Image.network(a.url, fit: BoxFit.cover, height: 180, width: double.infinity),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.attach_file_rounded, size: 14,
                        color: isSent ? _D.sentText.withOpacity(0.7) : _D.textMuted),
                      const SizedBox(width: 4),
                      Text(a.name,
                        style: TextStyle(fontSize: 12.5,
                          color: isSent ? _D.sentText.withOpacity(0.8) : _D.textSecondary)),
                    ]),
                  ),
            // Zeit + Status
            const SizedBox(height: 5),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_formatTime(m.createdAt),
                style: TextStyle(fontSize: 10.5,
                  color: isSent ? _D.sentText.withOpacity(0.5) : _D.textMuted)),
              if (isSent) ...[const SizedBox(width: 4), _statusIcon(m)],
            ]),
          ]),
        ),
      ),
    ),
  );

  Widget _statusIcon(ChatMessage m) {
    // Kein id → noch nicht gespeichert (pending)
    if (m.id.isEmpty)
      return Icon(Icons.schedule_rounded, size: 12, color: _D.sentText.withOpacity(0.4));
    // deliveredTo nicht leer → zugestellt
    if (m.deliveredTo.isNotEmpty)
      return Icon(Icons.done_all_rounded, size: 13, color: _D.sentText.withOpacity(0.5));
    // Gespeichert, aber noch nicht zugestellt
    return Icon(Icons.done_rounded, size: 12, color: _D.sentText.withOpacity(0.4));
  }

  Widget _errorView(Object? err) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFF8B2020)),
    const SizedBox(height: 12),
    const Text('Nachrichten konnten nicht geladen werden.',
      style: TextStyle(color: _D.textSecondary, fontSize: 14), textAlign: TextAlign.center),
    const SizedBox(height: 6),
    Text('$err', style: const TextStyle(fontSize: 11, color: _D.textMuted), textAlign: TextAlign.center),
  ]));

  Widget _emptyMessages() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 56, height: 56,
      decoration: BoxDecoration(color: _D.bgCard, shape: BoxShape.circle, border: Border.all(color: _D.border)),
      child: const Icon(Icons.waving_hand_rounded, size: 24, color: _D.textMuted),
    ),
    const SizedBox(height: 14),
    const Text('Noch keine Nachrichten',
      style: TextStyle(color: _D.textSecondary, fontWeight: FontWeight.w600, fontSize: 15)),
    const SizedBox(height: 6),
    const Text('Starte die Unterhaltung!', style: TextStyle(color: _D.textMuted, fontSize: 13)),
  ]));

  // ── Eingabebereich ───────────────────────────────────────
  Widget _inputArea() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: const BoxDecoration(
      color: _D.bgPanel,
      border: Border(top: BorderSide(color: _D.border)),
    ),
    child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Bild-Vorschau
      if (_pendingImages.isNotEmpty)
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _pendingImages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            padding: const EdgeInsets.only(bottom: 6),
            itemBuilder: (_, i) => Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(_D.radiusSm),
                child: Image.memory(_pendingImages[i], width: 58, height: 58, fit: BoxFit.cover),
              ),
              Positioned(
                top: -5, right: -5,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(i)),
                  child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(color: _D.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),

      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Anhang
        _inputRoundBtn(Icons.add_rounded, _pickImages),
        const SizedBox(width: 8),
        // Textfeld
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _D.bgInput,
              borderRadius: BorderRadius.circular(_D.radiusXl),
              border: Border.all(
                color: _inputFocused ? _D.accent.withOpacity(0.6) : _D.border,
                width: _inputFocused ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              maxLines: 4, minLines: 1, maxLength: 4000,
              onSubmitted: (_) => _sendMessage(),
              style: const TextStyle(color: _D.textPrimary, fontSize: 14.5, height: 1.4),
              decoration: const InputDecoration(
                hintText: 'Nachricht ...',
                hintStyle: TextStyle(color: _D.textMuted, fontSize: 14.5),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                counterText: '',
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Senden
        GestureDetector(
          onTap: _sendMessage,
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_D.accentLt, _D.accent],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _D.accent.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
          ),
        ),
      ]),
    ])),
  );

  Widget _inputRoundBtn(IconData icon, VoidCallback fn) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: _D.bgInput, shape: BoxShape.circle, border: Border.all(color: _D.border)),
      child: Icon(icon, size: 20, color: _D.textSecondary),
    ),
  );

  // ── Modals ───────────────────────────────────────────────
  Widget _buildNewChatModal() => _modalShell(
    title: 'Chat starten', subtitle: 'Mitarbeiter auswählen',
    icon: Icons.person_add_outlined,
    onClose: () => setState(() => _showNewChatModal = false),
    child: _loadingMitarbeiter
        ? const Center(child: Padding(padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: _D.accent, strokeWidth: 2)))
        : ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: _mitarbeiter.length,
            itemBuilder: (_, i) {
              final m = _mitarbeiter[i];
              return _mitarbeiterTile(m.name, onTap: () => _startDirectChat(m));
            },
          ),
  );

  Widget _buildNewGroupModal() => _modalShell(
    title: 'Gruppe erstellen', subtitle: 'Name und Mitglieder wählen',
    icon: Icons.group_add_outlined,
    onClose: () => setState(() => _showNewGroupModal = false),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GestureDetector(
        onTap: _createGroup,
        child: Container(
          width: double.infinity, height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_D.accentLt, _D.accent]),
            borderRadius: BorderRadius.circular(_D.radiusSm),
            boxShadow: [BoxShadow(color: _D.accent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          alignment: Alignment.center,
          child: const Text('Gruppe erstellen',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
        ),
      ),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: TextField(
          controller: _groupNameController,
          style: const TextStyle(color: _D.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'z.B. Rettungsteam Alpha',
            hintStyle: const TextStyle(color: _D.textMuted),
            labelText: 'Gruppenname',
            labelStyle: const TextStyle(color: _D.textSecondary, fontSize: 13),
            filled: true, fillColor: _D.bgInput,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(_D.radiusSm),
              borderSide: const BorderSide(color: _D.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_D.radiusSm),
              borderSide: const BorderSide(color: _D.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_D.radiusSm),
              borderSide: const BorderSide(color: _D.accent, width: 1.5)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 10),
        child: Text(
          'MITGLIEDER${_selectedGroupMembers.isNotEmpty ? " (${_selectedGroupMembers.length})" : ""}',
          style: const TextStyle(color: _D.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      if (_loadingMitarbeiter)
        const Center(child: Padding(padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: _D.accent, strokeWidth: 2)))
      else
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _mitarbeiter.length,
          itemBuilder: (_, i) {
            final m = _mitarbeiter[i];
            final sel = _selectedGroupMembers.any((s) => s.uid == m.uid);
            return _mitarbeiterTile(m.name, selected: sel,
              onTap: () => setState(() {
                if (sel) _selectedGroupMembers.removeWhere((s) => s.uid == m.uid);
                else _selectedGroupMembers.add(m);
              }));
          },
        ),
    ]),
  );

  Widget _modalShell({
    required String title, required String subtitle, required IconData icon,
    required VoidCallback onClose, required Widget child, Widget? footer,
  }) => Material(
    color: Colors.black.withOpacity(0.65),
    child: Center(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
      decoration: BoxDecoration(
        color: _D.bgModal,
        borderRadius: BorderRadius.circular(_D.radius),
        border: Border.all(color: _D.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 32, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_D.radius),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _D.border))),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _D.accentBg, borderRadius: BorderRadius.circular(_D.radiusSm),
                  border: Border.all(color: _D.accent.withOpacity(0.3))),
                child: Icon(icon, size: 18, color: _D.accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: _D.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(color: _D.textMuted, fontSize: 12)),
              ])),
              InkWell(
                borderRadius: BorderRadius.circular(_D.radiusSm),
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded, size: 18, color: _D.textSecondary),
                ),
              ),
            ]),
          ),
          Flexible(child: SingleChildScrollView(child: child)),
          if (footer != null) footer,
        ]),
      ),
    )),
  );

  Widget _mitarbeiterTile(String name, {bool selected = false, required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? _D.accentBg : Colors.transparent,
        border: Border(top: BorderSide(color: _D.border.withOpacity(0.5))),
      ),
      child: Row(children: [
        _avatar(_getInitials(name), radius: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(name,
          style: TextStyle(
            color: selected ? _D.textPrimary : _D.textSecondary,
            fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
        if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: _D.accent),
      ]),
    ),
  );

  // ── Confirm-Dialog ───────────────────────────────────────
  Widget _confirmDialog(BuildContext ctx, {
    required String title, required String content,
    required String confirmLabel, bool isDanger = false,
  }) => AlertDialog(
    backgroundColor: _D.bgModal,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_D.radius), side: const BorderSide(color: _D.border)),
    title: Text(title, style: const TextStyle(color: _D.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
    content: Text(content, style: const TextStyle(color: _D.textSecondary, fontSize: 13.5)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: const Text('Abbrechen', style: TextStyle(color: _D.textSecondary))),
      TextButton(
        onPressed: () => Navigator.pop(ctx, true),
        style: TextButton.styleFrom(
          backgroundColor: isDanger ? _D.accent.withOpacity(0.15) : null),
        child: Text(confirmLabel,
          style: TextStyle(color: isDanger ? _D.accent : _D.textPrimary, fontWeight: FontWeight.w600)),
      ),
    ],
  );
}
