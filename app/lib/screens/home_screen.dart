import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../widgets/info_container_card.dart';

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
                final crossAxisCount = MediaQuery.sizeOf(context).width < 500 ? 2 : 3;
                const rowCount = 2;
                final spacing = MediaQuery.sizeOf(context).width < 500 ? 10.0 : 12.0;
                final availableWidth = constraints.maxWidth - (spacing * (crossAxisCount - 1));
                final buttonWidth = availableWidth / crossAxisCount;
                final buttonHeight = MediaQuery.sizeOf(context).width < 500 ? 44.0 : 35.0;

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
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: containerTypes.asMap().entries.map((e) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: e.key < containerTypes.length - 1 ? 12 : 0),
                                    child: ValueListenableBuilder<List<Information>>(
                                      valueListenable: infoListenable,
                                      builder: (_, items, __) => InfoContainerCard(
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
