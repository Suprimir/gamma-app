import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// Plays a WAV response on IO platforms: writes it to a temp file and opens
/// it with the caller-owned media_kit [player].
///
/// The caller owns the player lifecycle; this helper only feeds it audio.
Future<void> playVoiceResponse(Uint8List wavBytes, Object player) async {
  final file = File(
    '${Directory.systemTemp.path}/gamma_respuesta_${DateTime.now().millisecondsSinceEpoch}.wav',
  );
  await file.writeAsBytes(wavBytes);
  await (player as Player).open(Media(file.path), play: true);
}
