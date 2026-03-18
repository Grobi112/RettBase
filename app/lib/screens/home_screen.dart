import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/alarm_quittierung_service.dart';
import '../services/push_notification_service.dart';

import '../theme/app_theme.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../widgets/info_container_card.dart';

final _emptyContainerSlotsNotifier = ValueNotifier<List<String?>>(List.filled(6, null));
final _emptyInfoItemsNotifier = ValueNotifier<List<Information>>([]);

class HomeScreen extends StatefulWidget {
  final String? displayName;
  final String? vorname;
  final List<AppModule?> shortcuts;
  final ValueListenable<int>? chatUnreadListenable;
  /// Ungelesene E-Mails im Posteingang (Badge für E-Mail-Modul)
  final ValueListenable<int>? emailUnreadListenable;
  /// Anzahl pending Meldungen im Schichtplan NFS (Badge für Admin/Koordinator)
  final ValueListenable<int>? schichtplanNfsMeldungenListenable;
  final void Function(int index)? onShortcutTap;
  /// Aktualisierbare Container-Reihenfolge: 'informationen', 'verkehrslage' oder null
  final ValueListenable<List<String?>>? containerSlotsListenable;
  /// Informationen für den "informationen"-Container (Betreff, Kategorie, Datum)
  final ValueListenable<List<Information>>? informationenItemsListenable;
  final String? companyId;
  final String? userRole;
  final VoidCallback? onInfoDeleted;
  final ValueListenable<Map<String, dynamic>?>? activeEinsatzListenable;
  final String? mitarbeiterId;
  final VoidCallback? onEinsatzDetailsTap;
  final VoidCallback? onProtokollErstellenTap;
  /// true = es gibt abgeschlossene Einsätze, in denen der Nutzer alarmiert war (Button nur dann anzeigen)
  final ValueListenable<bool>? hatAbgeschlosseneEinsaetzeListenable;

  const HomeScreen({
    super.key,
    this.displayName,
    this.vorname,
    this.shortcuts = const [],
    this.chatUnreadListenable,
    this.emailUnreadListenable,
    this.schichtplanNfsMeldungenListenable,
    this.onShortcutTap,
    this.containerSlotsListenable,
    this.informationenItemsListenable,
    this.companyId,
    this.userRole,
    this.onInfoDeleted,
    this.activeEinsatzListenable,
    this.mitarbeiterId,
    this.onEinsatzDetailsTap,
    this.onProtokollErstellenTap,
    this.hatAbgeschlosseneEinsaetzeListenable,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timeTimer;
  bool _einsatzPopupShown = false;
  String? _lastEinsatzPopupId;

  @override
  void initState() {
    super.initState();
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    widget.activeEinsatzListenable?.addListener(_onActiveEinsatzChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onActiveEinsatzChanged());
  }

  @override
  void dispose() {
    widget.activeEinsatzListenable?.removeListener(_onActiveEinsatzChanged);
    _timeTimer?.cancel();
    super.dispose();
  }

  void _onActiveEinsatzChanged() {
    if (!mounted) return;
    final e = widget.activeEinsatzListenable?.value;
    if (e == null) {
      _lastEinsatzPopupId = null;
      setState(() {});
      return;
    }
    final eid = e['id'] as String?;
    if (eid == null) return;
    if (eid != _lastEinsatzPopupId) {
      _lastEinsatzPopupId = eid;
      _einsatzPopupShown = false;
    }
    if (!_einsatzPopupShown) {
      _einsatzPopupShown = true;
      unawaited(_checkAndShowEinsatzPopup(e, widget.companyId ?? '', eid));
    }
    setState(() {});
  }

  Future<void> _checkAndShowEinsatzPopup(Map<String, dynamic> e, String companyId, String eid) async {
    final quittiert = await AlarmQuittierungService().isQuittiert(companyId, eid);
    if (!mounted) return;
    if (quittiert) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lastEinsatzPopupId != eid) return;
      _showEinsatzPopup(e);
    });
  }

  void _showEinsatzPopup(Map<String, dynamic> einsatz) {
    if (!mounted) return;
    final companyId = widget.companyId ?? '';
    final eid = einsatz['id'] as String? ?? '';
    // Einwählen = Quittierung: Wenn User App geöffnet hat (kein Ton läuft), sofort quittieren. Kein Alarmton beim Popup.
    if (companyId.isNotEmpty && eid.isNotEmpty && !PushNotificationService.isAlarmTonePlaying) {
      unawaited(AlarmQuittierungService().markQuittiert(companyId, eid));
    }
    final nr = einsatz['einsatzNr'] as String? ?? '-';
    final datum = einsatz['einsatzDatum'] as String? ?? '';
    final name = einsatz['nameBetroffener'] as String? ?? '';
    final indikation = (einsatz['einsatzindikation'] as String?) ?? '';
    final indikationLabel = _einsatzindikationLabel(indikation);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text('Aktiver Einsatz $nr'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (datum.isNotEmpty) Text('Datum: $datum'),
              if (name.isNotEmpty) Text('Betroffener: $name'),
              if (indikationLabel.isNotEmpty) Text('Indikation: $indikationLabel'),
              const SizedBox(height: 16),
              Text(
                'Sie wurden zu diesem Einsatz alarmiert.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Schließen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onEinsatzDetailsTap?.call();
            },
            child: const Text('Einsatzdetails'),
          ),
        ],
      ),
    ).then((_) {
      final wasTonePlaying = PushNotificationService.isAlarmTonePlaying;
      PushNotificationService.stopAlarmTone();
      if (companyId.isNotEmpty && eid.isNotEmpty && wasTonePlaying) {
        unawaited(AlarmQuittierungService().markQuittiert(companyId, eid));
      }
    });
  }

  static String _einsatzindikationLabel(String key) {
    const opts = [
      ('utn', 'ÜTN - Überbringen Todesnachricht'),
      ('haeuslicher_todesfall', 'häuslicher Todesfall / akute Erkrankung'),
      ('frustrane_reanimation', 'frustrane Reanimation'),
      ('suizid', 'Suizid'),
      ('verkehrsunfall', 'Verkehrsunfall'),
      ('arbeitsunfall', 'Arbeitsunfall'),
      ('schuleinsatz', 'Schuleinsatz'),
      ('brand_explosion_unwetter', 'Brand / Explosion / Unwetter'),
      ('gewalt_verbrechen', 'Gewalttat / Verbrechen'),
      ('grosse_einsatzlage', 'Große Einsatzlage'),
      ('ploetzlicher_kindstod', 'plötzlicher Kindstod'),
      ('sonstiges', 'sonstiges'),
    ];
    if (key.isEmpty) return '';
    final found = opts.where((e) => e.$1 == key).firstOrNull;
    return found?.$2 ?? key;
  }

  /// Liefert immer nur den Vornamen für die Begrüßung (für alle Firmen).
  String? _getGreetingName() {
    if (widget.vorname != null && widget.vorname!.trim().isNotEmpty) return widget.vorname!.trim();
    final dn = widget.displayName?.trim();
    if (dn == null || dn.isEmpty) return null;
    final commaIdx = dn.indexOf(', ');
    if (commaIdx >= 0) return dn.substring(commaIdx + 2).trim();
    return dn.isNotEmpty ? dn : null;
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
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 25,
            vertical: MediaQuery.sizeOf(context).width < 600 ? 12 : 15,
          ),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Dashboard',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                              fontSize: MediaQuery.sizeOf(context).width < 400 ? 18 : null,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getGreetingName() != null
                            ? '${_getGreeting()} ${_getGreetingName()}'
                            : _getGreeting(),
                        style: TextStyle(
                          fontSize: MediaQuery.sizeOf(context).width < 400 ? 13 : 15,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (MediaQuery.sizeOf(context).width < 500) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 500)
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
            padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 500 ? 12 : 20),
            child: ValueListenableBuilder<List<String?>>(
              valueListenable: widget.containerSlotsListenable ?? _emptyContainerSlotsNotifier,
              builder: (context, slots, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                final isNarrow = MediaQuery.sizeOf(context).width < 500;
                final crossAxisCount = isNarrow ? 2 : 3;
                final spacing = MediaQuery.sizeOf(context).width < 500 ? 10.0 : 12.0;
                final buttonHeight = MediaQuery.sizeOf(context).width < 500 ? 44.0 : 35.0;

                // Nur belegte Schnellstart-Felder anzeigen; leere ausblenden
                final filledShortcuts = <(int, AppModule)>[];
                for (var i = 0; i < widget.shortcuts.length; i++) {
                  final m = widget.shortcuts[i];
                  if (m != null) filledShortcuts.add((i, m));
                }
                final buttonWidth = filledShortcuts.isNotEmpty
                    ? (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount
                    : 0.0;

                // Nur Slots mit ausgewähltem Container anzeigen; null (= "— Kein Container —") ausblenden
                final containerTypes = slots
                    .whereType<String>()
                    .where((s) => s.trim().isNotEmpty)
                    .toList();
                final showContainers = containerTypes.isNotEmpty;
                final infoListenable = widget.informationenItemsListenable ?? _emptyInfoItemsNotifier;

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (filledShortcuts.isNotEmpty)
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: filledShortcuts.map((e) {
                            final origIndex = e.$1;
                            final mod = e.$2;
                            return SizedBox(
                              width: buttonWidth,
                              height: buttonHeight,
                              child: _ShortcutButton(
                                index: origIndex,
                                width: buttonWidth,
                                height: buttonHeight,
                                module: mod,
                                chatUnreadListenable: widget.chatUnreadListenable,
                                emailUnreadListenable: widget.emailUnreadListenable,
                                schichtplanNfsMeldungenListenable: widget.schichtplanNfsMeldungenListenable,
                                onTap: () => widget.onShortcutTap?.call(origIndex),
                              ),
                            );
                          }).toList(),
                        ),
                      if (widget.activeEinsatzListenable?.value != null) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: widget.onEinsatzDetailsTap,
                            icon: const Icon(Icons.emergency, size: 22),
                            label: const Text('Einsatzdetails'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ] else if (widget.onProtokollErstellenTap != null) ...[
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.hatAbgeschlosseneEinsaetzeListenable ?? ValueNotifier<bool>(false),
                          builder: (_, hatAbgeschlossene, __) {
                            if (!hatAbgeschlossene) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: widget.onProtokollErstellenTap,
                                    icon: const Icon(Icons.description, size: 22),
                                    label: const Text('Protokoll erstellen'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.amber.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      if (showContainers) ...[
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, bc) {
                            final isNarrow = bc.maxWidth < 600;
                            final spacing = 12.0;
                            // 1 Container = volle Breite; schmal = 1 Spalte; sonst max. 2 nebeneinander
                            final singleContainer = containerTypes.length == 1;
                            final crossAxisCount = (singleContainer || isNarrow) ? 1 : 2;
                            final childWidth = (singleContainer || isNarrow)
                                ? bc.maxWidth
                                : (bc.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                            if (isNarrow) {
                              return Column(
                                children: containerTypes.map((t) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ValueListenableBuilder<List<Information>>(
                                    valueListenable: infoListenable,
                                    builder: (_, items, __) => InfoContainerCard(
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
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: containerTypes.map((t) => SizedBox(
                                width: childWidth,
                                child: ValueListenableBuilder<List<Information>>(
                                  valueListenable: infoListenable,
                                  builder: (_, items, __) => InfoContainerCard(
                                    type: t,
                                    informationenItems: items,
                                    companyId: widget.companyId,
                                    userRole: widget.userRole,
                                    onInfoDeleted: widget.onInfoDeleted,
                                  ),
                                ),
                              )).toList(),
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

class _ShortcutButton extends StatefulWidget {
  final int index;
  final double width;
  final double height;
  final AppModule? module;
  final ValueListenable<int>? chatUnreadListenable;
  final ValueListenable<int>? emailUnreadListenable;
  final ValueListenable<int>? schichtplanNfsMeldungenListenable;
  final VoidCallback? onTap;

  const _ShortcutButton({
    required this.index,
    required this.width,
    required this.height,
    this.module,
    this.chatUnreadListenable,
    this.emailUnreadListenable,
    this.schichtplanNfsMeldungenListenable,
    this.onTap,
  });

  @override
  State<_ShortcutButton> createState() => _ShortcutButtonState();
}

class _ShortcutButtonState extends State<_ShortcutButton> {
  bool _hover = false;
  bool _pressed = false;

  void _onBadgeChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.chatUnreadListenable?.addListener(_onBadgeChanged);
    widget.emailUnreadListenable?.addListener(_onBadgeChanged);
    widget.schichtplanNfsMeldungenListenable?.addListener(_onBadgeChanged);
  }

  @override
  void didUpdateWidget(covariant _ShortcutButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.chatUnreadListenable?.removeListener(_onBadgeChanged);
    oldWidget.emailUnreadListenable?.removeListener(_onBadgeChanged);
    oldWidget.schichtplanNfsMeldungenListenable?.removeListener(_onBadgeChanged);
    widget.chatUnreadListenable?.addListener(_onBadgeChanged);
    widget.emailUnreadListenable?.addListener(_onBadgeChanged);
    widget.schichtplanNfsMeldungenListenable?.addListener(_onBadgeChanged);
  }

  @override
  void dispose() {
    widget.chatUnreadListenable?.removeListener(_onBadgeChanged);
    widget.emailUnreadListenable?.removeListener(_onBadgeChanged);
    widget.schichtplanNfsMeldungenListenable?.removeListener(_onBadgeChanged);
    super.dispose();
  }

  IconData? _getIconDataForModule(String? id) {
    switch (id) {
      case 'chat': return Icons.chat_bubble_outline;
      case 'office':
      case 'email': return Icons.mail_outline;
      case 'neuermangel': return Icons.build;
      case 'fahrzeugmanagement': return Icons.directions_car;
      case 'schichtanmeldung':
      case 'schichtuebersicht':
      case 'schichtplannfs': return Icons.calendar_today;
      case 'fahrtenbuch':
      case 'fahrtenbuchuebersicht': return Icons.receipt_long_outlined;
      case 'checklisten': return Icons.checklist_rounded;
      case 'informationssystem':
      case 'informationen': return Icons.info_outline_rounded;
      case 'ssd':
      case 'einsatzprotokollnfs':
      case 'alarmierungnfs': return Icons.description_outlined;
      default: return null;
    }
  }

  Widget? _buildIconForModule(String? id, Color color) {
    const size = 18.0;
    final iconData = _getIconDataForModule(id);
    if (iconData != null) {
      return Icon(iconData, size: size, color: color);
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
    final emailUnread = widget.emailUnreadListenable?.value ?? 0;
    final nfsMeldungen = widget.schichtplanNfsMeldungenListenable?.value ?? 0;
    final badgeCount = widget.module?.id == 'chat'
        ? chatUnread
        : (widget.module?.id == 'email' || widget.module?.id == 'office')
            ? emailUnread
            : (widget.module?.id == 'schichtplannfs' ? nfsMeldungen : 0);
    final showBadge = badgeCount > 0;

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
                  ? Row(
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
                        if (showBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.all(Radius.circular(10)),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
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
