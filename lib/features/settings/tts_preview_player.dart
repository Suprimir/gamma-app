import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// Plays the short WAV returned by the TTS preview endpoint.
///
/// Abstracted so widget tests can exercise the fetch/synthesis flow without
/// depending on native media playback (media_kit needs native libraries that
/// do not exist in the test host).
abstract interface class TtsPreviewPlayer {
  Future<void> play(Uint8List wavBytes);

  void dispose();
}

/// media_kit implementation mirroring the wall voice loop: writes the WAV to
/// a temp file and plays it with a lazily-created [Player]. The player is
/// created on first playback so merely building the settings page never
/// requires native libraries.
class MediaKitTtsPreviewPlayer implements TtsPreviewPlayer {
  Player? _player;

  @override
  Future<void> play(Uint8List wavBytes) async {
    final file = File(
      '${Directory.systemTemp.path}/gamma_tts_preview_'
      '${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(wavBytes);
    final player = _player ??= Player();
    await player.open(Media(file.path), play: true);
  }

  @override
  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
