import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:record/record.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../data/device_inventory.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../ui/app_colors.dart';
import '../../ui/assistant_orb.dart';
import '../../ui/audio_waves.dart';
import '../../ui/open_in_new_tab.dart';
import 'home_theme_background.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/spotify_logo.dart';
import '../areas/area_editor.dart';
import '../areas/areas_page.dart';
import '../cameras/cameras_page.dart';
import '../cameras/cameras_player_page.dart';
import '../devices/desktop_devices_page.dart';
import '../routines/routines_editor_page.dart';
import '../routines/routines_page.dart';
import '../settings/settings_page.dart';
import '../spotify/spotify_player_controller.dart';
import '../voice/mic_source.dart';
import '../voice/vad_model.dart';
import '../voice/voice_session.dart';
import '../wall_home/wall_home_projection.dart';
import '../wall_home/wall_quick_actions_usage.dart';
import 'home_derivations.dart';

class DesktopDashboardPage extends StatefulWidget {
  const DesktopDashboardPage({
    super.key,
    required this.api,
    this.spotifyPollInterval = Duration.zero,
  });

  final ApiClient api;

  /// Fallback playback polling cadence for the Spotify card; zero (default,
  /// tests) keeps polling and SSE off. Production wires 30s through AppShell
  /// and SSE events converge state in between.
  final Duration spotifyPollInterval;

  @override
  State<DesktopDashboardPage> createState() => _DesktopDashboardPageState();
}

class _DesktopDashboardPageState extends State<DesktopDashboardPage>
    with TickerProviderStateMixin {
  DeviceInventorySnapshot? _snapshot;
  Object? _error;
  Object? _refreshError;
  bool _loading = true;

  /// Cameras explicitly reported online by `GET /api/v1/cameras/status`, or
  /// null when that call failed: unknown is never rendered as a count/dot.
  CameraStatusJoin? _cameraStatuses;
  int? _onlineCameras;

  /// Home sections render from the same single source loaded in [_loadData]:
  /// the canonical snapshot plus the already-fetched camera/routine/spotify
  /// lists. No second source of truth is introduced here.
  List<Map<String, dynamic>> _cameras = const [];
  List<Map<String, dynamic>> _routines = const [];
  List<Map<String, dynamic>> _playlists = const [];
  bool _spotifyConnected = false;

  /// Guards the one-shot settings/playlists refetch that runs once the player
  /// answers: duplicate in-flight reads are skipped and failures keep the
  /// previously loaded data.
  bool _spotifyDetailsRefreshInFlight = false;

  /// Pins the launcher (header + playlists) over active playback after the
  /// user picks "Ver playlists" in the player overflow. A new track resets it
  /// so the card returns to the player state on its own.
  bool _showLibrary = false;

  /// Local scrub position while the user drags the progress slider; null
  /// means "follow the controller's interpolated position".
  int? _spotifySeekPreviewMs;

  /// Last track uri seen by the shared listener, used to detect track changes
  /// without rebuilding the card on every position tick.
  String? _lastTrackUri;

  /// Canonical playback state shared by the now-playing block, the transport
  /// and the device picker. Owned here; disposed with the page.
  late final SpotifyPlayerController _spotify = SpotifyPlayerController(
    widget.api,
  );

  late final AnimationController _staggerController;
  late final Animation<double> _staggerCurved;

  bool _wasActive = false;
  bool _initialized = false;
  int _animationVersion = 0;

  bool _loadStarted = false;

  // Voice state — same as mobile DashboardPage.
  final _recorder = AudioRecorder();
  final _player = Player();
  LoopState _state = LoopState.idle;
  String _thought = '';
  String? _voiceError;
  bool _listening = false;
  bool _busy = false;
  MicStream? _mic;
  Future<void>? _vadStopInFlight;
  late Future<String> _sessionId;
  late final Future<void> _vadReady;

  // Assistant text input (Escribe o habla…) via POST /api/v1/turns.
  final _inputController = TextEditingController();
  bool _sendingText = false;

  // 1-tap quick actions via POST /api/v1/turns (same contract as chat).
  bool _quickBusy = false;
  String? _quickBusyKey;

  static const _quickActions = [
    (
      key: 'apagar',
      icon: Icons.power_settings_new_outlined,
      label: 'Apagar todo',
      command: 'Apagá todas las luces',
    ),
    (
      key: 'noche',
      icon: Icons.nightlight_outlined,
      label: 'Modo noche',
      command: 'Activá modo noche',
    ),
    (
      key: 'segura',
      icon: Icons.shield_outlined,
      label: 'Asegurar casa',
      command: 'Asegurá la casa',
    ),
    (
      key: 'fuera',
      icon: Icons.home_outlined,
      label: 'Modo fuera',
      command: 'Activá modo fuera',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _staggerCurved = CurvedAnimation(
      parent: _staggerController,
      curve: Curves.easeOutCubic,
    );
    _sessionId = getOrCreateVoiceSessionId();
    _vadReady = VadModel.ensureReady();
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _state = playing ? LoopState.speaking : LoopState.idle);
      }
    });
    VadModel.vad.onSpeechEnd.listen((samples) => _onSpeechEnd(samples));
    VadModel.vad.onVADMisfire.listen((_) {
      if (mounted && _listening) {
        setState(() => _state = LoopState.listening);
      }
    });
    VadModel.vad.onError.listen((message) {
      if (mounted && _listening) _fail('Error del VAD: $message');
    });
    // The settings read happens once in [_loadData]; the listener converges
    // the card when the playback backend starts answering (fresh auth).
    _spotify.addListener(_onSpotifyAvailabilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    if (!_initialized) {
      _initialized = true;
      _wasActive = isActive;
      if (isActive && !_loadStarted) {
        _loadStarted = true;
        _staggerController.forward(from: 0);
        _loadData();
      }
      return;
    }
    if (!_wasActive && isActive) {
      setState(() => _animationVersion++);
      _staggerController.forward(from: 0);
    }
    _wasActive = isActive;
    if (isActive && !_loadStarted) {
      _loadStarted = true;
      _staggerController.forward(from: 0);
      _loadData();
    }
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
    _inputController.dispose();
    _player.dispose();
    _spotify.removeListener(_onSpotifyAvailabilityChanged);
    _spotify.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (kIsWeb) {
      _fail('La voz no está disponible en la versión web todavía.');
      return;
    }
    if (_listening) {
      await VadModel.vad.stopListening();
      if (!mounted) return;
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
    final pendingStop = _vadStopInFlight;
    _vadStopInFlight = null;
    if (pendingStop != null) await pendingStop;
    try {
      try {
        await _vadReady;
      } catch (_) {}
      final mic = await micPcm16Stream(_recorder);
      _mic = mic;
      setState(() {
        _listening = true;
        _state = LoopState.listening;
        _voiceError = null;
        _thought = '';
      });
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
    _vadStopInFlight = VadModel.vad.stopListening();
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        await mic.cancel();
      } catch (_) {}
    }
    setState(() {
      _listening = false;
      _busy = true;
      _state = LoopState.processing;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!kIsWeb && !Platform.isAndroid) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    if (!mounted) return;
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
      setState(() {
        _busy = false;
        _state = LoopState.idle;
        _thought = transcript.isNotEmpty ? '«$transcript»' : '';
        if (speech != null && speech.isNotEmpty) {
          _thought = speech;
        }
      });
      final audioB64 = result['audio'] as String?;
      if (audioB64 != null && audioB64.isNotEmpty) {
        await _playResponse(audioB64);
      }
      _loadData();
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
      _voiceError = message;
    });
  }

  /// Sends a text order to the assistant through the frozen turns contract
  /// (same as ChatPage). Refreshes home counts afterwards so Estado del
  /// hogar stays canonical.
  Future<void> _sendAssistantText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sendingText) return;
    setState(() {
      _sendingText = true;
      _voiceError = null;
    });
    try {
      final sessionId = await _sessionId;
      final result = await widget.api.turn(text, sessionId: sessionId);
      if (!mounted) return;
      final speech = result['speech'] as String?;
      final deviceResults = result['device_results'] as List?;
      final reply = StringBuffer();
      if (speech != null && speech.isNotEmpty) reply.write(speech);
      if (deviceResults != null && deviceResults.isNotEmpty) {
        for (final d in deviceResults) {
          final m = d is Map ? d['message'] : null;
          if (m != null && m.toString().isNotEmpty) reply.write('\n• $m');
        }
      }
      setState(() {
        _sendingText = false;
        _thought = reply.isEmpty ? '(sin respuesta)' : reply.toString();
      });
      _inputController.clear();
      _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingText = false;
        _state = LoopState.error;
        _voiceError = 'Error: $e';
      });
    }
  }

  Future<void> _runQuickAction(String key, String command) async {
    if (_quickBusy) return;
    setState(() {
      _quickBusy = true;
      _quickBusyKey = key;
    });
    try {
      // Best-effort cross-surface usage count; never gates the action.
      unawaited(WallQuickActionsUsage.recordUse(key));
      final sessionId = await _sessionId;
      final result = await widget.api.turn(command, sessionId: sessionId);
      if (!mounted) return;
      final speech = result['speech']?.toString() ?? 'Listo.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(speech)));
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo ejecutar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _quickBusy = false;
          _quickBusyKey = null;
        });
      }
    }
  }

  static const _externalUrlChannel = MethodChannel('gamma_app/external_url');

  Future<void> _connectSpotify() async {
    try {
      final data = await widget.api.spotifyAuthStart();
      final url = data['auth_url']?.toString();
      if (url == null || url.isEmpty) {
        throw StateError('URL de autorización vacía');
      }
      if (kIsWeb) {
        openInNewTab(url);
        return;
      }
      if (Platform.isAndroid) {
        await _externalUrlChannel.invokeMethod<void>('openUrl', {'url': url});
      } else if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [url]);
        if (result.exitCode != 0) {
          throw StateError('No se pudo abrir el navegador.');
        }
      } else {
        throw UnsupportedError('desktop-connect');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autorizá GAMMA en Spotify y la conexión se completa sola.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      // Windows/desktop: no external-url channel here — Ajustes owns the
      // platform-specific connect flow, so route there instead of faking it.
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SettingsPage(api: widget.api)),
      );
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
      _refreshError = null;
    });
    try {
      final repository = HttpDeviceInventoryRepository(widget.api);
      final snapshot = await repository.load().timeout(
        const Duration(milliseconds: 1200),
      );
      final camFuture = widget.api
          .cameraModule()
          .timeout(const Duration(milliseconds: 900))
          .then<({List<Map<String, dynamic>> cameras, bool enabled})>(
            (v) => v,
            onError: (_) => (cameras: <Map<String, dynamic>>[], enabled: false),
          );
      final cameraStatusFuture = widget.api
          .cameraStatus()
          .timeout(const Duration(milliseconds: 900))
          .then<({List<Map<String, dynamic>> statuses, bool ok})>(
            (data) => (
              statuses:
                  (data['statuses'] as List?)?.cast<Map<String, dynamic>>() ??
                  const <Map<String, dynamic>>[],
              ok: true,
            ),
            onError: (_) =>
                (statuses: const <Map<String, dynamic>>[], ok: false),
          );
      final routinesFuture = widget.api
          .routines()
          .timeout(const Duration(milliseconds: 900))
          .catchError((_) => <Map<String, dynamic>>[]);
      final spotifySettingsFuture = widget.api
          .spotifySettings()
          .timeout(const Duration(milliseconds: 900))
          .catchError((_) => <String, dynamic>{});
      final spotifyPlaylistsFuture = widget.api
          .spotifyPlaylists(limit: 6)
          .timeout(const Duration(milliseconds: 900))
          .catchError((_) => <String, dynamic>{'playlists': []});

      final results = await Future.wait([
        camFuture,
        cameraStatusFuture,
        routinesFuture,
        spotifySettingsFuture,
        spotifyPlaylistsFuture,
      ]);

      final camResult =
          results[0] as ({List<Map<String, dynamic>> cameras, bool enabled});
      final cameraStatusResult =
          results[1] as ({List<Map<String, dynamic>> statuses, bool ok});
      final routines = results[2] as List<Map<String, dynamic>>;
      final spotifySettings = results[3] as Map<String, dynamic>;
      final playlistsData = results[4] as Map<String, dynamic>;

      final cameras = camResult.cameras;
      // Only an explicit `online` from /cameras/status counts or lights a
      // dot; a failed status call keeps the count unknown ('—/neutral').
      final cameraStatuses = cameraStatusResult.ok
          ? joinCameraStatuses(cameraStatusResult.statuses)
          : null;
      final onlineCameras = cameraStatuses == null
          ? null
          : countOnlineCameras(cameras, cameraStatuses);

      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _cameras = cameras;
        _routines = routines;
        _cameraStatuses = cameraStatuses;
        _onlineCameras = onlineCameras;
        _spotifyConnected =
            spotifySettings['authenticated'] == true &&
            spotifySettings['client_id_configured'] != false;
        _playlists =
            (playlistsData['playlists'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [];
        _error = null;
        _refreshError = null;
      });
      // Playback state is its own async source: the card converges on the
      // canonical backend state without blocking the home load.
      unawaited(_spotify.refresh());
      _spotify.startPolling(interval: widget.spotifyPollInterval);
    } catch (error, stackTrace) {
      debugPrint('DesktopDashboard _loadData error: $error\n$stackTrace');
      if (!mounted) return;
      if (_snapshot != null) {
        setState(() => _refreshError = error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo actualizar el inicio')),
          );
        }
      } else {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The desktop shell paints the theme-aware gradient behind this page.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: _buildBody()),
    );
  }

  /// Home layout (touch-first desktop):
  /// top area (tall assistant + spotify/estado column on the left,
  /// acciones + rutinas on the right) → cámaras en vivo → áreas.
  /// No greeting/date header, no recent-activity strip.
  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return MessageView(
        message: 'No se pudo cargar el inicio',
        onRetry: _loadData,
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _staggered(0, _buildToolbar()),
              if (_refreshError != null) ...[
                const SizedBox(height: 12),
                _buildRefreshBanner(),
              ],
              const SizedBox(height: 12),
              _staggered(1, _buildTopArea(snapshot)),
              const SizedBox(height: 12),
              _staggered(2, _buildAreasCard(snapshot)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Minimal toolbar: no greeting, no date — just refresh.
  Widget _buildToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh_outlined),
          color: AppColors.textDim,
          onPressed: _loading ? null : _loadData,
        ),
      ],
    );
  }

  Widget _buildRefreshBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem, size: 18, color: AppColors.textDim),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'No se pudo actualizar el inicio',
              style: TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ),
          TextButton(onPressed: _loadData, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _staggered(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerCurved,
      builder: (context, _) {
        final start = (index * 0.15).clamp(0.0, 1.0);
        final end = (0.5 + index * 0.15).clamp(0.0, 1.0);
        double progress;
        if (_staggerCurved.value <= start) {
          progress = 0;
        } else if (_staggerCurved.value >= end) {
          progress = 1;
        } else {
          progress = (_staggerCurved.value - start) / (end - start);
        }
        final opacity = progress;
        final dy = 12 * (1 - progress);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
      child: child,
    );
  }

  // ---------------------------------------------------------------- top row

  /// Top area, row by row:
  /// row 1: assistant + Spotify + (acciones + rutinas);
  /// row 2: cámaras (wide) + estado.
  /// Áreas goes below as its own full-width section.
  Widget _buildTopArea(DeviceInventorySnapshot snapshot) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1100) {
          return Column(
            children: [
              // Row 1: assistant + Spotify stretch to match acciones+rutinas.
              // IntrinsicHeight gives the stretch Row a finite height inside
              // the vertical scroll.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildAssistantCard()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSpotifyCard()),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 330,
                      child: Column(
                        children: [
                          _buildQuickActionsCard(),
                          const SizedBox(height: 12),
                          _buildRoutinesCard(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Row 2: wide cámaras + estado, tops aligned.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildCamerasSection()),
                  const SizedBox(width: 12),
                  SizedBox(width: 330, child: _buildHomeStatusCard(snapshot)),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAssistantCard(),
            const SizedBox(height: 12),
            _buildSpotifyCard(),
            const SizedBox(height: 12),
            _buildQuickActionsCard(),
            const SizedBox(height: 12),
            _buildRoutinesCard(),
            const SizedBox(height: 12),
            _buildCamerasSection(),
            const SizedBox(height: 12),
            _buildHomeStatusCard(snapshot),
          ],
        );
      },
    );
  }

  /// Assistant card keeps OUR orb design (orb + typewriter + waves +
  /// thought/error), laid out vertically and centered: it stretches to fill
  /// the height next to the Spotify/Estado column.
  Widget _buildAssistantCard() {
    final isListening = _listening || _state == LoopState.listening;
    final isError = _state == LoopState.error;
    return _HomeCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 192,
                height: 192,
                child: AssistantOrb(
                  state: _state,
                  onTap: _busy || _sendingText ? null : _toggleRecord,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
              SizedBox(width: 6),
              Text(
                'GAMMA',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _DesktopTypewriter(
            key: ValueKey('orb-help-$_animationVersion'),
            text: '¿En qué te ayudo?',
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isListening ? 1 : 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: isListening ? 28 : 0,
              child: isListening
                  ? const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: AudioWaves(listening: true),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (_thought.isNotEmpty || isError)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                isError ? (_voiceError ?? '') : _thought,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isError ? Colors.red.shade700 : AppColors.textDim,
                ),
              ),
            ),
          const SizedBox(height: 64),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_sendingText,
                  onSubmitted: _sendAssistantText,
                  decoration: InputDecoration(
                    hintText: 'Escribe o habla…',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textFaint,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceRaised,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_sendingText)
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else
                IconButton.filled(
                  tooltip: _listening ? 'Detener' : 'Hablar',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                  ),
                  onPressed: _busy ? null : _toggleRecord,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeStatusCard(DeviceInventorySnapshot snapshot) {
    final status = deriveHomeStatus(snapshot);
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.home_outlined,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Estado del hogar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatusPill(tone: status.tone),
          const SizedBox(height: 6),
          _StatusRow(
            icon: Icons.lightbulb_outline,
            label: 'Dispositivos activos',
            value: status.valueLabel,
            subtitle: status.subtitle,
          ),
          const Divider(height: 20, color: AppColors.border),
          _StatusRow(
            icon: Icons.videocam_outlined,
            label: 'Cámaras conectadas',
            value: _onlineCameras?.toString() ?? '—',
          ),
          const Divider(height: 20, color: AppColors.border),
          _StatusRow(
            icon: Icons.auto_awesome_outlined,
            label: 'Rutinas configuradas',
            value: '${_routines.length}',
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Areas

  Widget _buildAreasCard(DeviceInventorySnapshot snapshot) {
    final wall = projectWallHome(snapshot);
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.home_outlined,
            title: 'Áreas',
            actionLabel: wall.areas.isEmpty ? null : 'Ver todas',
            onAction: wall.areas.isEmpty ? null : _openAllAreas,
          ),
          const SizedBox(height: 12),
          if (wall.areas.isEmpty)
            const Text(
              'Aún no hay áreas configuradas',
              style: TextStyle(fontSize: 13, color: AppColors.textDim),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 208,
              ),
              itemCount: wall.areas.length,
              itemBuilder: (context, i) {
                final area = wall.areas[i];
                return _AreaPhotoTile(
                  key: ValueKey('desktop-area-${area.areaId}'),
                  name: area.name,
                  count: area.controlCount,
                  hasOn: areaHasPowerOn(snapshot, area.areaId),
                  index: i,
                  onTap: () => _onAreaTap(area),
                );
              },
            ),
        ],
      ),
    );
  }

  void _openAllAreas() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Theme-aware route: pushed pages live outside the shell's backdrop,
        // and the desktop areas workspace root is transparent.
        builder: (_) => HomeThemeBackground(
          child: AreasPage(
            repository: HttpDeviceInventoryRepository(widget.api),
          ),
        ),
      ),
    );
  }

  /// Wall parity: "Ver dispositivos" pushes the desktop Devices workspace
  /// pre-filtered to this area, with a back affordance (the page has no AppBar
  /// of its own when hosted in the shell).
  Future<void> _openArea(WallAreaSummary area) async {
    final controller = AdaptiveFeatureController(
      HttpDeviceInventoryRepository(widget.api),
    );
    unawaited(controller.loadDevices());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Theme-aware route: pushed pages live outside the shell's backdrop,
        // so they carry it explicitly.
        builder: (_) => HomeThemeBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: Text(area.name),
            ),
            body: DesktopDevicesPage(
              controller: controller,
              api: widget.api,
              initialLocationId: area.areaId,
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  /// Desktop parity with the wall Home area menu: tapping an area tile opens
  /// a compact "Elegí una acción" dialog (Ver dispositivos / Editar / Eliminar)
  /// and dispatches to the matching action. Mutations reload canonical data.
  Future<void> _onAreaTap(WallAreaSummary area) async {
    final action = await _showDesktopAreaActions(context, area.name);
    if (action == null || !mounted) return;
    switch (action) {
      case _DesktopAreaAction.view:
        await _openArea(area);
      case _DesktopAreaAction.edit:
        await _editArea(area);
      case _DesktopAreaAction.delete:
        await _deleteArea(area);
    }
  }

  HomeArea? _homeArea(String areaId) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    for (final area in snapshot.areas) {
      if (area.id == areaId) return area;
    }
    return null;
  }

  Future<void> _editArea(WallAreaSummary area) async {
    final current = _homeArea(area.areaId);
    final result = await showDialog<({String name, List<String> aliases})>(
      context: context,
      builder: (_) => AreaEditorDialog(
        title: 'Editar área',
        submitLabel: 'Guardar',
        initialName: current?.name ?? area.name,
        initialAliases: current?.aliases ?? const [],
        showAliases: false,
        decorated: true,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await HttpDeviceInventoryRepository(
        widget.api,
      ).updateArea(area.areaId, name: result.name, aliases: result.aliases);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área actualizada.')));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  Future<void> _deleteArea(WallAreaSummary area) async {
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (!confirmed || !mounted) return;
    try {
      await HttpDeviceInventoryRepository(widget.api).deleteArea(area.areaId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área eliminada.')));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  // --------------------------------------------------------------- cameras

  /// Live cameras section (same header pattern as Áreas, same width as
  /// Estado del hogar): a horizontal strip of thumbnails, one per
  /// configured camera.
  Widget _buildCamerasSection() {
    final online = _onlineCameras;
    return _HomeCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.videocam_outlined,
            title: 'Cámaras en vivo',
            pill: _cameras.isEmpty
                ? null
                : online == null
                ? '— en línea'
                : '$online en línea',
            pillOk: online != null && online > 0,
            actionLabel: _cameras.isEmpty ? null : 'Ver todas',
            onAction: _cameras.isEmpty ? null : _openAllCameras,
          ),
          const SizedBox(height: 12),
          if (_cameras.isEmpty)
            const Text(
              'No hay cámaras configuradas.',
              style: TextStyle(fontSize: 13, color: AppColors.textDim),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _cameras.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    _CameraThumb(
                      key: ValueKey(
                        'desktop-cam-${_cameras[i]['camera_id'] ?? i}',
                      ),
                      camera: _cameras[i],
                      api: widget.api,
                      online: _cameraStatuses?.onlineFor(
                        _cameras[i]['camera_id']?.toString(),
                      ),
                      onTap: () => _openCameraLive(_cameras[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openAllCameras() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CamerasPage(api: widget.api, showBackButton: true),
      ),
    );
  }

  void _openCameraLive(Map<String, dynamic> camera) {
    final cameraId = camera['camera_id']?.toString();
    if (cameraId == null || cameraId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${camera['name']?.toString() ?? 'Cámara'} — vista previa no disponible',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraPlayerPage(api: widget.api, camera: camera),
      ),
    );
  }

  // --------------------------------------------------------------- spotify

  /// Converges the card when the playback backend starts answering: a fresh
  /// authorization (from Settings or the wall) leaves the one-shot settings
  /// read stale, so the connect affordance would otherwise persist until the
  /// next reload. A player response is proof of a usable account; the
  /// capabilities read is unchanged.
  void _onSpotifyAvailabilityChanged() {
    if (!mounted) return;
    // A new track always brings the player state back: the "Ver playlists"
    // pin only lasts while the current track keeps playing.
    final trackUri = _spotify.track?['uri']?.toString();
    if (_showLibrary && trackUri != null && trackUri != _lastTrackUri) {
      setState(() => _showLibrary = false);
    }
    _lastTrackUri = trackUri;
    if (_spotifyConnected) return;
    if (_spotify.needsAuth || _spotify.player == null) return;
    setState(() => _spotifyConnected = true);
    unawaited(_refreshSpotifyDetails());
  }

  /// One-shot refetch of the playlists loaded in [_loadData], triggered once
  /// the player answers. Never polls: the settings endpoint hits Spotify
  /// upstream. Failures keep the previous data.
  Future<void> _refreshSpotifyDetails() async {
    if (_spotifyDetailsRefreshInFlight) return;
    _spotifyDetailsRefreshInFlight = true;
    try {
      try {
        final playlistsData = await widget.api.spotifyPlaylists(limit: 6);
        if (!mounted) return;
        setState(() {
          _playlists =
              (playlistsData['playlists'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
        });
      } catch (_) {
        // Keep the previous playlists.
      }
    } finally {
      _spotifyDetailsRefreshInFlight = false;
    }
  }

  /// Spotify card with progressive disclosure. Three bodies share the same
  /// canonical controller:
  /// - player: hero (art + track + transport), thin progress, single up-next
  ///   line and the secondary icon row;
  /// - launcher: compact header, account, playlists and the settings link
  ///   (also reachable while playing through "Ver playlists");
  /// - disconnected: unchanged connect CTA.
  Widget _buildSpotifyCard() {
    return _HomeCard(
      child: ListenableBuilder(
        listenable: _spotify,
        builder: (context, _) {
          // A player 401/503 means the account is not usable even when the
          // settings read said otherwise: keep the connect affordance.
          final connected = _spotifyConnected && !_spotify.needsAuth;
          final track = _spotify.track;
          final hasPlayback =
              (_spotify.player != null &&
                  _spotify.player!['has_playback'] == true) ||
              track != null;
          return Column(
            // Fully centered so the card looks intentional when stretched
            // tall next to the assistant; every body stays compact.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!connected)
                _buildSpotifyDisconnected()
              else if (hasPlayback && !_showLibrary)
                _buildSpotifyPlayer(track)
              else
                _buildSpotifyLauncher(pinned: hasPlayback),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpotifyDisconnected() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildSpotifyHeader(connected: false),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Conectá tu cuenta para ver tu música acá.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: FilledButton.icon(
            onPressed: _connectSpotify,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Conectar Spotify'),
          ),
        ),
      ],
    );
  }

  /// Compact logo + name + connection pill used by the launcher and the
  /// disconnected CTA (the player state is identified by the hero instead).
  Widget _buildSpotifyHeader({required bool connected}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SpotifyLogo(size: 24),
        const SizedBox(width: 8),
        const Text(
          'Spotify',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        if (!connected) ...[
          const SizedBox(width: 8),
          _Pill(text: 'Sin conectar', ok: false),
        ],
      ],
    );
  }

  /// Launcher body: header, optional account line, the playlist shortcuts and
  /// the settings link. [pinned] is true when the user opened it from the
  /// player overflow while playback continues.
  Widget _buildSpotifyLauncher({required bool pinned}) {
    final visible = _playlists.take(3).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _buildSpotifyHeader(connected: true)),
        if (pinned) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showLibrary = false),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('Volver al reproductor'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ] else ...[
          const SizedBox(height: 10),
          const Text(
            'Sin reproducción',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Tu música',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Text(
            'No se encontraron playlists en tu cuenta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          )
        else
          for (final playlist in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PlaylistRow(
                playlist: playlist,
                onTap: () => _playPlaylist(playlist),
              ),
            ),
        TextButton(
          onPressed: _openSpotifySettings,
          child: const Text('Abrir ajustes de Spotify'),
        ),
        if (_spotify.error != null) ...[
          const SizedBox(height: 4),
          Text(
            _spotify.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }

  /// Player body: hero, compact progress, single up-next line and the
  /// secondary icon row. No account, queue list or playlists stack here.
  Widget _buildSpotifyPlayer(Map<String, dynamic>? track) {
    final name = track?['name']?.toString();
    final artist = track?['artist']?.toString();
    final deviceName = _spotify.activeDevice?['name']?.toString();
    final subtitle = [
      if (artist != null && artist.isNotEmpty) artist,
      if (deviceName != null && deviceName.isNotEmpty) deviceName,
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SpotifyArtwork(
              imageUrl: track?['image_url']?.toString(),
              size: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (name == null || name.isEmpty) ? 'Sin título' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            _buildSpotifyTransport(),
          ],
        ),
        _buildSpotifyProgress(),
        _buildSpotifyUpNext(),
        const SizedBox(height: 8),
        _buildSpotifyActionIcons(),
        if (_spotify.error != null) ...[
          const SizedBox(height: 6),
          Text(
            _spotify.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }

  /// Volume reported by the player, else by the active device, else null.
  int? _spotifyVolume() {
    final playerVolume = _spotify.player?['volume_percent'];
    final deviceVolume = _spotify.activeDevice?['volume_percent'];
    if (playerVolume is int) return playerVolume;
    if (deviceVolume is int) return deviceVolume;
    return null;
  }

  /// True when the scrubber may issue a seek: the backend advertises a
  /// resolvable device and, when it sends an explicit [actions] list, a
  /// `seek` entry. Legacy responses without actions keep the old device check.
  bool _spotifySeekEnabled() {
    if (_spotify.activeDevice == null) return false;
    final actions = _spotify.player?['actions'];
    final gated = actions is List && actions.isNotEmpty;
    return gated ? _spotify.actionEnabled('seek') : true;
  }

  /// Progress scrubber: a thin slider over the controller's interpolated
  /// position. Dragging previews locally (label follows the finger, no
  /// traffic); the seek commits on drag end / tap. When seeking is disabled
  /// it degrades to the non-interactive bar.
  Widget _buildSpotifyProgress() {
    final duration = _spotify.durationMs;
    if (_spotify.track == null || duration == null || duration <= 0) {
      return const SizedBox.shrink();
    }
    final canonical = (_spotify.progressMs ?? 0).clamp(0, duration);
    if (!_spotifySeekEnabled()) {
      return _buildSpotifyProgressBar(canonical, duration);
    }
    final position = (_spotifySeekPreviewMs ?? canonical).clamp(0, duration);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              // Compact density: the SDK Slider owns its 48px touch height,
              // so the desktop scrubber pins a shorter box with small parts.
              height: 28,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.border,
                  thumbColor: AppColors.accent,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: Slider(
                  key: const ValueKey('desktop-spotify-progress'),
                  value: position.toDouble(),
                  max: duration.toDouble(),
                  onChanged: (value) =>
                      setState(() => _spotifySeekPreviewMs = value.round()),
                  onChangeEnd: (value) {
                    final target = value.round().clamp(0, duration);
                    setState(() => _spotifySeekPreviewMs = null);
                    unawaited(_spotify.seek(target));
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatPlaybackTime(position)} / ${_formatPlaybackTime(duration)}',
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  /// Non-interactive fallback for the progress row (no device, or the
  /// backend does not advertise `seek`).
  Widget _buildSpotifyProgressBar(int position, int duration) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: duration <= 0 ? 0 : position / duration,
                minHeight: 4,
                backgroundColor: AppColors.border,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatPlaybackTime(position)} / ${_formatPlaybackTime(duration)}',
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  /// Single up-next line; hidden while the queue is empty. Tapping opens the
  /// queue sheet with the full listing.
  Widget _buildSpotifyUpNext() {
    final upcoming = _spotify.upcomingQueue;
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: const ValueKey('desktop-spotify-up-next'),
        borderRadius: BorderRadius.circular(8),
        onTap: _openSpotifyQueueSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              const Icon(
                Icons.queue_music_rounded,
                size: 14,
                color: AppColors.textDim,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'A continuación · ${_formatUpNextItem(upcoming.first)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Icon-only secondary actions: volume popover, device menu, queue sheet
  /// (only with a known queue) and the overflow menu.
  Widget _buildSpotifyActionIcons() {
    final volume = _spotifyVolume();
    final muted = volume != null && volume <= 0;
    final volumeUnsupported = _spotify.targetSupportsVolume == false;
    final hasQueue =
        _spotify.upcomingQueue.isNotEmpty || _spotify.previousQueue.isNotEmpty;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('desktop-spotify-volume'),
          tooltip: volumeUnsupported
              ? spotifyVolumeUnsupportedTooltip
              : 'Volumen',
          visualDensity: VisualDensity.compact,
          disabledColor: AppColors.textFaint,
          onPressed: volumeUnsupported ? null : _openSpotifyVolumeSheet,
          icon: Icon(
            muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
        ),
        _buildSpotifyDeviceMenu(),
        if (hasQueue)
          IconButton(
            key: const ValueKey('desktop-spotify-queue'),
            tooltip: 'Ver cola',
            visualDensity: VisualDensity.compact,
            onPressed: _openSpotifyQueueSheet,
            icon: const Icon(Icons.playlist_play_rounded),
          ),
        PopupMenuButton<_SpotifyOverflowAction>(
          key: const ValueKey('desktop-spotify-overflow'),
          tooltip: 'Más opciones',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: _onSpotifyOverflow,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _SpotifyOverflowAction.settings,
              child: Text('Abrir ajustes de Spotify'),
            ),
            PopupMenuItem(
              value: _SpotifyOverflowAction.library,
              child: Text('Ver playlists'),
            ),
          ],
        ),
      ],
    );
  }

  void _onSpotifyOverflow(_SpotifyOverflowAction action) {
    switch (action) {
      case _SpotifyOverflowAction.settings:
        _openSpotifySettings();
      case _SpotifyOverflowAction.library:
        setState(() => _showLibrary = true);
    }
  }

  /// Bottom sheet with the existing volume slider; the trigger icon already
  /// reflects muted/normal from the current volume.
  Future<void> _openSpotifyVolumeSheet() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: _spotify,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Volumen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: _buildSpotifyVolumeSlider()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpotifyVolumeSlider() {
    // Explicit `supports_volume == false` disables the slider; the row stays
    // visible read-only with a hint. Unknown/null keeps the legacy behavior.
    final volumeUnsupported = _spotify.targetSupportsVolume == false;
    return _SpotifyVolumeSlider(
      value: _spotifyVolume(),
      enabled: _spotify.activeDevice != null && !volumeUnsupported,
      hint: volumeUnsupported ? spotifyVolumeUnsupportedHint : null,
      onCommit: _spotify.setVolume,
    );
  }

  /// Queue sheet with the existing row style: up to 10 upcoming items plus
  /// an "Anteriores" section when the backend reports previous tracks.
  Future<void> _openSpotifyQueueSheet() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: _spotify,
          builder: (context, _) {
            final upcoming = _spotify.upcomingQueue.take(10).toList();
            final previous = _spotify.previousQueue.take(10).toList();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'A continuación',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (upcoming.isEmpty)
                    const Text(
                      'No hay elementos en la cola.',
                      style: TextStyle(fontSize: 13, color: AppColors.textDim),
                    )
                  else
                    for (final item in upcoming) _buildSpotifyQueueRow(item),
                  if (previous.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Anteriores',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in previous) _buildSpotifyQueueRow(item),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSpotifyQueueRow(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 14,
            color: AppColors.textDim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _formatQueueItem(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  /// Transport row. When the backend advertises the executable [actions]
  /// (SSE state), gating follows that list; otherwise it falls back to the
  /// device check: a command with no active device is a guaranteed 409.
  Widget _buildSpotifyTransport() {
    final actions = _spotify.player?['actions'];
    final gated = actions is List && actions.isNotEmpty;
    final hasDevice = _spotify.activeDevice != null;
    bool enabledFor(String action) =>
        gated ? _spotify.actionEnabled(action) : hasDevice;
    final playing = _spotify.isPlaying;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Anterior',
          visualDensity: VisualDensity.compact,
          onPressed: enabledFor('skip_prev') ? _spotify.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton.filled(
          tooltip: playing ? 'Pausar' : 'Reproducir',
          onPressed: enabledFor(playing ? 'pause' : 'play')
              ? (playing ? _spotify.pause : _spotify.play)
              : null,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        IconButton(
          tooltip: 'Siguiente',
          visualDensity: VisualDensity.compact,
          onPressed: enabledFor('skip_next') ? _spotify.next : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }

  /// Icon-triggered device menu with the backend's device list. "Automático"
  /// clears the explicit pick; any other entry transfers playback there.
  Widget _buildSpotifyDeviceMenu() {
    final active = _spotify.activeDevice;
    final activeId = active?['id'];
    final hasDevice = active != null;
    return PopupMenuButton<String>(
      key: const ValueKey('desktop-spotify-device'),
      tooltip: hasDevice ? 'Elegir dispositivo' : 'Sin dispositivo activo',
      icon: Icon(hasDevice ? Icons.speaker_rounded : Icons.speaker_outlined),
      onSelected: (value) {
        if (value.isEmpty) {
          _spotify.selectDevice(null);
        } else {
          _spotify.transferTo(value);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: '',
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 8),
              const Text('Automático'),
              if (_spotify.selectedDeviceId == null && activeId != null) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16, color: AppColors.green),
              ],
            ],
          ),
        ),
        for (final device in _spotify.devices)
          PopupMenuItem<String>(
            value: device['id']?.toString() ?? '',
            child: Row(
              children: [
                Icon(
                  device['is_active'] == true
                      ? Icons.speaker
                      : Icons.speaker_outlined,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    device['name']?.toString() ??
                        device['id']?.toString() ??
                        'Dispositivo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (device['is_default'] == true) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'Predeterminado',
                    style: TextStyle(fontSize: 10, color: AppColors.textDim),
                  ),
                ],
                if (device['id'] == activeId) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 16, color: AppColors.green),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Playlist tap now commands real playback; a playlist without a URI is
  /// reported honestly instead of pretending it played.
  Future<void> _playPlaylist(Map<String, dynamic> playlist) async {
    final uri = playlist['uri']?.toString();
    if (uri == null || uri.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta playlist no tiene un URI reproducible.'),
        ),
      );
      return;
    }
    await _spotify.playContext(uri);
  }

  void _openSpotifySettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(api: widget.api)),
    );
  }

  // -------------------------------------------------------- quick actions

  Widget _buildQuickActionsCard() {
    Widget tile(int i) {
      final action = _quickActions[i];
      final busy = _quickBusy && _quickBusyKey == action.key;
      return _QuickActionTile(
        key: ValueKey('desktop-quick-${action.key}'),
        icon: action.icon,
        label: action.label,
        busy: busy,
        enabled: !_quickBusy,
        onTap: () => _runQuickAction(action.key, action.command),
      );
    }

    // Plain rows instead of GridView: this card lives inside the
    // IntrinsicHeight row that equalizes heights, and shrink-wrap grids
    // can't be measured there (blank screen / layout exceptions).
    Widget row(int a, int b) {
      return Row(
        children: [
          Expanded(child: SizedBox(height: 76, child: tile(a))),
          const SizedBox(width: 10),
          Expanded(child: SizedBox(height: 76, child: tile(b))),
        ],
      );
    }

    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.bolt_outlined,
            title: 'Acciones rápidas',
          ),
          const SizedBox(height: 12),
          row(0, 1),
          const SizedBox(height: 10),
          row(2, 3),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- routines

  /// Routines from the existing routines list: status plus tap-through to
  /// the existing editor. Creation reuses the editor with a null id.
  Widget _buildRoutinesCard() {
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.auto_awesome_outlined,
            title: 'Rutinas',
            actionLabel: _routines.isEmpty ? null : 'Ver todas',
            onAction: _routines.isEmpty ? null : _openAllRoutines,
          ),
          const SizedBox(height: 12),
          if (_routines.isEmpty) ...[
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.auto_awesome,
                  size: 40,
                  color: AppColors.accentTintStrong,
                ),
              ),
            ),
            const Center(
              child: Text(
                'Automatiza tu hogar y haz tu vida más fácil.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: FilledButton.icon(
                onPressed: _createRoutine,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Crear rutina'),
              ),
            ),
          ] else ...[
            for (final routine in _routines.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RoutineRow(
                  key: ValueKey(
                    'desktop-routine-${routine['id']?.toString() ?? routine.hashCode}',
                  ),
                  routine: routine,
                  onOpen: () => _openRoutine(routine),
                ),
              ),
            Center(
              child: TextButton.icon(
                onPressed: _createRoutine,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Crear rutina'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAllRoutines() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinesPage(api: widget.api, showBackButton: true),
      ),
    );
  }

  Future<void> _createRoutine() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RoutinesEditorPage(api: widget.api),
      ),
    );
    if (saved == true && mounted) _loadData();
  }

  Future<void> _openRoutine(Map<String, dynamic> routine) async {
    final id = routine['id']?.toString();
    if (id == null || id.isEmpty) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RoutinesEditorPage(api: widget.api, routineId: id),
      ),
    );
    if (saved == true && mounted) _loadData();
  }
}

// ------------------------------------------------------------------- cards

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    this.pill,
    this.pillOk = true,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? pill;

  /// Pill tone; false renders the neutral (unknown) variant.
  final bool pillOk;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (pill != null) ...[
                const SizedBox(width: 8),
                _Pill(text: pill!, ok: pillOk),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!, style: const TextStyle(fontSize: 12)),
                const Icon(Icons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? AppColors.statusEncendido.withValues(alpha: 0.12)
            : AppColors.textFaint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ok ? AppColors.green : AppColors.textDim,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.tone});

  final HomeStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (tone) {
      HomeStatusTone.ok => (
        'Todo funcionando',
        AppColors.green,
        AppColors.statusEncendido.withValues(alpha: 0.12),
      ),
      HomeStatusTone.check => (
        'Revisar',
        AppColors.amber,
        AppColors.amber.withValues(alpha: 0.15),
      ),
      HomeStatusTone.neutral => (
        'Sin validar',
        AppColors.textDim,
        AppColors.textFaint.withValues(alpha: 0.15),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textDim),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppColors.textDim),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textFaint,
                  ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- areas

IconData _areaIcon(String name) {
  final key = name.toLowerCase();
  if (key.contains('cocina') || key.contains('kitchen')) return Icons.kitchen;
  if (key.contains('living') || key.contains('sala') || key.contains('estar')) {
    return Icons.weekend;
  }
  if (key.contains('patio') ||
      key.contains('jard') ||
      key.contains('terraza')) {
    return Icons.grass;
  }
  if (key.contains('recámara') ||
      key.contains('recamara') ||
      key.contains('dormitorio') ||
      key.contains('habitaci') ||
      key.contains('bedroom')) {
    return Icons.bed;
  }
  if (key.contains('baño') || key.contains('bano') || key.contains('bath')) {
    return Icons.bathtub_outlined;
  }
  if (key.contains('oficina') ||
      key.contains('estudio') ||
      key.contains('office')) {
    return Icons.work_outline;
  }
  if (key.contains('comedor') || key.contains('dining')) {
    return Icons.restaurant_outlined;
  }
  if (key.contains('cochera') ||
      key.contains('garage') ||
      key.contains('garaje')) {
    return Icons.garage_outlined;
  }
  return Icons.home_outlined;
}

const _areaBanners = [
  (Color(0xFFDCE7FB), Color(0xFFB9CDF3)),
  (Color(0xFFDFF3E4), Color(0xFFB7E2C3)),
  (Color(0xFFFFEACF), Color(0xFFFFD3A1)),
  (Color(0xFFE9E2FB), Color(0xFFC9BDF0)),
];

class _AreaPhotoTile extends StatelessWidget {
  const _AreaPhotoTile({
    super.key,
    required this.name,
    required this.count,
    required this.hasOn,
    required this.index,
    required this.onTap,
  });

  final String name;
  final int count;

  /// True when a device linked to this area has a confirmed "on" state.
  final bool hasOn;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final banner = _areaBanners[index % _areaBanners.length];
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [banner.$1, banner.$2],
                  ),
                ),
                child: Center(
                  child: Icon(
                    _areaIcon(name),
                    size: 44,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count ${count == 1 ? 'control' : 'controles'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasOn
                          ? AppColors.statusEncendido
                          : AppColors.statusDesconectado,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textFaint,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DesktopAreaAction { view, edit, delete }

/// Compact desktop menu for a home area: the area name on top and view/edit/
/// delete rows using the desktop option-tile styling (no wall sheet chrome).
/// Returns the choice, or null on dismiss.
Future<_DesktopAreaAction?> _showDesktopAreaActions(
  BuildContext context,
  String areaName,
) {
  return showDialog<_DesktopAreaAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            areaName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          const Text(
            'Elegí una acción',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AreaActionOption(
              label: 'Ver dispositivos',
              icon: Icons.devices_outlined,
              onTap: () =>
                  Navigator.of(dialogContext).pop(_DesktopAreaAction.view),
            ),
            _AreaActionOption(
              label: 'Editar área',
              icon: Icons.edit_outlined,
              onTap: () =>
                  Navigator.of(dialogContext).pop(_DesktopAreaAction.edit),
            ),
            _AreaActionOption(
              label: 'Eliminar área',
              icon: Icons.delete_outline,
              destructive: true,
              onTap: () =>
                  Navigator.of(dialogContext).pop(_DesktopAreaAction.delete),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Desktop action row: soft raised surface, accent icon, red variant for
/// destructive actions.
class _AreaActionOption extends StatelessWidget {
  const _AreaActionOption({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? AppColors.errorRed : AppColors.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: accent.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: destructive ? AppColors.errorRed : AppColors.text,
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
}

// ----------------------------------------------------------------- cameras

/// One camera thumbnail: dark rounded snapshot, name bottom-left in white,
/// status dot top-right (green online, red offline). Taps through live.
class _CameraThumb extends StatelessWidget {
  const _CameraThumb({
    super.key,
    required this.camera,
    required this.api,
    required this.onTap,
    this.online,
  });

  final Map<String, dynamic> camera;
  final ApiClient api;
  final VoidCallback onTap;

  /// Explicit `/cameras/status` online flag. Null = the backend did not
  /// report this camera, so the dot stays neutral (never fabricated green).
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final cameraId = camera['camera_id']?.toString();
    final name = camera['name']?.toString() ?? 'Cámara';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 230,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF141A24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cameraId != null && cameraId.isNotEmpty)
              Image.network(
                api.cameraSnapshotUrl(cameraId),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white54,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, _, _) => const Center(
                  child: Icon(
                    Icons.videocam_off_outlined,
                    size: 30,
                    color: Colors.white38,
                  ),
                ),
              )
            else
              const Center(
                child: Icon(
                  Icons.videocam_off_outlined,
                  size: 30,
                  color: Colors.white38,
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online == true
                      ? AppColors.statusEncendido
                      : online == false
                      ? AppColors.red
                      : AppColors.statusDesconectado,
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 8,
              right: 10,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- spotify

/// Entries of the Spotify card overflow menu.
enum _SpotifyOverflowAction { settings, library }

/// Official-style Spotify mark drawn in code (green disc + three white
/// arcs): no extra icon font or binary asset needed.
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final Map<String, dynamic> playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        playlist['name']?.toString() ??
        playlist['title']?.toString() ??
        'Playlist';
    // `/api/v1/spotify/playlists` returns SpotifySearchItem entries: the
    // only honest metadata is `subtitle` plus `image_url`. The old
    // track_count/tracks reads never existed in that contract.
    final rawSubtitle = playlist['subtitle']?.toString();
    final subtitle = (rawSubtitle != null && rawSubtitle.isNotEmpty)
        ? rawSubtitle
        : 'Playlist · Spotify';
    final imageUrl = playlist['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    Widget artworkFallback() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C6FF0), Color(0xFF4F46E5)],
        ),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        size: 20,
        color: Colors.white,
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: hasImage
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (context, _, _) => artworkFallback(),
                      )
                    : artworkFallback(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Album art with the same gradient fallback used by playlist rows.
class _SpotifyArtwork extends StatelessWidget {
  const _SpotifyArtwork({this.imageUrl, this.size = 44});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    Widget fallback() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C6FF0), Color(0xFF4F46E5)],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }
}

/// Light-theme volume slider. Drag value is local so a polling refresh never
/// fights the finger; only the drag end commits to the backend. A non-null
/// [hint] renders under the row when the device cannot be volume-controlled.
class _SpotifyVolumeSlider extends StatefulWidget {
  const _SpotifyVolumeSlider({
    required this.value,
    required this.enabled,
    required this.onCommit,
    this.hint,
  });

  final int? value;
  final bool enabled;
  final ValueChanged<int> onCommit;
  final String? hint;

  @override
  State<_SpotifyVolumeSlider> createState() => _SpotifyVolumeSliderState();
}

class _SpotifyVolumeSliderState extends State<_SpotifyVolumeSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value?.toDouble() ?? 0).clamp(0.0, 100.0);
    return SizedBox(
      width: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volume_down_rounded,
                size: 18,
                color: AppColors.textDim,
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('desktop-spotify-volume-slider'),
                  value: value,
                  max: 100,
                  onChanged: widget.enabled
                      ? (v) => setState(() => _drag = v)
                      : null,
                  onChangeEnd: widget.enabled
                      ? (v) {
                          setState(() => _drag = null);
                          widget.onCommit(v.round());
                        }
                      : null,
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${value.round()}%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ],
          ),
          if (widget.hint != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                height: 1.3,
                color: AppColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ quick actions

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(icon, size: 18, color: AppColors.accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- routines

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({super.key, required this.routine, required this.onOpen});

  final Map<String, dynamic> routine;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final enabled = routine['enabled'] == true;
    final activadores =
        (routine['activadores'] as List?)?.cast<String>() ?? const [];
    final actionCount = (routine['acciones'] as List?)?.length ?? 0;
    final validationErrors =
        (routine['validation_errors'] as List?)?.cast<String>() ?? const [];
    final subtitle = validationErrors.isNotEmpty
        ? 'Requiere revisión'
        : activadores.isNotEmpty
        ? '«${activadores.first}»'
        : '$actionCount ${actionCount == 1 ? 'acción' : 'acciones'}';
    final subtitleColor = validationErrors.isNotEmpty
        ? AppColors.red
        : AppColors.textDim;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    routine['nombre']?.toString() ??
                        routine['name']?.toString() ??
                        'Rutina',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? AppColors.statusEncendido
                    : AppColors.statusDesconectado,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ misc

class _DesktopTypewriter extends StatefulWidget {
  const _DesktopTypewriter({super.key, required this.text});

  final String text;

  @override
  State<_DesktopTypewriter> createState() => _DesktopTypewriterState();
}

class _DesktopTypewriterState extends State<_DesktopTypewriter>
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
  void didUpdateWidget(covariant _DesktopTypewriter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller
        ..reset()
        ..forward();
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
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        );
      },
    );
  }
}

/// `mm:ss` for a playback position/duration in milliseconds.
String _formatPlaybackTime(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).floor();
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// `name · artist` for a queue item, degrading to whichever field exists.
String _formatQueueItem(Map<String, dynamic> item) {
  final name = item['name']?.toString() ?? '';
  final artist = item['artist']?.toString() ?? '';
  if (artist.isEmpty) return name;
  if (name.isEmpty) return artist;
  return '$name · $artist';
}

/// `name — artist` for the single up-next line, so the enclosing
/// "A continuación ·" prefix does not double the separator dot.
String _formatUpNextItem(Map<String, dynamic> item) {
  final name = item['name']?.toString() ?? '';
  final artist = item['artist']?.toString() ?? '';
  if (artist.isEmpty) return name;
  if (name.isEmpty) return artist;
  return '$name — $artist';
}
