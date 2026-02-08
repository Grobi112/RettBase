import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../services/informationen_service.dart';

/// Container-Typen für das Informationssystem auf der Hauptseite
abstract class InfoContainerType {
  static const informationen = 'informationen';
  static const verkehrslage = 'verkehrslage';
  static const labels = {informationen: 'Informationen', verkehrslage: 'Verkehrslage'};
}

String _formatInfoDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

final _emptyContainerSlotsNotifier = ValueNotifier<List<String?>>([null, null]);
final _emptyInfoItemsNotifier = ValueNotifier<List<Information>>([]);

class HomeScreen extends StatefulWidget {
  final String? displayName;
  final String? vorname;
  final List<AppModule?> shortcuts;
  final ValueListenable<int>? chatUnreadListenable;
  final void Function(int index)? onShortcutTap;
  /// Aktualisierbare Container-Reihenfolge: 'informationen', 'verkehrslage' oder null
  final ValueListenable<List<String?>>? containerSlotsListenable;
  /// Informationen für den "informationen"-Container (Betreff, Kategorie, Datum)
  final ValueListenable<List<Information>>? informationenItemsListenable;
  final String? companyId;
  final String? userRole;
  final VoidCallback? onInfoDeleted;

  const HomeScreen({
    super.key,
    this.displayName,
    this.vorname,
    this.shortcuts = const [],
    this.chatUnreadListenable,
    this.onShortcutTap,
    this.containerSlotsListenable,
    this.informationenItemsListenable,
    this.companyId,
    this.userRole,
    this.onInfoDeleted,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timeTimer;

  @override
  void initState() {
    super.initState();
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    super.dispose();
  }

  /// Liefert immer nur den Vornamen für die Begrüßung (für alle Firmen).
  String? _getGreetingName() {
    if (widget.vorname != null && widget.vorname!.trim().isNotEmpty) return widget.vorname!.trim();
    final dn = widget.displayName?.trim();
    if (dn == null || dn.isEmpty) return null;
    final commaIdx = dn.indexOf(', ');
    if (commaIdx >= 0) return dn.substring(commaIdx + 2).trim();
    return null;
  }

  String _getGreeting() {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    final total = h * 60 + m;
    if (total >= 11 * 60 + 30 && total < 14 * 60) return 'Mahlzeit';
    if (h >= 5 && h < 12) return 'Guten Morgen';
    if (h >= 12 && h < 18) return 'Guten Nachmittag';
    return 'Guten Abend';
  }

  String _formatTime() {
    final now = DateTime.now();
    final days = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
    final day = days[now.weekday % 7];
    final d = now.day.toString().padLeft(2, '0');
    final mon = (now.month).toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$day $d.$mon - $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 4)),
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Dashboard',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getGreetingName() != null
                          ? '${_getGreeting()} ${_getGreetingName()}'
                          : _getGreeting(),
                      style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                Text(
                  _formatTime(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: AppTheme.border),
        Expanded(
          child: Container(
            color: AppTheme.surfaceBg,
            padding: const EdgeInsets.all(20),
            child: ValueListenableBuilder<List<String?>>(
              valueListenable: widget.containerSlotsListenable ?? _emptyContainerSlotsNotifier,
              builder: (context, slots, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                const crossAxisCount = 3;
                const rowCount = 2;
                const spacing = 12.0;
                final availableWidth = constraints.maxWidth - (spacing * (crossAxisCount - 1));
                final buttonWidth = availableWidth / crossAxisCount;
                final buttonHeight = 35.0;

                final containerTypes = slots.whereType<String>().toList();
                final showContainers = containerTypes.isNotEmpty;
                final infoListenable = widget.informationenItemsListenable ?? _emptyInfoItemsNotifier;

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(rowCount, (row) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: row < rowCount - 1 ? spacing : spacing),
                          child: Row(
                            children: List.generate(crossAxisCount, (col) {
                              final index = row * crossAxisCount + col;
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: col < crossAxisCount - 1 ? spacing : 0),
                                  child: _ShortcutButton(
                                    index: index,
                                    width: buttonWidth,
                                    height: buttonHeight,
                                    module: index < widget.shortcuts.length ? widget.shortcuts[index] : null,
                                    chatUnreadListenable: widget.chatUnreadListenable,
                                    onTap: () => widget.onShortcutTap?.call(index),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                      if (showContainers) ...[
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, bc) {
                            final isNarrow = bc.maxWidth < 600;
                            if (isNarrow) {
                              return Column(
                                children: containerTypes.map((t) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ValueListenableBuilder<List<Information>>(
                                    valueListenable: infoListenable,
                                    builder: (_, items, __) => _InfoContainerCard(
                                      type: t,
                                      informationenItems: items,
                                      companyId: widget.companyId,
                                      userRole: widget.userRole,
                                      onInfoDeleted: widget.onInfoDeleted,
                                    ),
                                  ),
                                )).toList(),
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: containerTypes.asMap().entries.map((e) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: e.key < containerTypes.length - 1 ? 12 : 0),
                                    child: ValueListenableBuilder<List<Information>>(
                                      valueListenable: infoListenable,
                                      builder: (_, items, __) => _InfoContainerCard(
                                        type: e.value,
                                        informationenItems: items,
                                        companyId: widget.companyId,
                                        userRole: widget.userRole,
                                        onInfoDeleted: widget.onInfoDeleted,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoContainerCard extends StatelessWidget {
  final String type;
  final List<Information>? informationenItems;
  final String? companyId;
  final String? userRole;
  final VoidCallback? onInfoDeleted;

  const _InfoContainerCard({
    required this.type,
    this.informationenItems,
    this.companyId,
    this.userRole,
    this.onInfoDeleted,
  });

  static const _deleteAllowedRoles = {
    'superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'leiterssd', 'wachleitung',
  };

  bool get _canDelete => companyId != null &&
      userRole != null &&
      _deleteAllowedRoles.contains((userRole ?? '').toLowerCase().trim());

  Widget _buildContainerContent(BuildContext context, List<Information> items, String subtitle) {
    final isNarrow = MediaQuery.of(context).size.width < 400;
    final padding = isNarrow ? 12.0 : 16.0;
    final fontSize = isNarrow ? 12.0 : 14.0;
    final fontSizeSmall = isNarrow ? 11.0 : 12.0;

    if (items.isEmpty) {
      return Text(
        subtitle,
        style: TextStyle(fontSize: fontSizeSmall, color: AppTheme.textSecondary, height: 1.4),
      );
    }
    final list = items.take(10).toList();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: list.map((i) => Padding(
        padding: EdgeInsets.only(bottom: isNarrow ? 8 : 12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                GestureDetector(
                  onTap: () => _showInfoDetail(context, i),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      i.betreff,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                        decoration: TextDecoration.none,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 8),
                  child: Text(
                    i.kategorie,
                    style: TextStyle(fontSize: fontSizeSmall, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatInfoDate(i.datum),
                    style: TextStyle(fontSize: fontSizeSmall, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      )).toList(),
      ),
    );
  }

  void _showInfoDetail(BuildContext context, Information info) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.15),
          child: SafeArea(
            top: false,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width,
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              info.betreff,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_canDelete && companyId != null)
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                              tooltip: 'Information löschen',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: ctx,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Information löschen?'),
                                    content: const Text('Möchten Sie diese Information wirklich löschen?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Abbrechen')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.of(c).pop(true),
                                        child: const Text('Löschen'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true && ctx.mounted) {
                                  await InformationenService().deleteInformation(companyId!, info.id);
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    onInfoDeleted?.call();
                                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Information gelöscht')));
                                  }
                                }
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.grey.shade100,
                              ),
                            ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.grey.shade600),
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey.shade100,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (info.kategorie.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(info.kategorie, style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                                  ),
                                const SizedBox(width: 12),
                                Text(
                                  '${_formatInfoDate(info.datum)} · ${info.userDisplayName}',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              info.text,
                              style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      ),
    );
  }

  Widget _buildHeaderIcon() {
    const size = 22.0;
    const color = Colors.white;
    if (type == InfoContainerType.verkehrslage) {
      return Icon(Icons.traffic, size: size, color: color);
    }
    return SvgPicture.asset(
      'img/icon_informationssystem.svg',
      width: size,
      height: size,
      colorFilter: const ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = (InfoContainerType.labels[type] ?? type).toUpperCase();
    final subtitle = type == InfoContainerType.verkehrslage
        ? 'Aktuelle Verkehrslage und Staus'
        : 'Interne Informationen und Mitteilungen';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: AppTheme.primary,
            child: Row(
              children: [
                _buildHeaderIcon(),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: MediaQuery.of(context).size.width < 400 ? 130 : 150,
            padding: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 12 : 16),
            color: Colors.white,
            child: _buildContainerContent(
              context,
              informationenItems?.where((i) => i.typ == type).toList() ?? [],
              subtitle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatefulWidget {
  final int index;
  final double width;
  final double height;
  final AppModule? module;
  final ValueListenable<int>? chatUnreadListenable;
  final VoidCallback? onTap;

  const _ShortcutButton({
    required this.index,
    required this.width,
    required this.height,
    this.module,
    this.chatUnreadListenable,
    this.onTap,
  });

  @override
  State<_ShortcutButton> createState() => _ShortcutButtonState();
}

class _ShortcutButtonState extends State<_ShortcutButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    widget.chatUnreadListenable?.addListener(_onChatUnreadChanged);
  }

  @override
  void didUpdateWidget(covariant _ShortcutButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.chatUnreadListenable?.removeListener(_onChatUnreadChanged);
    widget.chatUnreadListenable?.addListener(_onChatUnreadChanged);
  }

  @override
  void dispose() {
    widget.chatUnreadListenable?.removeListener(_onChatUnreadChanged);
    super.dispose();
  }

  void _onChatUnreadChanged() => setState(() {});

  IconData? _getIconDataForModule(String? id) {
    switch (id) {
      case 'chat': return Icons.chat_bubble_outline;
      case 'office': return Icons.mail_outline;
      case 'neuermangel': return Icons.build;
      case 'fahrzeugmanagement': return Icons.directions_car;
      case 'schichtanmeldung':
      case 'schichtuebersicht': return Icons.calendar_today;
      default: return null;
    }
  }

  Widget? _buildIconForModule(String? id, Color color) {
    const size = 18.0;
    final iconData = _getIconDataForModule(id);
    if (iconData != null) {
      return Icon(iconData, size: size, color: color);
    }
    if (id == 'fahrtenbuch' || id == 'fahrtenbuchuebersicht') {
      return SvgPicture.asset(
        'img/icon_fahrtenbuch.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    if (id == 'checklisten') {
      return SvgPicture.asset(
        'img/icon_checklisten.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    if (id == 'informationssystem' || id == 'informationen') {
      return SvgPicture.asset(
        'img/icon_informationssystem.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _hover || _pressed;
    final bgColor = widget.module != null
        ? (isHighlighted ? AppTheme.primaryHover : AppTheme.primary)
        : (isHighlighted ? const Color(0xFFE8F5FE) : Colors.grey[200]);
    final textColor = widget.module != null ? Colors.white : AppTheme.textMuted;
    final iconWidget = _buildIconForModule(widget.module?.id, textColor);
    final chatUnread = widget.chatUnreadListenable?.value ?? 0;
    final showBadge = widget.module?.id == 'chat' && chatUnread > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
            height: widget.height,
            child: Center(
              child: iconWidget != null && widget.module != null
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconWidget,
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.module!.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (showBadge)
                          Positioned(
                            top: -6,
                            right: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                              ),
                              child: Text(
                                chatUnread > 99 ? '99+' : '$chatUnread',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Text(
                      widget.module?.label ?? '+',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
