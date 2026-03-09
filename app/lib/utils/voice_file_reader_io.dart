import 'dart:io';
import 'dart:typed_data';

/// Liest eine Audiodatei vom Dateisystem und löscht sie danach.
/// FIX: try/finally stellt sicher, dass die Temp-Datei immer gelöscht wird,
/// auch wenn readAsBytes() einen Fehler wirft (verhindert Temp-File-Leaks).
Future<Uint8List?> readVoiceFileBytes(String path) async {
  final file = File(path);
  Uint8List? bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    // Lesen fehlgeschlagen – bytes bleibt null
  } finally {
    // Immer löschen, egal ob Lesen erfolgreich war oder nicht
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
  return bytes;
}
