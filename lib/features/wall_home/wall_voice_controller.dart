import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:record/record.dart';

import '../../data/api_client.dart';
import '../../ui/assistant_orb.dart';
import '../voice/mic_source.dart';
import '../voice/vad_model.dart';
import '../voice/voice_session.dart';

/// Voice loop for the wall panel surface.
///
/// Same contract as the mobile/desktop loop (VAD-gated mic capture, WAV
/// upload via `POST /api/v1/voice/audio-turn`, spoken WAV reply through
/// media_kit), owned by the wall home page so the assistant card talks
/// inline instead of navigating to another screen.
/// A [ChangeNotifier] so the card rebuilds on state changes.
class WallVoiceController extends ChangeNotifier {
  WallVoiceController(this._api);

  final ApiClient _api;
  final _recorder = AudioRecorder();

  /// Created lazily on the first spoken reply: instantiating a media_kit
  /// player requires native libraries that don't exist in widget tests,
  /// and the home page now owns this controller from initState.
  Player? _player;

  LoopState _state = LoopState.idle;
  String _thought = '';
  String? _error;
  bool _listening = false;
  bool _busy = false;
  int _completedTurns = 0;
  MicStream? _mic;
  Future<void>? _vadStopInFlight;
  Future<String>? _sessionId;
  Future<void>? _vadReady;

  LoopState get state => _state;
  String get thought => _thought;
  String? get error => _error;
  bool get listening => _listening;
  bool get busy => _busy;

  /// Monotonic count of turns the assistant fully answered (speech parsed,
  /// no transport failure). Surfaces watch it to refresh canonical state
  /// after a spoken action without polling.
  int get completedTurns => _completedTurns;

  /// Pre-warms the VAD model and session id without starting capture.
  void warmUp() {
    _vadReady ??= _ignoreFailure(VadModel.ensureReady());
    _sessionId ??= getOrCreateVoiceSessionId();
  }

  static Future<void> _ignoreFailure(Future<void> future) async {
    try {
      await future;
    } catch (_) {}
  }

  Future<void> toggle() async {
    if (_listening) {
      await _stopAndIdle();
      return;
    }
    if (_busy) return;
    warmUp();
    if (await _recorder.hasPermission() != true) {
      _fail('Permiso de micrófono denegado.');
      return;
    }
    final pendingStop = _vadStopInFlight;
    _vadStopInFlight = null;
    if (pendingStop != null) await pendingStop;
    try {
      try {
        await _vadReady;
      } catch (_) {}
      final mic = await micPcm16Stream(_recorder);
      _mic = mic;
      _listening = true;
      _state = LoopState.listening;
      _error = null;
      _thought = '';
      notifyListeners();
      await VadModel.vad.startListening(
        audioStream: mic.pcm,
        model: 'v5',
        baseAssetPath: 'assets/',
        submitUserSpeechOnPause: true,
      );
    } catch (e) {
      _fail('Error al escuchar: $e');
    }
  }

  Future<void> _stopAndIdle() async {
    try {
      await VadModel.vad.stopListening();
    } catch (_) {}
    if (!hasListeners) return;
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        await mic.cancel();
      } catch (_) {}
    }
    _listening = false;
    _state = LoopState.idle;
    notifyListeners();
  }

  Future<void> onSpeechEnd(List<double> samples) async {
    if (samples.isEmpty) return;
    _vadStopInFlight = VadModel.vad.stopListening();
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        await mic.cancel();
      } catch (_) {}
    }
    _listening = false;
    _busy = true;
    _state = LoopState.processing;
    notifyListeners();
    if (!kIsWeb && !Platform.isAndroid) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    final wav = pcm16ToWav(floatsToPcm16(samples));
    await _upload(wav);
  }

  Future<void> _upload(Uint8List wavBytes) async {
    _busy = true;
    _state = LoopState.processing;
    notifyListeners();
    try {
      final sessionId = await (_sessionId ??= getOrCreateVoiceSessionId());
      final result = await _api.audioTurn(wavBytes, sessionId: sessionId);
      final transcript = result['transcript'] as String? ?? '';
      final speech = result['speech'] as String?;
      final audioB64 = result['audio'] as String?;
      _busy = false;
      _state = LoopState.idle;
      _thought = transcript.isNotEmpty ? '«$transcript»' : '';
      if (speech != null && speech.isNotEmpty) _thought = speech;
      _completedTurns++;
      notifyListeners();
      if (audioB64 != null && audioB64.isNotEmpty) {
        await _playResponse(audioB64);
      }
    } catch (e) {
      _fail('Error al enviar el audio: $e');
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _playResponse(String audioB64) async {
    if (kIsWeb) {
      _fail(
        'La reproducción de voz no está disponible en la versión web todavía.',
      );
      return;
    }
    try {
      final bytes = base64Decode(audioB64);
      final file = File(
        '${Directory.systemTemp.path}/gamma_wall_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(bytes);
      final player = _player ??= Player();
      await player.open(Media(file.path), play: true);
    } catch (e) {
      _fail('Error al reproducir la respuesta: $e');
    }
  }

  void _fail(String message) {
    _state = LoopState.error;
    _error = message;
    notifyListeners();
  }

  /// Detaches the VAD speech-end callback target. The wall home page
  /// subscribes with `VadModel.vad.onSpeechEnd.listen(controller.onSpeechEnd)`
  /// and cancels its own subscription; the controller only stops hardware here.
  @override
  void dispose() {
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        mic.cancel();
      } catch (_) {}
    }
    try {
      _player?.dispose();
    } catch (_) {}
    try {
      _recorder.dispose();
    } catch (_) {}
    super.dispose();
  }
}
