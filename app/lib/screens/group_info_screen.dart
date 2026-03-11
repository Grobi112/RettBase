import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/profile_service.dart';
import '../utils/chat_permissions.dart';
import 'group_description_screen.dart';

/// Gruppeinfo-Seite: Avatar, Name, Beschreibung, Benachrichtigungen, Mitglieder.
class GroupInfoScreen extends StatefulWidget {
  final String companyId;
  final ChatModel chat;
  final bool initialMuted;
  final String? userRole;
  final VoidCallback? onBack;

  const GroupInfoScreen({
    super.key,
    required this.companyId,
    required this.chat,
    required this.initialMuted,
    this.userRole,
    this.onBack,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _chatService = ChatService();
  final _profileService = ProfileService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Map<String, String?> _profileImageCache = {};

  late bool _muted;
  bool _saving = false;
  bool _descriptionExpanded = false;
  late ChatModel _chat;
  bool _showAddMembersModal = false;
  List<MitarbeiterForChat> _mitarbeiter = [];
  bool _loadingMitarbeiter = false;
  final List<MitarbeiterForChat> _selectedAddMembers = [];

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _muted = widget.initialMuted;
    _nameController.text = widget.chat.name ?? '';
    _descriptionController.text = widget.chat.groupDescription ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileImage(String uid) async {
    if (_profileImageCache.containsKey(uid)) return;
    _profileImageCache[uid] = null;
    try {
      final profile = await _profileService.loadProfile(widget.companyId, uid, '');
      if (profile != null && mounted) {
        final d = profile.data;
        final url = (d['fotoUrl'] ?? d['photoUrl'] ?? d['profilfoto'])?.toString().trim();
        setState(() => _profileImageCache[uid] = (url != null && url.isNotEmpty) ? url : null);
      }
    } catch (_) {}
  }

  String _getInitials(String name) {
    final s = name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').join('').toUpperCase();
    return s.length >= 2 ? s.substring(0, 2) : (s.isEmpty ? '?' : s);
  }

  Future<void> _pickAndUploadAvatar() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Aus Galerie'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Aus Datei'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    Uint8List? bytes;
    String? filename;
    if (choice == 'gallery') {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (x != null) {
        bytes = await x.readAsBytes();
        filename = x.name;
      }
    } else if (choice == 'file') {
      const ext = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'tif', 'heic', 'ico'];
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ext,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.single.size > 0) {
        final f = result.files.single;
        bytes = f.bytes;
        filename = f.name;
      }
    }
    if (bytes == null || bytes.isEmpty || filename == null || filename.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      await _chatService.uploadGroupAvatar(
        widget.companyId,
        widget.chat.id,
        bytes,
        filename,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppenavatar wurde aktualisiert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hochladen: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (name == widget.chat.name) return;
    setState(() => _saving = true);
    try {
      await _chatService.updateGroupName(widget.companyId, widget.chat.id, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppenname wurde aktualisiert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _openGroupDescription() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => GroupDescriptionScreen(
          companyId: widget.companyId,
          chat: widget.chat,
          initialDescription: _descriptionController.text.trim(),
        ),
      ),
    );
    if (result != null && mounted) {
      _descriptionController.text = result;
      setState(() {});
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) {
      _chatService.muteChat(widget.companyId, widget.chat.id);
    } else {
      _chatService.unmuteChat(widget.companyId, widget.chat.id);
    }
  }

  Future<void> _loadMitarbeiter() async {
    setState(() => _loadingMitarbeiter = true);
    try {
      final list = await _chatService.loadMitarbeiter(widget.companyId);
      if (mounted) {
        final memberUids = _chat.participantNames.map((p) => p.uid).toSet();
        setState(() {
          _mitarbeiter = list.where((m) => !memberUids.contains(m.uid)).toList();
          _loadingMitarbeiter = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMitarbeiter = false);
    }
  }

  void _openAddMembers() {
    _selectedAddMembers.clear();
    setState(() => _showAddMembersModal = true);
    _loadMitarbeiter();
  }

  Future<void> _confirmAddMembers() async {
    if (_selectedAddMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens einen Teilnehmer auswählen.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _chatService.addMembersToGroup(
        widget.companyId,
        widget.chat.id,
        _selectedAddMembers,
      );
      if (mounted) {
        setState(() {
          _showAddMembersModal = false;
          _saving = false;
          _chat = _chat.copyWith(
            participants: [..._chat.participants, ..._selectedAddMembers.map((m) => m.uid)],
            participantNames: [
              ..._chat.participantNames,
              ..._selectedAddMembers.map((m) => ParticipantName(uid: m.uid, name: m.name)),
            ],
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_selectedAddMembers.length} Mitglied(er) hinzugefügt.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Gruppe wirklich verlassen?',
          style: TextStyle(color: Color(0xFFE6EDF3)),
        ),
        content: const Text(
          'Du kannst den Chat weiterhin lesen, aber keine Nachrichten mehr senden.',
          style: TextStyle(color: Color(0xFF8B949E)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verlassen', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _chatService.leaveGroup(widget.companyId, widget.chat.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Du hast die Gruppe verlassen.')),
        );
        widget.onBack?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final avatarUrl = chat.groupImageUrl;
    final members = chat.participantNames
        .where((p) => !chat.leftBy.contains(p.uid))
        .toList()
      ..sort((a, b) => (a.name).toLowerCase().compareTo((b.name).toLowerCase()));

    for (final p in members) {
      if (p.uid.isNotEmpty) Future.microtask(() => _loadProfileImage(p.uid));
    }

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: const Color(0xFFE6EDF3),
        title: const Text('Gruppeninfo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.onBack?.call();
            Navigator.pop(context);
          },
        ),
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F81F7)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 1. Gruppenavatar (zentriert, änderbar)
                  GestureDetector(
                    onTap: _pickAndUploadAvatar,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: (avatarUrl == null || avatarUrl.isEmpty)
                            ? LinearGradient(
                                colors: [
                                  const Color(0xFF388BFD).withOpacity(0.8),
                                  const Color(0xFF2F81F7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? Image.network(
                              avatarUrl,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(
                                _getInitials(chat.name ?? ''),
                                style: const TextStyle(
                                  color: Color(0xFF161B22),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 32,
                                ),
                              ),
                            )
                          : Text(
                              _getInitials(chat.name ?? ''),
                              style: const TextStyle(
                                color: Color(0xFF161B22),
                                fontWeight: FontWeight.w700,
                                fontSize: 32,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tippen zum Ändern',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),

                  // 2. Gruppenname (änderbar nur mit Berechtigung)
                  TextField(
                    controller: _nameController,
                    readOnly: !ChatPermissions.canManageGroups(widget.userRole),
                    showCursor: ChatPermissions.canManageGroups(widget.userRole),
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF161B22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: ChatPermissions.canManageGroups(widget.userRole)
                        ? (_) => _saveName()
                        : null,
                  ),
                  const SizedBox(height: 4),
                  // 3. Gruppe - (Teilnehmerzahl) direkt unter Gruppenname
                  Text(
                    'Gruppe – ${members.length} ${members.length == 1 ? 'Mitglied' : 'Mitglieder'}',
                    style: const TextStyle(
                      color: Color(0xFF2F81F7),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!chat.leftBy.contains(_chatService.userId)) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: ChatPermissions.canManageGroups(widget.userRole)
                            ? _openAddMembers
                            : null,
                        child: Opacity(
                          opacity: ChatPermissions.canManageGroups(widget.userRole)
                              ? 1.0
                              : 0.45,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_add,
                                  size: 36,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Hinzufügen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // 4. Gruppenbeschreibung (3 Zeilen, Mehr Zeilen anzeigen, ">" → Bearbeitungsseite)
                  Text(
                    'Gruppenbeschreibung',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final desc = _descriptionController.text.trim();
                        final style = const TextStyle(color: Color(0xFFE6EDF3), fontSize: 15);
                        final painter = TextPainter(
                          text: TextSpan(
                            text: desc.isEmpty ? 'Keine Beschreibung' : desc,
                            style: style,
                          ),
                          maxLines: 3,
                          textDirection: TextDirection.ltr,
                        )..layout(maxWidth: constraints.maxWidth - 40);
                        final exceeds = painter.didExceedMaxLines;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    desc.isEmpty ? 'Keine Beschreibung' : desc,
                                    style: style,
                                    maxLines: _descriptionExpanded ? null : 3,
                                    overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
                                  ),
                                  if (exceeds && !_descriptionExpanded)
                                    GestureDetector(
                                      onTap: () => setState(() => _descriptionExpanded = true),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '... Mehr Zeilen anzeigen',
                                          style: TextStyle(
                                            color: Colors.blue[400],
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (exceeds && _descriptionExpanded)
                                    GestureDetector(
                                      onTap: () => setState(() => _descriptionExpanded = false),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Weniger anzeigen',
                                          style: TextStyle(
                                            color: Colors.blue[400],
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: ChatPermissions.canManageGroups(widget.userRole)
                                  ? _openGroupDescription
                                  : null,
                              behavior: HitTestBehavior.opaque,
                              child: Opacity(
                                opacity: ChatPermissions.canManageGroups(widget.userRole)
                                    ? 1.0
                                    : 0.45,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey[400],
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 5. Benachrichtigungen (Stumm oder nicht)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Benachrichtigungen',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Switch(
                        value: !_muted,
                        onChanged: (_) => _toggleMute(),
                        activeColor: const Color(0xFF2F81F7),
                      ),
                    ],
                  ),
                  Text(
                    _muted ? 'Stumm' : 'Nicht stumm',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),

                  // 6. Mitglieder A–Z
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Mitglieder (${members.length})',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...members.map((p) {
                    final photoUrl = p.uid.isNotEmpty ? _profileImageCache[p.uid] : null;
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: (photoUrl == null || photoUrl.isEmpty)
                              ? LinearGradient(
                                  colors: [
                                    const Color(0xFF388BFD).withOpacity(0.8),
                                    const Color(0xFF2F81F7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          shape: BoxShape.circle,
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: (photoUrl != null && photoUrl.isNotEmpty)
                            ? Image.network(photoUrl, width: 40, height: 40, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Text(
                                  _getInitials(p.name),
                                  style: const TextStyle(
                                    color: Color(0xFF161B22),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ))
                            : Text(
                                _getInitials(p.name),
                                style: const TextStyle(
                                  color: Color(0xFF161B22),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(
                          color: Color(0xFFE6EDF3),
                          fontSize: 15,
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),

                  // 7. Gruppe verlassen (nur wenn noch nicht verlassen)
                  if (!(chat.leftBy.contains(_chatService.userId)))
                    GestureDetector(
                      onTap: _confirmLeaveGroup,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Gruppe verlassen',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );

    final content = Stack(
      children: [
        scaffold,
        if (_showAddMembersModal) _buildAddMembersModal(),
      ],
    );
    return content;
  }

  Widget _buildAddMembersModal() {
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F81F7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_add, size: 18, color: Color(0xFF2F81F7)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Mitglieder hinzufügen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Color(0xFFE6EDF3),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF8B949E)),
                      onPressed: () => setState(() => _showAddMembersModal = false),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: const Color(0xFF30363D)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Teilnehmer auswählen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_selectedAddMembers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F81F7).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_selectedAddMembers.length} gewählt',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2F81F7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F81F7)))
                    : _mitarbeiter.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Keine weiteren Mitarbeiter verfügbar.',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: _mitarbeiter.length,
                            itemBuilder: (_, i) {
                              final m = _mitarbeiter[i];
                              if (m.uid.isNotEmpty) Future.microtask(() => _loadProfileImage(m.uid));
                              final photoUrl = m.uid.isNotEmpty ? _profileImageCache[m.uid] : null;
                              final selected = _selectedAddMembers.any((s) => s.uid == m.uid);
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    if (selected) {
                                      _selectedAddMembers.removeWhere((s) => s.uid == m.uid);
                                    } else {
                                      _selectedAddMembers.add(m);
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF2F81F7).withOpacity(0.06)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          gradient: (photoUrl == null || photoUrl.isEmpty)
                                              ? (selected
                                                  ? LinearGradient(
                                                      colors: [
                                                        const Color(0xFF388BFD).withOpacity(0.7),
                                                        const Color(0xFF2F81F7),
                                                      ],
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                    )
                                                  : null)
                                              : null,
                                          color: (photoUrl == null || photoUrl.isEmpty) && !selected
                                              ? const Color(0xFF2F81F7).withOpacity(0.15)
                                              : null,
                                          shape: BoxShape.circle,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        alignment: Alignment.center,
                                        child: (photoUrl != null && photoUrl.isNotEmpty)
                                            ? Image.network(photoUrl, width: 40, height: 40, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Text(
                                                  _getInitials(m.name),
                                                  style: TextStyle(
                                                    color: selected ? Colors.white : const Color(0xFF2F81F7),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ))
                                            : Text(
                                                _getInitials(m.name),
                                                style: TextStyle(
                                                  color: selected ? Colors.white : const Color(0xFF2F81F7),
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
                                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                            color: const Color(0xFFE6EDF3),
                                          ),
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        child: selected
                                            ? const Icon(Icons.check_circle, color: Color(0xFF2F81F7), size: 22, key: ValueKey('checked'))
                                            : Icon(Icons.circle_outlined, color: Colors.grey[300], size: 22, key: const ValueKey('unchecked')),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selectedAddMembers.isEmpty ? null : _confirmAddMembers,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F81F7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Hinzufügen'),
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
