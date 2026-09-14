import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:record/record.dart';

import '../../adaptive/adaptive_scope.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/assistant_orb.dart';
import '../../ui/audio_waves.dart';
import '../voice/mic_source.dart';
import '../voice/vad_model.dart';
import '../voice/voice_session.dart';
import 'home_theme.dart';
import 'home_theme_controller.dart';

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
  bool _suggestionBusy = false;
  MicStream? _mic;
  // Stop del VAD en vuelo: se lanza sin bloquear el envío en _onSpeechEnd y
  // se espera aquí antes de arrancar una nueva escucha.
  Future<void>? _vadStopInFlight;
  late Future<String> _sessionId;
  late final Future<void> _vadReady;
  String _themeId = HomeThemePreset.claro.id;

  HomeThemePreset get _preset => HomeThemePreset.fromId(_themeId);

  static const _allShortcuts = [
    _Shortcut('Prende la luz del living', CupertinoIcons.lightbulb),
    _Shortcut('Poné el aire en 24°', CupertinoIcons.snow),
    _Shortcut('Poné música relajante', CupertinoIcons.music_note),
    _Shortcut('Apagá todas las luces', CupertinoIcons.lightbulb),
    // iOS approx: no blinds/persiana icon — split rectangles read as slats.
    _Shortcut('Subí la persiana', CupertinoIcons.rectangle_split_3x1),
    _Shortcut('Clima de hoy', CupertinoIcons.sun_max),
    _Shortcut('Activá modo noche', CupertinoIcons.moon),
    _Shortcut('Mostrá cámaras', CupertinoIcons.videocam),
    _Shortcut('Bajá la intensidad al 40%', CupertinoIcons.brightness),
  ];

  late List<_Shortcut> _visibleShortcuts;
  int _poolCursor = 0;
  bool _wasActive = false;
  bool _initialized = false;
  int _greetingVersion = 0;

  List<_Shortcut> _nextShortcuts() {
    final result = <_Shortcut>[];
    for (var i = 0; i < 3; i++) {
      result.add(_allShortcuts[(_poolCursor + i) % _allShortcuts.length]);
    }
    _poolCursor = (_poolCursor + 3) % _allShortcuts.length;
    return result;
  }

  String _greetingBase() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _greeting() {
    return '${_greetingBase()} — ¿en qué te ayudo hoy?';
  }

  String _mobileGreetingText() {
    return '${_greetingBase()}\n¿en qué puedo ayudarte hoy?';
  }

  String _formattedDate() {
    const weekdays = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final now = DateTime.now();
    final weekday = weekdays[now.weekday - 1];
    final month = months[now.month - 1];
    return '$weekday ${now.day} de $month';
  }

  Future<void> _onSuggestionTap(String suggestion) async {
    if (_suggestionBusy || _busy) return;
    setState(() {
      _suggestionBusy = true;
      _thought = '«$suggestion»';
      _error = null;
    });
    try {
      final sessionId = await _sessionId;
      final result = await widget.api.turn(suggestion, sessionId: sessionId);
      if (!mounted) return;
      final speech = result['speech']?.toString();
      setState(() {
        _suggestionBusy = false;
        if (speech != null && speech.isNotEmpty) _thought = speech;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _suggestionBusy = false;
        _state = LoopState.error;
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _loadTheme() async {
    final id = await HomeThemeController.loadPresetId();
    if (mounted) {
      setState(() => _themeId = id);
    }
  }

  Future<void> _selectTheme(String id) async {
    final normalized = HomeThemePreset.fromId(id).id;
    setState(() => _themeId = normalized);
    await HomeThemeController.savePresetId(normalized);
  }

  Future<void> _openThemePicker() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Personalizar fondo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in HomeThemePreset.allPresets)
                  _ThemePresetTile(
                    preset: preset,
                    selected: preset.id == _themeId,
                    onTap: () => Navigator.of(context).pop(preset.id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
    if (selected != null && selected != _themeId) {
      await _selectTheme(selected);
    }
  }

  @override
  void initState() {
    super.initState();
    _visibleShortcuts = _nextShortcuts();
    _sessionId = getOrCreateVoiceSessionId();
    _vadReady = VadModel.ensureReady();
    _loadTheme();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    if (!_initialized) {
      _initialized = true;
      _wasActive = isActive;
      return;
    }
    if (!_wasActive && isActive) {
      final isDesktop =
          AppAdaptiveScope.maybeOf(context)?.isDesktopSurface ?? true;
      final shouldRotate = _visibleShortcuts.isNotEmpty;
      final shouldAnimateGreeting = !isDesktop;
      if (shouldAnimateGreeting || shouldRotate) {
        setState(() {
          if (shouldAnimateGreeting) _greetingVersion++;
          if (shouldRotate) _visibleShortcuts = _nextShortcuts();
        });
      }
    }
    _wasActive = isActive;
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
    if (!kIsWeb && !Platform.isAndroid) {
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
    if (kIsWeb) {
      _fail(
        'La reproducción de voz no está disponible en la versión web todavía.',
      );
      return;
    }
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
    final preset = _preset;
    final showPicker =
        AppAdaptiveScope.maybeOf(context)?.isDesktopSurface ?? true;
    final isDesktop =
        AppAdaptiveScope.maybeOf(context)?.isDesktopSurface ?? true;
    final isListening = _listening || _state == LoopState.listening;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: preset.gradientColors,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDesktop) ...[
                          // Premium header card — frosted pill/card with hierarchy.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceRaised.withValues(
                                alpha: 0.72,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.shadow.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentTint,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        size: 12,
                                        color: AppColors.accent,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formattedDate(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textDim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _greeting(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                    height: 1.2,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Tocá el orbe o elegí un atajo',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ] else ...[
                          const SizedBox(height: 64),
                          _TypewriterText(
                            key: ValueKey(_greetingVersion),
                            text: _mobileGreetingText(),
                          ),
                          const SizedBox(height: 28),
                        ],
                        // Soft glow behind orb — static, cheap.
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            IgnorePointer(
                              child: Container(
                                width: 260,
                                height: 260,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      AppColors.orbBlue.withValues(alpha: 0.10),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            AssistantOrb(
                              state: _state,
                              onTap: _busy ? null : _toggleRecord,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _statusLabel(isDesktop: isDesktop),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isDesktop
                                ? FontWeight.w500
                                : (_state == LoopState.idle
                                      ? FontWeight.w400
                                      : FontWeight.w500),
                            color: isError
                                ? colors.error
                                : (_state == LoopState.idle
                                      ? (isDesktop
                                            ? AppColors.green
                                            : AppColors.textFaint)
                                      : colors.onSurfaceVariant),
                          ),
                        ),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          opacity: isListening ? 1 : 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            height: isListening ? 32 : 0,
                            alignment: Alignment.center,
                            child: isListening
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: AudioWaves(listening: isListening),
                                  )
                                : const SizedBox.shrink(),
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
                        if (isDesktop &&
                            _thought.isEmpty &&
                            !isError &&
                            _state == LoopState.idle) ...[
                          const SizedBox(height: 18),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.94,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.08),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: Wrap(
                              key: ValueKey(
                                _visibleShortcuts.map((s) => s.label).join(','),
                              ),
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final shortcut in _visibleShortcuts)
                                  ActionChip(
                                    label: Text(
                                      shortcut.label,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    avatar: Icon(
                                      shortcut.icon,
                                      size: 16,
                                      color: AppColors.textDim,
                                    ),
                                    backgroundColor: AppColors.surfaceRaised,
                                    side: const BorderSide(
                                      color: AppColors.border,
                                    ),
                                    onPressed: () =>
                                        _onSuggestionTap(shortcut.label),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              if (showPicker)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Personalizar fondo',
                    icon: const Icon(CupertinoIcons.paintbrush),
                    color: AppColors.textDim,
                    onPressed: _openThemePicker,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel({required bool isDesktop}) {
    switch (_state) {
      case LoopState.idle:
        return isDesktop
            ? 'Esperando activación'
            : 'Decí "Oye Gamma" o tocá el orbe';
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

class _TypewriterText extends StatefulWidget {
  const _TypewriterText({super.key, required this.text});

  final String text;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Restart animation when returning to the screen if needed.
    if (_controller.status == AnimationStatus.completed) {
      // Keep completed state; but if visibility changed we ensure replay on demand.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final progress = _curve.value.clamp(0.0, 1.0);
        final len = (widget.text.length * progress).floor().clamp(
          0,
          widget.text.length,
        );
        final visible = widget.text.substring(0, len);
        return Text(
          visible,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            height: 1.3,
          ),
        );
      },
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ThemePresetTile extends StatelessWidget {
  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final HomeThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in preset.gradientColors)
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1A14202D)),
              ),
            ),
        ],
      ),
      title: Text(
        preset.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(preset.description, style: const TextStyle(fontSize: 12)),
      trailing: Icon(
        selected
            ? CupertinoIcons.smallcircle_fill_circle
            : CupertinoIcons.circle,
        color: selected ? AppColors.accent : AppColors.textFaint,
      ),
    );
  }
}
