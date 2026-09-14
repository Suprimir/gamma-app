// Conditional export: on web this resolves to a blob-URL HTMLAudioElement
// player; on IO platforms it resolves to the media_kit temp-file player.
// Both expose the same `playVoiceResponse(bytes, player)` signature, so a
// single import works everywhere.
export 'voice_response_player_io.dart'
    if (dart.library.js_interop) 'voice_response_player_web.dart';
