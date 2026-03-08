import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readVoiceFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  try {
    await file.delete();
  } catch (_) {}
  return bytes;
}
