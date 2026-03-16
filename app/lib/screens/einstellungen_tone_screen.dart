import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/tone_settings_service.dart';
import 'package:just_audio/just_audio.dart';

/// Toneinstellungen – Ton für Chat (System) und Alarm (Dropdown).
class EinstellungenToneScreen extends StatefulWidget {
  final String? companyId;
  final VoidCallback? onBack;

  const EinstellungenToneScreen({
    super.key,
    this.companyId,
    this.onBack,
  });

  @override
  State<EinstellungenToneScreen> createState() => _EinstellungenToneScreenState();
}

class _EinstellungenToneScreenState extends State<EinstellungenToneScreen> {
  final _toneService = ToneSettingsService();
  String _selectedAlarmToneId = ToneSettingsService.kAlarmToneOptions.first.id;
  bool _loading = true;
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = await _toneService.getAlarmToneId();
    if (mounted) {
      setState(() {
        _selectedAlarmToneId = id;
        _loading = false;
      });
    }
  }

  Future<void> _saveAlarmTone(String id) async {
    await _toneService.setAlarmToneId(id);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final companyId = widget.companyId;
    if (uid != null && companyId != null && companyId.isNotEmpty) {
      await _toneService.syncAlarmToneToFirestore(companyId, uid);
    }
    if (mounted) {
      setState(() => _selectedAlarmToneId = id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm-Ton gespeichert.')),
      );
    }
  }

  Future<void> _playPreview(String assetPath) async {
    if (kIsWeb) return;
    try {
      await _player.stop();
      await _player.setAsset(assetPath);
      await _player.play();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack?.call();
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppTheme.buildModuleAppBar(
          title: 'Toneinstellungen',
          onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : ListView(
                padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                children: [
                  Text(
                    'Push-Benachrichtigungen',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.chat_bubble_outline, color: AppTheme.primary, size: 28),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ton für Chatbenachrichtigung',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Systemton verwenden',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.notifications_active, color: AppTheme.primary, size: 28),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ton für Alarmierungen',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedAlarmToneId,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: ToneSettingsService.kAlarmToneOptions
                                .map((o) => DropdownMenuItem(
                                      value: o.id,
                                      child: Text(o.label),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                _saveAlarmTone(v);
                                final opt = ToneSettingsService.kAlarmToneOptions
                                    .where((o) => o.id == v)
                                    .firstOrNull;
                                if (opt != null && opt.assetPath.isNotEmpty && !kIsWeb) {
                                  _playPreview(opt.assetPath);
                                }
                              }
                            },
                          ),
                            if (!kIsWeb) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () {
                                for (final o in ToneSettingsService.kAlarmToneOptions) {
                                  if (o.id == _selectedAlarmToneId) {
                                    if (o.assetPath.isNotEmpty) _playPreview(o.assetPath);
                                    return;
                                  }
                                }
                              },
                              icon: const Icon(Icons.play_circle_outline, size: 20),
                              label: const Text('Vorschau abspielen'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
