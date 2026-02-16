import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import 'app_update_types.dart';

/// Android APK: Prüft auf Updates und fordert Nutzer zum Download auf.
/// Nutzt version.json vom Server (z.B. app.rettbase.de).
bool get canCheckAppUpdate => true;

Future<AppUpdateResult> checkForAppUpdate() async {
  if (!Platform.isAndroid) return AppUpdateResult.upToDate;
  if (kDebugMode) debugPrint('RettBase Update: Prüfe ${AppConfig.androidUpdateCheckUrl}');
  try {
    final info = await PackageInfo.fromPlatform();
    final current = _parseVersion(info.version, info.buildNumber);
    if (current == null) return AppUpdateResult.error;

    final url = AppConfig.androidUpdateCheckUrl;
    if (url == null || url.isEmpty) return AppUpdateResult.error;

    // Cache-Busting: gecachte version.json verhindern
    final uri = Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}');
    final res = await http.get(uri).timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception('Timeout'),
    );
    if (res.statusCode != 200) {
      if (kDebugMode) debugPrint('RettBase Update: HTTP ${res.statusCode}');
      return AppUpdateResult.error;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    if (data == null) {
      if (kDebugMode) debugPrint('RettBase Update: version.json leer oder ungültig');
      return AppUpdateResult.error;
    }

    final serverVersion = (data['version'] as String?)?.trim();
    final serverBuildRaw = data['buildNumber'];
    final serverBuild = serverBuildRaw != null
        ? (serverBuildRaw is int ? serverBuildRaw.toString() : (serverBuildRaw as String?)?.trim())
        : null;
    final downloadUrl = (data['downloadUrl'] as String?)?.trim();
    final releaseNotes = (data['releaseNotes'] as String?)?.trim();

    if (serverVersion == null || downloadUrl == null) {
      if (kDebugMode) debugPrint('RettBase Update: version oder downloadUrl fehlt');
      return AppUpdateResult.error;
    }

    final server = _parseVersion(serverVersion, serverBuild);
    if (server == null || !_isVersionNewer(server, current)) {
      if (kDebugMode) {
        debugPrint('RettBase Update: Kein Update nötig. '
            'Installiert: ${info.version}+${info.buildNumber} '
            'Server: $serverVersion+$serverBuild');
      }
      return AppUpdateResult.upToDate;
    }

    if (kDebugMode) {
      debugPrint('RettBase Update: Neuere Version $serverVersion+$serverBuild verfügbar → Dialog');
    }

    _showUpdateDialog(
      currentVersion: info.version,
      newVersion: serverVersion,
      downloadUrl: downloadUrl,
      releaseNotes: releaseNotes,
    );
    return AppUpdateResult.updateAvailable;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('RettBase Update: Fehler beim Abruf – $e');
      debugPrint('RettBase Update: Stack $st');
    }
    return AppUpdateResult.error;
  }
}

List<int>? _parseVersion(String version, String? buildNumber) {
  final parts = version.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  if (parts.isEmpty) return null;
  final build = int.tryParse(buildNumber ?? '0') ?? 0;
  return [...parts, build];
}

bool _isVersionNewer(List<int> server, List<int> current) {
  final maxLen = server.length > current.length ? server.length : current.length;
  for (var i = 0; i < maxLen; i++) {
    final s = i < server.length ? server[i] : 0;
    final c = i < current.length ? current[i] : 0;
    if (s > c) return true;
    if (s < c) return false;
  }
  return false;
}

BuildContext? _appUpdateNavigatorContext;
GlobalKey<NavigatorState>? _appUpdateNavigatorKey;

/// Muss einmal beim App-Start gesetzt werden.
void setAppUpdateNavigatorContext(BuildContext? context) {
  _appUpdateNavigatorContext = context;
}

void setAppUpdateNavigatorKey(GlobalKey<NavigatorState>? key) {
  _appUpdateNavigatorKey = key;
}

BuildContext? get _resolveContext =>
    _appUpdateNavigatorKey?.currentContext ?? _appUpdateNavigatorContext;

void _showUpdateDialog({
  required String currentVersion,
  required String newVersion,
  required String downloadUrl,
  String? releaseNotes,
}) {
  void tryShow(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BuildContext? ctx = _appUpdateNavigatorKey?.currentState?.overlay?.context;
      if (ctx == null || !ctx.mounted) {
        ctx = _resolveContext;
      }
      if (ctx == null || !ctx.mounted) {
        if (attempt < 8) {
          Future.delayed(Duration(milliseconds: 300 * (attempt + 1)), () => tryShow(attempt + 1));
        }
        return;
      }
      _showUpdateDialogImpl(
        context: ctx,
        currentVersion: currentVersion,
        newVersion: newVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
      );
    });
  }

  tryShow(0);
}

void _showUpdateDialogImpl({
  required BuildContext context,
  required String currentVersion,
  required String newVersion,
  required String downloadUrl,
  String? releaseNotes,
}) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Update verfügbar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version $newVersion ist verfügbar.\n'
              'Sie haben derzeit Version $currentVersion installiert.',
            ),
            if (releaseNotes != null && releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(releaseNotes!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            const Text(
              'Der Download startet im Browser. Öffnen Sie nach dem Download die Datei, um die App zu aktualisieren.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Später'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            final uri = Uri.parse(downloadUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('Jetzt aktualisieren'),
        ),
      ],
    ),
  );
}

/// Öffentlich: Manueller Update-Check aus Einstellungen. Muss mit [context] aufgerufen werden.
Future<AppUpdateResult> checkForAppUpdateWithContext(BuildContext context) async {
  if (!Platform.isAndroid) return AppUpdateResult.upToDate;
  _appUpdateNavigatorContext = context;
  return checkForAppUpdate();
}

/// Öffnet direkt die APK-Download-URL im Browser (ohne version.json).
Future<void> openApkDownloadUrl() async {
  if (!Platform.isAndroid) return;
  final url = AppConfig.androidApkDownloadUrl;
  if (url == null || url.isEmpty) return;
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
