import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../../ui/voice_response_player.dart';

/// Plays the short WAV returned by the TTS preview endpoint.
///
/// Abstracted so widget tests can exercise the fetch/synthesis flow without
/// depending on native media playback (media_kit needs native libraries that
/// do not exist in the test host).
abstract interface class TtsPreviewPlayer {
  Future<void> play(Uint8List wavBytes);

  void dispose();
}

/// Platform-dispatched implementation mirroring the wall voice loop: on IO it
/// writes the WAV to a temp file and plays it with a lazily-created [Player];
/// on web the shared helper plays a blob URL. The player is created on first
/// playback so merely building the settings page never requires native
/// libraries.
class MediaKitTtsPreviewPlayer implements TtsPreviewPlayer {
  Player? _player;

  @override
  Future<void> play(Uint8List wavBytes) async {
    await playVoiceResponse(wavBytes, _player ??= Player());
  }

  @override
  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
