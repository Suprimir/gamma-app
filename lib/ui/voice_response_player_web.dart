import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Plays a WAV response on web: the bytes become a blob URL played through a
/// throwaway [web.HTMLAudioElement]. The caller's media_kit player is ignored
/// on this platform (it cannot open temp files here); the returned future
/// completes when playback ends, or fails when the element errors/refuses to
/// start.
Future<void> playVoiceResponse(Uint8List wavBytes, Object player) async {
  final blob = web.Blob(
    [wavBytes.toJS].toJS,
    web.BlobPropertyBag(type: 'audio/wav'),
  );
  final url = web.URL.createObjectURL(blob);
  final audio = web.HTMLAudioElement()..src = url;
  final done = Completer<void>();
  audio.onended = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  audio.onerror = ((web.Event _) {
    if (!done.isCompleted) {
      done.completeError(StateError('No se pudo reproducir el audio.'));
    }
  }).toJS;
  try {
    await audio.play().toDart;
    await done.future;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
