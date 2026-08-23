import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:record/record.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/assistant_orb.dart';
import '../voice/mic_source.dart';
import '../voice/vad_model.dart';
import '../voice/voice_session.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _recorder = AudioRecorder();
  final _player = Player();
  LoopState _state = LoopState.idle;
  String _thought = '';
  String? _error;
  bool _listening = false;
  bool _busy = false;
  MicStream? _mic;
  // Stop del VAD en vuelo: se lanza sin bloquear el envío en _onSpeechEnd y
  // se espera aquí antes de arrancar una nueva escucha.
  Future<void>? _vadStopInFlight;
  late Future<String> _sessionId;
  late final Future<void> _vadReady;

  @override
  void initState() {
    super.initState();
    _sessionId = getOrCreateVoiceSessionId();
    _vadReady = VadModel.ensureReady();
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _state = playing ? LoopState.speaking : LoopState.idle);
      }
    });
    VadModel.vad.onSpeechEnd.listen((samples) => _onSpeechEnd(samples));
    VadModel.vad.onVADMisfire.listen((_) {
      // Falso arranque (ruido que parecía voz): volver a escuchar.
      if (mounted && _listening) {
        setState(() => _state = LoopState.listening);
      }
    });
    VadModel.vad.onError.listen((message) {
      if (mounted && _listening) _fail('Error del VAD: $message');
    });
  }

  @override
  void dispose() {
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        mic.cancel();
      } catch (_) {}
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_listening) {
      // Stop manual: en lugar de descartar el audio hablado, forzar el fin
      // del habla en el VAD (submitUserSpeechOnPause) — emite onSpeechEnd
      // con lo acumulado y el turno se procesa normal.
      await VadModel.vad.stopListening();
      if (!mounted) return;
      // Si onSpeechEnd no llegó (no había habla en curso), cortar el mic y
      // volver a idle.
      if (_mic != null) {
        final mic = _mic;
        _mic = null;
        if (mic != null) {
          try {
            await mic.cancel();
          } catch (_) {}
        }
        setState(() {
          _listening = false;
          _state = LoopState.idle;
        });
      }
      return;
    }
    if (await _recorder.hasPermission() != true) {
      _fail('Permiso de micrófono denegado.');
      return;
    }
    // Si un turno anterior dejó un stop en vuelo, esperarlo antes de abrir
    // otra suscripción al stream del VAD.
    final pendingStop = _vadStopInFlight;
    _vadStopInFlight = null;
    if (pendingStop != null) await pendingStop;
    try {
      // Espera la precarga del modelo si sigue en curso (primera apertura);
      // si falló, se ignora y la escucha real carga el modelo igual.
      try {
        await _vadReady;
      } catch (_) {}
      final mic = await micPcm16Stream(_recorder);
      _mic = mic;
      setState(() {
        _listening = true;
        _state = LoopState.listening;
        _error = null;
        _thought = '';
      });
      // Silero VAD v5 (modelo local, sin CDN): distingue voz de ruido ambiente
      // (aire acondicionado, ventiladores, etc.) sin calibrar umbrales.
      // submitUserSpeechOnPause: el toque de detener fuerza el fin del habla
      // y procesa lo hablado en vez de descartarlo.
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

  Future<void> _onSpeechEnd(List<double> samples) async {
    if (!mounted || samples.isEmpty) return;
    // CORTAR LA ENTREGA AL VAD INMEDIATAMENTE: cancel() detiene los eventos
    // futuros al instante (solo el Future espera al callback en curso).
    _vadStopInFlight = VadModel.vad.stopListening();
    // El mic físico (bridge/rechunk) se corta en background.
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        await mic.cancel();
      } catch (_) {}
    }
    // Feedback inmediato: el orbe pasa a "Procesando" en el instante en que
    // termina el habla.
    setState(() {
      _listening = false;
      _busy = true;
      _state = LoopState.processing;
    });
    // El frame se pinta rápido: el VAD ya no procesa más frames y el orbe
    // cambia de estado con un corte directo (sin fade de doble pintado).
    await WidgetsBinding.instance.endOfFrame;
    // En Linux (desktop) el mic lo maneja record y hay que pararlo. En
    // Android/iOS el stop corre en background vía MicStream.cancel
    // (onCancel: recorder.stop); llamar a record.stop() aquí es una llamada
    // de plataforma innecesaria que puede colgar.
    if (!Platform.isAndroid) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    if (!mounted) return;
    // El paquete original entrega floats (-1..1): convertir a PCM16 + WAV.
    final wav = pcm16ToWav(floatsToPcm16(samples));
    await _upload(wav);
  }

  Future<void> _upload(Uint8List wavBytes) async {
    setState(() {
      _busy = true;
      _state = LoopState.processing;
    });
    try {
      final sessionId = await _sessionId;
      final result = await widget.api.audioTurn(wavBytes, sessionId: sessionId);
      if (!mounted) return;
      final transcript = result['transcript'] as String? ?? '';
      final speech = result['speech'] as String?;
      final audioB64 = result['audio'] as String?;
      setState(() {
        _busy = false;
        _state = LoopState.idle;
        _thought = transcript.isNotEmpty ? '«$transcript»' : '';
        if (speech != null && speech.isNotEmpty) {
          _thought = speech;
        }
      });
      if (audioB64 != null && audioB64.isNotEmpty) {
        await _playResponse(audioB64);
      }
    } catch (e) {
      _fail('Error al enviar el audio: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playResponse(String audioB64) async {
    final bytes = base64Decode(audioB64);
    final file = File(
      '${Directory.systemTemp.path}/gamma_respuesta_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(bytes);
    try {
      await _player.open(Media(file.path), play: true);
    } catch (e) {
      _fail('Error al reproducir la respuesta: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _state = LoopState.error;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isError = _state == LoopState.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AssistantOrb(
                  state: _state,
                  onTap: _busy ? null : _toggleRecord,
                ),
                const SizedBox(height: 14),
                Text(
                  _statusLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isError
                        ? colors.error
                        : (_state == LoopState.idle
                              ? AppColors.green
                              : colors.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      isError ? _error ?? '' : _thought,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: isError
                            ? colors.error
                            : (_thought.isEmpty
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface),
                        fontWeight: _thought.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel() {
    switch (_state) {
      case LoopState.idle:
        return 'Esperando activación';
      case LoopState.listening:
        return 'Te escucho';
      case LoopState.processing:
        return 'Procesando tu solicitud';
      case LoopState.speaking:
        return 'GAMMA está respondiendo';
      case LoopState.error:
        return 'Voz no disponible';
    }
  }
}
