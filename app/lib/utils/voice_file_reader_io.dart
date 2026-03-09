import 'dart:io';
import 'dart:typed_data';

/// FIX Bug 4: Race-Condition beim Löschen der Temp-Audiodatei.
/// Datei wird jetzt in einem try/finally-Block gelöscht, sodass sie
/// auch bei einem Fehler beim Lesen sicher entfernt wird.
Future<Uint8List?> readVoiceFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    final bytes = await file.readAsBytes();
    return bytes;
  } catch (_) {
    return null;
  } finally {
    // Immer löschen – egal ob readAsBytes() erfolgreich war oder nicht.
    try {
      await file.delete();
    } catch (_) {}
  }
}
