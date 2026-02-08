import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/email_model.dart';
import '../services/email_service.dart';

class EmailScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;

  const EmailScreen({super.key, required this.companyId, this.onBack});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> with SingleTickerProviderStateMixin {
  final _emailService = EmailService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _stripHtmlForPreview(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final sameDay = d.day == now.day && d.month == now.month && d.year == now.year;
    if (sameDay) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (d.year != now.year) {
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Interne E-Mails',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Posteingang'),
            Tab(text: 'Gesendet'),
            Tab(text: 'Entwürfe'),
            Tab(text: 'Papierkorb'),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, color: Colors.white, size: 24, weight: 700),
            ),
            tooltip: 'Neue Nachricht',
            onPressed: _openCompose,
          ),
        ],
      ),
      body: SizedBox.expand(
        child: TabBarView(
          controller: _tabController,
          children: [
          _buildEmailList('inbox'),
          _buildEmailList('sent'),
          _buildEmailList('drafts'),
          _buildEmailList('trash'),
        ],
        ),
      ),
    );
  }

  Stream<List<EmailItem>> _getStreamForTab(String tab) {
    switch (tab) {
      case 'inbox': return _emailService.streamInbox(widget.companyId);
      case 'sent': return _emailService.streamSent(widget.companyId);
      case 'drafts': return _emailService.streamDrafts(widget.companyId);
      case 'trash': return _emailService.streamTrash(widget.companyId);
      default: return Stream.value([]);
    }
  }

  Widget _buildEmailList(String tab) {
    return StreamBuilder<List<EmailItem>>(
      stream: _getStreamForTab(tab),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        final emails = snap.data!;
        if (emails.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Keine Nachrichten', style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: emails.length,
          itemBuilder: (_, i) {
            final e = emails[i];
            return _EmailListItem(
              email: e,
              tab: tab,
              formatDate: _formatDate,
              stripHtmlForPreview: _stripHtmlForPreview,
              onTap: () => _openEmail(e, tab),
            );
          },
        );
      },
    );
  }

  void _openEmail(EmailItem email, String tab) async {
    if (tab == 'inbox' && !email.read) {
      await _emailService.markAsRead(widget.companyId, email.id);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EmailViewScreen(
          email: email,
          tab: tab,
          companyId: widget.companyId,
          emailService: _emailService,
          onBack: () => Navigator.of(context).pop(),
          onReply: () {
            Navigator.of(context).pop();
            _openCompose(replyTo: email);
          },
        ),
      ),
    );
  }

  void _openCompose({EmailItem? replyTo}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EmailComposeScreen(
          companyId: widget.companyId,
          emailService: _emailService,
          replyTo: replyTo,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (result == true && mounted) setState(() {});
  }
}

class _EmailListItem extends StatefulWidget {
  final EmailItem email;
  final String tab;
  final String Function(DateTime?) formatDate;
  final String Function(String) stripHtmlForPreview;
  final VoidCallback onTap;

  const _EmailListItem({
    required this.email,
    required this.tab,
    required this.formatDate,
    required this.stripHtmlForPreview,
    required this.onTap,
  });

  @override
  State<_EmailListItem> createState() => _EmailListItemState();
}

class _EmailListItemState extends State<_EmailListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.email;
    final isInbox = widget.tab == 'inbox';
    final otherName = isInbox ? e.fromName : (e.toName ?? e.toEmail ?? '');
    final subject = e.subject.isEmpty ? '(Kein Betreff)' : e.subject;
    final bodyPreview = widget.stripHtmlForPreview(e.body);
    final subjectAndPreview = bodyPreview.isEmpty ? subject : '$subject - $bodyPreview';

    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              splashColor: const Color(0xFFE0E0E0),
              highlightColor: const Color(0xFFE8E8E8),
              child: SizedBox(
                width: screenWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        color: _isHovered ? const Color(0xFFE8E8E8) : Colors.transparent,
                      ),
                    ),
                    Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: FlexColumnWidth(1),
                        2: IntrinsicColumnWidth(),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 12),
                              child: Text(
                                otherName.isNotEmpty ? otherName : '(Unbekannt)',
                                style: TextStyle(
                                  fontWeight: (isInbox && !e.read) ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
                              child: Text(
                                subjectAndPreview,
                                style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  widget.formatDate(e.createdAt),
                                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _EmailViewScreen extends StatelessWidget {
  final EmailItem email;
  final String tab;
  final String companyId;
  final EmailService emailService;
  final VoidCallback onBack;
  final VoidCallback? onReply;

  const _EmailViewScreen({
    required this.email,
    required this.tab,
    required this.companyId,
    required this.emailService,
    required this.onBack,
    this.onReply,
  });

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isInbox = tab == 'inbox';
    final fromLabel = isInbox ? 'Von' : 'An';
    String fromValue;
    if (isInbox) {
      fromValue = email.fromName.isNotEmpty ? email.fromName : (email.fromEmail ?? '');
    } else {
      final toName = email.toName ?? '';
      final toEmail = email.toEmail ?? '';
      fromValue = toName.isNotEmpty ? toName : toEmail;
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: email.subject.isEmpty ? '(Kein Betreff)' : email.subject,
        onBack: onBack,
        actions: [
          if (tab != 'trash' && tab != 'drafts' && onReply != null)
            IconButton(
              icon: const Icon(Icons.reply),
              tooltip: 'Antworten',
              onPressed: onReply,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Löschen',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Löschen'),
                  content: Text(tab == 'drafts' ? 'Entwurf endgültig löschen?' : 'Nachricht in den Papierkorb verschieben?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
                  ],
                ),
              );
              if (confirm == true) {
                if (tab == 'drafts') {
                  await emailService.deleteDraft(companyId, email.id);
                } else {
                  await emailService.deleteEmail(companyId, email.id);
                }
                if (context.mounted) onBack();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$fromLabel: $fromValue', style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(_formatDate(email.createdAt), style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const Divider(height: 24),
            SelectableText(_stripHtml(email.body).isEmpty ? '(Keine Nachricht)' : _stripHtml(email.body)),
          ],
        ),
      ),
    );
  }
}

class _EmailComposeScreen extends StatefulWidget {
  final String companyId;
  final EmailService emailService;
  final EmailItem? replyTo;
  final VoidCallback onBack;

  const _EmailComposeScreen({
    required this.companyId,
    required this.emailService,
    this.replyTo,
    required this.onBack,
  });

  @override
  State<_EmailComposeScreen> createState() => _EmailComposeScreenState();
}

class _EmailComposeScreenState extends State<_EmailComposeScreen> {
  final _recipientController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  List<EmailUser> _users = [];
  List<GroupMember> _allContacts = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final users = await widget.emailService.loadEmailUsers(widget.companyId);
    final contacts = await widget.emailService.loadGroupMembers(widget.companyId);
    if (!mounted) return;
    setState(() {
      _users = users;
      _allContacts = contacts;
      _loading = false;
      if (widget.replyTo != null) {
        final r = widget.replyTo!;
        _subjectController.text = r.subject.startsWith('Re:') ? r.subject : 'Re: ${r.subject}';
        _bodyController.text = '\n\n---\n${r.fromName} schrieb:\n${_stripHtml(r.body)}';
        _recipientController.text = r.fromName;
      }
    });
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ');
  }

  void _addRecipients(List<GroupMember> selected) {
    final parts = selected.map((c) => c.name).toList();
    final toAdd = parts.join('; ');
    final cur = _recipientController.text.trim();
    _recipientController.text = cur.isEmpty ? toAdd : '$cur; $toAdd';
  }

  void _showRecipientPicker() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Mitarbeiter auswählen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          child: SizedBox(
            width: MediaQuery.of(ctx).size.width,
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: _RecipientPickerSheet(
              contacts: _allContacts,
              onConfirm: (selected) {
                Navigator.of(ctx).pop();
                _addRecipients(selected);
              },
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final recipientsStr = _recipientController.text.trim();
    if (recipientsStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens einen Empfänger angeben.')));
      return;
    }
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff eingeben.')));
      return;
    }
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Nachricht eingeben.')));
      return;
    }

    final parts = recipientsStr.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens einen Empfänger angeben.')));
      return;
    }

    setState(() => _sending = true);
    try {
      int internal = 0, external = 0;
      final bodyHtml = '<p>${body.replaceAll('\n', '<br>')}</p>';

      for (final part in parts) {
        if (EmailService.isValidEmail(part)) {
          await widget.emailService.sendExternalEmail(
            widget.companyId, part, part, subject, bodyHtml,
            replyTo: subject.toLowerCase().startsWith('re:') ? null : null,
          );
          external++;
          continue;
        }

        GroupMember? contact;
        for (final c in _allContacts) {
          if (c.uid != null && c.name.equalsIgnoreCase(part)) {
            contact = c;
            break;
          }
        }
        if (contact != null && contact.uid != null) {
          await widget.emailService.sendEmail(
            widget.companyId, contact.uid!, contact.name, contact.email, subject, bodyHtml,
          );
          internal++;
        } else {
          EmailUser? user;
          for (final u in _users) {
            if (u.name.equalsIgnoreCase(part)) {
              user = u;
              break;
            }
          }
          if (user != null) {
            await widget.emailService.sendEmail(
              widget.companyId, user.uid, user.name, user.email, subject, bodyHtml,
            );
            internal++;
          } else {
            throw Exception('Empfänger "$part" nicht gefunden. Nutzen Sie die Kontaktliste oder gültige E-Mail-Adresse.');
          }
        }
      }

      if (mounted) {
        String msg = 'Nachricht gesendet!';
        if (internal + external > 1) {
          final parts2 = <String>[];
          if (internal > 0) parts2.add('$internal intern');
          if (external > 0) parts2.add('$external extern');
          msg = 'Nachricht gesendet (${parts2.join(', ')})!';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        widget.onBack();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Neue Nachricht',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          if (_sending)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))))
          else
            IconButton(icon: const Icon(Icons.send), onPressed: _send),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _recipientController,
                  decoration: InputDecoration(
                    labelText: 'An',
                    hintText: 'Tippen, Empfänger auswählen oder E-Mail eingeben (mehrere mit ; trennen)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_drop_down),
                      tooltip: 'Empfänger auswählen',
                      onPressed: _showRecipientPicker,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(labelText: 'Betreff'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Nachricht',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 12,
                ),
              ],
            ),
    );
  }
}

class _RecipientPickerSheet extends StatefulWidget {
  final List<GroupMember> contacts;
  final void Function(List<GroupMember> selected) onConfirm;
  final VoidCallback? onClose;

  const _RecipientPickerSheet({
    required this.contacts,
    required this.onConfirm,
    this.onClose,
  });

  @override
  State<_RecipientPickerSheet> createState() => _RecipientPickerSheetState();
}

class _RecipientPickerSheetState extends State<_RecipientPickerSheet> {
  final _searchController = TextEditingController();
  String _search = '';
  final List<GroupMember> _selected = [];
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
  }

  List<GroupMember> get _filtered {
    if (_search.isEmpty) return widget.contacts;
    final q = _search.toLowerCase().trim();
    return widget.contacts.where((c) =>
      c.name.toLowerCase().contains(q) || (c.email.isNotEmpty && c.email.toLowerCase().contains(q))).toList();
  }

  void _toggle(GroupMember m) {
    setState(() {
      final idx = _selected.indexWhere((s) => s.uid == m.uid && s.name == m.name);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(m);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Mitarbeiter suchen',
                    hintText: 'Name eingeben...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _clearSearch,
                      tooltip: 'Suche leeren',
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _selected.isEmpty ? null : () => widget.onConfirm(List.from(_selected)),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: Text('Übernehmen (${_selected.length})'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final c = _filtered[i];
              final isSelected = _selected.any((s) => s.uid == c.uid && s.name == c.name);
              return CheckboxListTile(
                value: isSelected,
                onChanged: (_) => _toggle(c),
                title: Text(c.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

extension _StringExt on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}

