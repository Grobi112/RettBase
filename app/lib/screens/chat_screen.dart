import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';

/// Natives Chat-Modul – ohne WebView.
class ChatScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const ChatScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final _messageController = TextEditingController();
  String? _selectedChatId;
  Future<List<ChatMessage>>? _messagesFuture;
  List<MitarbeiterForChat> _mitarbeiter = [];
  List<Uint8List> _pendingImages = [];
  bool _loadingMitarbeiter = false;
  bool _showNewChatModal = false;
  bool _showNewGroupModal = false;
  final _groupNameController = TextEditingController();
  final List<MitarbeiterForChat> _selectedGroupMembers = [];

  @override
  void dispose() {
    _messageController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  String _chatDisplayName(ChatModel chat) {
    if (chat.name != null && chat.name!.isNotEmpty) return chat.name!;
    final uid = _chatService.userId ?? '';
    final others = chat.participantNames.where((p) => p.uid != uid).toList();
    return others.map((p) => p.name).where((n) => n.isNotEmpty).join(', ') ?? 'Chat';
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
    if (mounted) {
      final chatId = ChatService.getDirectChatId(_chatService.userId!, m.uid);
      setState(() {
        _showNewChatModal = false;
        _selectedChatId = chatId;
        _messagesFuture = _chatService.loadMessages(widget.companyId, chatId);
      });
    }
  }

  void _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Gruppenname eingeben.')));
      return;
    }
    if (_selectedGroupMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens einen Teilnehmer auswählen.')));
      return;
    }
    try {
      final chatId = await _chatService.createGroupChat(widget.companyId, name, _selectedGroupMembers);
      if (mounted) {
        setState(() {
          _showNewGroupModal = false;
          _selectedChatId = chatId;
          _messagesFuture = _chatService.loadMessages(widget.companyId, chatId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
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
    try {
      await _chatService.sendMessage(
        widget.companyId,
        _selectedChatId!,
        text,
        imageBytes: _pendingImages.isNotEmpty ? _pendingImages : null,
        imageNames: _pendingImages.asMap().entries.map((e) => 'image_${e.key}.jpg').toList(),
      );
      if (mounted) setState(() {
        _pendingImages = [];
        _messagesFuture = _chatService.loadMessages(widget.companyId, _selectedChatId!);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Senden fehlgeschlagen: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final onBack = widget.onBack ?? () => Navigator.of(context).pop();

    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Chat',
        onBack: onBack,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Neuer Chat',
            onPressed: _openNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Neue Gruppe',
            onPressed: _openNewGroup,
          ),
        ],
      ),
      body: Row(
        children: [
          // Chat-Liste
          AnimatedContainer(
            width: isNarrow ? (_selectedChatId != null ? 0 : double.infinity) : 320,
            duration: const Duration(milliseconds: 200),
            child: isNarrow && _selectedChatId != null
                ? const SizedBox.shrink()
                : _buildChatList(isNarrow),
          ),
          // Nachrichtenbereich
          Expanded(
            child: _selectedChatId == null
                ? _buildNoChatSelected(isNarrow)
                : _buildMessageView(isNarrow),
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
          if (!didPop) widget.onBack!();
        },
        child: content,
      );
    }
    return content;
  }

  Widget _buildChatList(bool isNarrow) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: StreamBuilder<List<ChatModel>>(
        stream: _chatService.streamChats(widget.companyId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final chats = snap.data!;
          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('Keine Chats', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Text(
                      'Neuer Chat oder Neue Gruppe',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final chat = chats[i];
              var unread = chat.unreadCount[_chatService.userId] ?? 0;
              if (unread == 0 &&
                  chat.lastMessageFrom != null &&
                  chat.lastMessageFrom != _chatService.userId &&
                  chat.lastMessageAt != null) {
                final lastRead = chat.lastReadAt[_chatService.userId];
                DateTime? lastReadAt;
                if (lastRead is Timestamp) lastReadAt = lastRead.toDate();
                if (lastRead is DateTime) lastReadAt = lastRead;
                if (lastReadAt == null || chat.lastMessageAt!.isAfter(lastReadAt)) unread = 1;
              }
              final hasUnread = unread > 0;
              return Dismissible(
                key: Key(chat.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (dir) async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Chat entfernen'),
                      content: const Text('Chat aus deiner Liste entfernen? (Für den anderen sichtbar, bis er ebenfalls löscht)'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _chatService.deleteChatForMe(widget.companyId, chat.id);
                    if (mounted && _selectedChatId == chat.id) setState(() => _selectedChatId = null);
                    return true;
                  }
                  return false;
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.2),
                    child: Text(
                      _getInitials(_chatDisplayName(chat)),
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _chatDisplayName(chat),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal),
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                          child: Text('${unread > 99 ? "99+" : unread}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    chat.lastMessageText ?? 'Keine Nachrichten',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  trailing: Text(_formatTime(chat.lastMessageAt), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  selected: _selectedChatId == chat.id,
                  selectedTileColor: AppTheme.primary.withOpacity(0.08),
                  onTap: () => setState(() {
                    _selectedChatId = chat.id;
                    _messagesFuture = _chatService.loadMessages(widget.companyId, chat.id);
                  }),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNoChatSelected(bool isNarrow) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Wähle einen Chat oder starte eine neue Unterhaltung.',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _openNewChat,
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                label: const Text('Neuer Chat'),
              ),
              OutlinedButton.icon(
                onPressed: _openNewGroup,
                icon: const Icon(Icons.group_add_outlined, size: 20),
                label: const Text('Neue Gruppe'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageView(bool isNarrow) {
    final chatId = _selectedChatId!;
    return StreamBuilder<List<ChatModel>>(
      stream: _chatService.streamChats(widget.companyId),
      builder: (context, chatSnap) {
        ChatModel? chat;
        for (final c in chatSnap.data ?? []) {
          if (c.id == chatId) { chat = c; break; }
        }
        final title = chat != null ? _chatDisplayName(chat) : 'Chat';

        return Column(
          children: [
            if (isNarrow)
              AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _selectedChatId = null),
                ),
                title: Text(title),
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
              ),
            Expanded(
              child: FutureBuilder<List<ChatMessage>>(
                future: _messagesFuture ??= _chatService.loadMessages(widget.companyId, chatId),
                builder: (context, snap) {
                  if (snap.hasError) {
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
                            const SizedBox(height: 8),
                            Text('${snap.error}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  final messages = snap.data!;
                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Noch keine Nachrichten',
                            style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Starte die Unterhaltung mit einer Nachricht.',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[messages.length - 1 - i];
                      final isSent = m.from == _chatService.userId;
                      return Align(
                        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                          decoration: BoxDecoration(
                            color: isSent ? AppTheme.primary : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (m.text != null && m.text!.isNotEmpty)
                                Text(
                                  m.text!,
                                  style: TextStyle(color: isSent ? Colors.white : Colors.black87, fontSize: 15),
                                ),
                              if (m.attachments != null)
                                for (final a in m.attachments!)
                                  if ((a.type).startsWith('image/'))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: GestureDetector(
                                        onTap: () {},
                                        child: Image.network(a.url, fit: BoxFit.contain, height: 150),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text('📎 ${a.name}', style: TextStyle(fontSize: 13, color: isSent ? Colors.white70 : Colors.grey[700])),
                                    ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(m.createdAt),
                                style: TextStyle(fontSize: 11, color: isSent ? Colors.white70 : Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pendingImages.isNotEmpty)
                      SizedBox(
                        height: 70,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _pendingImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(_pendingImages[i], width: 60, height: 60, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () => setState(() => _pendingImages.removeAt(i)),
                                  child: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file),
                          onPressed: _pickImages,
                          tooltip: 'Bild anhängen',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Nachricht eingeben...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            maxLines: 4,
                            minLines: 1,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _sendMessage,
                          color: AppTheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNewChatModal() {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Chat mit Mitarbeiter starten', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showNewChatModal = false)),
                  ],
                ),
              ),
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _mitarbeiter.length,
                        itemBuilder: (_, i) {
                          final m = _mitarbeiter[i];
                          return ListTile(
                            leading: CircleAvatar(child: Text(_getInitials(m.name))),
                            title: Text(m.name),
                            subtitle: m.email.isNotEmpty ? Text(m.email, style: const TextStyle(fontSize: 12)) : null,
                            onTap: () => _startDirectChat(m),
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

  Widget _buildNewGroupModal() {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Neue Gruppe erstellen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showNewGroupModal = false)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _groupNameController,
                  decoration: const InputDecoration(
                    labelText: 'Gruppenname',
                    hintText: 'z.B. Rettungsteam A',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _mitarbeiter.length,
                        itemBuilder: (_, i) {
                          final m = _mitarbeiter[i];
                          final selected = _selectedGroupMembers.any((s) => s.uid == m.uid);
                          return ListTile(
                            leading: CircleAvatar(child: Text(_getInitials(m.name))),
                            title: Text(m.name),
                            trailing: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? AppTheme.primary : null),
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  _selectedGroupMembers.removeWhere((s) => s.uid == m.uid);
                                } else {
                                  _selectedGroupMembers.add(m);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _createGroup,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                    child: const Text('Gruppe erstellen'),
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
