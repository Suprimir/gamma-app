import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/api_client.dart';
import 'features/dashboard/home_theme_controller.dart';
import 'features/spotify/spotify_player_controller.dart';
import 'features/spotify/spotify_scope.dart';
import 'features/wall_home/wall_activity_bus.dart';
import 'ui/app_colors.dart';
import 'app/app_shell.dart';

void main() {
  MediaKit.ensureInitialized();
  const baseUrl = String.fromEnvironment(
    'GAMMA_PI',
    defaultValue: 'http://127.0.0.1:8420',
  );
  runApp(
    GammaApp(
      api: ApiClient(baseUrl: baseUrl),
      // Fallback cadence with the app in the foreground: the Spotify SSE
      // stream delivers local changes instantly and this only reconciles
      // (and covers playback happening on another device).
      spotifyPollInterval: const Duration(seconds: 3),
    ),
  );
}

class GammaApp extends StatefulWidget {
  const GammaApp({
    super.key,
    required this.api,
    this.spotifyPollInterval = Duration.zero,
  });

  final ApiClient api;

  /// Fallback playback polling cadence for the Home surfaces while the app is
  /// in the foreground; SSE events converge state in between. Zero disables
  /// polling entirely (tests, previews).
  final Duration spotifyPollInterval;

  @override
  State<GammaApp> createState() => _GammaAppState();
}

class _GammaAppState extends State<GammaApp> with WidgetsBindingObserver {
  final HomeThemeController _themeController = HomeThemeController.instance;

  /// App-wide playback controller: one poll/SSE subscription shared by the wall
  /// music card, the sleep chip and the desktop dashboard.
  late final SpotifyPlayerController _spotify = SpotifyPlayerController(
    widget.api,
  );

  /// Background cadence: at least 30s (and never faster than the foreground
  /// one), so a minimized app stops burning backend-to-Spotify calls.
  Duration get _idleInterval {
    final base = widget.spotifyPollInterval;
    if (base <= Duration.zero) return Duration.zero;
    final scaled = base * 10;
    return scaled < const Duration(seconds: 30) ? const Duration(seconds: 30) : scaled;
  }

  @override
  void initState() {
    super.initState();
    // Best-effort: a missing prefs backend (e.g. widget tests) must never
    // crash startup. The default accent still applies.
    _themeController.load().catchError((Object _) {});
    WidgetsBinding.instance.addObserver(this);
    if (widget.spotifyPollInterval > Duration.zero) {
      _spotify.startPolling(interval: widget.spotifyPollInterval);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spotify.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.spotifyPollInterval <= Duration.zero) return;
    _spotify.setPollInterval(
      state == AppLifecycleState.resumed
          ? widget.spotifyPollInterval
          : _idleInterval,
      foreground: state == AppLifecycleState.resumed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController.presetIdNotifier,
      builder: (context, _) {
        final preset = _themeController.preset;
        return MaterialApp(
          title: 'GAMMA',
          theme: ThemeData(
            // Accent follows the selected appearance; the rest of the light
            // design tokens stay neutral for contrast.
            colorScheme: ColorScheme.fromSeed(
              seedColor: preset.accent,
              brightness: Brightness.light,
            ).copyWith(primary: preset.accent),
            scaffoldBackgroundColor: AppColors.bg,
          ),
          home: AppShell(
            api: widget.api,
            spotifyPollInterval: widget.spotifyPollInterval,
          ),
          // Above the Navigator: every touch anywhere (pages, pushed routes,
          // dialogs, sheets, touch keyboard) funnels through here and resets
          // the wall sleep countdown. Only WallPanelHomePage subscribes.
          // SpotifyScope also sits above the Navigator so overlay entries
          // (the sleep overlay) resolve the same shared controller.
          builder: (context, child) => SpotifyScope(
            controller: _spotify,
            child: _WallActivityProbe(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// Global touch probe for the wall idle countdown. Pointer events bubble up
/// from whatever route is on top, so a single Listener here sees activity
/// the per-page listeners can never see (e.g. the add-device dialog).
class _WallActivityProbe extends StatelessWidget {
  const _WallActivityProbe({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => WallActivityBus.poke(),
      onPointerMove: (_) => WallActivityBus.poke(),
      onPointerUp: (_) => WallActivityBus.poke(),
      child: child,
    );
  }
}
