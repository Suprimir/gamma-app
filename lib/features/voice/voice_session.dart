import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _voiceSessionKey = 'voice_session_id';

/// Devuelve el session_id de voz persistente de esta instalación,
/// creándolo (hex de 32 chars) si es la primera vez.
Future<String> getOrCreateVoiceSessionId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_voiceSessionKey);
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }
  final random = Random.secure();
  final id = List.generate(
    32,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  await prefs.setString(_voiceSessionKey, id);
  return id;
}
