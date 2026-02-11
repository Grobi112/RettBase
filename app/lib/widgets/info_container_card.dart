import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/information_model.dart';
import '../services/informationen_service.dart';

/// Container-Typen für das Informationssystem
abstract class InfoContainerType {
  static const informationen = 'informationen';
  static const verkehrslage = 'verkehrslage';
  static const labels = {informationen: 'Informationen', verkehrslage: 'Verkehrslage'};
}

String formatInfoDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

/// Karte für einen Informations- oder Verkehrslage-Container (wie auf dem Dashboard)
class InfoContainerCard extends StatelessWidget {
  final String type;
  final List<Information>? informationenItems;
  final String? companyId;
  final String? userRole;
  final VoidCallback? onInfoDeleted;

  const InfoContainerCard({
    super.key,
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
                      formatInfoDate(i.datum),
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
                                  '${formatInfoDate(info.datum)} · ${info.userDisplayName}',
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
