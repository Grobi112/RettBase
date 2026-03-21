import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import 'app_update_types.dart';

bool get canCheckAppUpdate => true;

Future<AppUpdateResult> checkForAppUpdate() async => AppUpdateResult.upToDate;

void setAppUpdateNavigatorContext(BuildContext? context) {}

void setAppUpdateNavigatorKey(GlobalKey<NavigatorState>? key) {}

Future<AppUpdateResult> checkForAppUpdateWithContext(BuildContext context) async {
  await maybePromptAndroidApkUpdate(context);
  return AppUpdateResult.upToDate;
}

Future<void> openApkDownloadUrl() async {}

int? _parseVersionCode(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

/// Beim App-Start (Android): `version.json` laden, bei neuem [versionCode] Dialog → Download → Installation.
Future<void> maybePromptAndroidApkUpdate(BuildContext context) async {
  if (!Platform.isAndroid) return;
  final checkUrl = AppConfig.androidUpdateCheckUrl;
  if (checkUrl == null || checkUrl.isEmpty) return;

  // print erscheint in adb logcat zuverlässig (auch Release), z. B.:
  // adb logcat | grep RettBase.apkUpdate
  void trace(String msg) {
    final line = '[RettBase.apkUpdate] $msg';
    print(line);
    developer.log(msg, name: 'RettBase.apkUpdate');
  }

  try {
    // Kurz warten: Navigator/Overlay nach erstem Frame sind auf manchen Geräten sonst noch nicht bereit.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    // Cache-Buster (wie Web): Proxies/CDN liefern sonst ggf. altes version.json → fälschlich „kein Update“.
    final uri = Uri.parse(checkUrl);
    final bust = DateTime.now().millisecondsSinceEpoch.toString();
    final requestUri = uri.replace(
      queryParameters: {...uri.queryParameters, 't': bust},
    );
    trace('Check gestartet → $requestUri');
    final res = await http
        .get(
          requestUri,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      trace('version.json HTTP ${res.statusCode}');
      return;
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      trace('version.json ist kein JSON-Objekt');
      return;
    }
    final data = Map<String, dynamic>.from(decoded);
    final remoteCode = _parseVersionCode(data['versionCode'] ?? data['buildNumber']);
    if (remoteCode == null) {
      final raw = res.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final preview = raw.length > 220 ? '${raw.substring(0, 220)}…' : raw;
      trace('version.json ohne versionCode/buildNumber – Server liefert z. B. nur "version"? Antwort: $preview');
      return;
    }

    final info = await PackageInfo.fromPlatform();
    final localCode = int.tryParse(info.buildNumber) ?? 0;
    trace('Vergleich: remote versionCode=$remoteCode, lokal buildNumber=$localCode');
    if (remoteCode <= localCode) {
      trace('kein Update (Server nicht höher als installierte App)');
      return;
    }

    final apkFromJson = (data['apkUrl'] as String?)?.trim();
    final apkUrl = (apkFromJson != null && apkFromJson.isNotEmpty)
        ? apkFromJson
        : AppConfig.androidApkDownloadUrlDefault;
    if (apkUrl.isEmpty) {
      trace('apkUrl leer, Abbruch');
      return;
    }

    final versionLabel = data['version']?.toString() ?? '';
    final label = versionLabel.isNotEmpty ? versionLabel : remoteCode.toString();
    final notes = (data['releaseNotes'] as String?)?.trim() ?? '';

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Update verfügbar'),
        content: SizedBox(
          width: 400,
          height: 320,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Eine neue Version von RettBase ist verfügbar (Version $label, Build $remoteCode).',
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(notes),
                ],
                const SizedBox(height: 12),
                Text(
                  'Die App wird heruntergeladen. Anschließend öffnet sich die Android-Installation – bitte „Installieren“ bestätigen.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
              ],
            ),
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
              await _downloadAndInstallApk(context, apkUrl);
            },
            child: const Text('Herunterladen & installieren'),
          ),
        ],
      ),
    );
  } catch (e, st) {
    print('[RettBase.apkUpdate] FEHLER: $e');
    developer.log(
      'APK-Update-Check fehlgeschlagen',
      name: 'RettBase.apkUpdate',
      error: e,
      stackTrace: st,
    );
  }
}

Future<void> _downloadAndInstallApk(BuildContext context, String apkUrl) async {
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: SizedBox(
          width: 400,
          height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Update wird geladen …'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final response = await http
        .get(
          Uri.parse(apkUrl),
          headers: const {'Cache-Control': 'no-cache'},
        )
        .timeout(const Duration(minutes: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/rettbase_update.apk');
    await file.writeAsBytes(response.bodyBytes, flush: true);

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Installation konnte nicht gestartet werden: ${result.message}',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download fehlgeschlagen: $e')),
      );
    }
  }
}
