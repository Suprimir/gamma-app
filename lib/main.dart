import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/api_client.dart';
import 'features/dashboard/home_theme_controller.dart';
import 'features/wall_home/wall_activity_bus.dart';
import 'ui/app_colors.dart';
import 'app/app_shell.dart';

void main() {
  MediaKit.ensureInitialized();
  const baseUrl = String.fromEnvironment(
    'GAMMA_PI',
    defaultValue: 'http://127.0.0.1:8420',
  );
  runApp(GammaApp(api: ApiClient(baseUrl: baseUrl)));
}

class GammaApp extends StatefulWidget {
  const GammaApp({super.key, required this.api});

  final ApiClient api;

  @override
  State<GammaApp> createState() => _GammaAppState();
}

class _GammaAppState extends State<GammaApp> {
  final HomeThemeController _themeController = HomeThemeController.instance;

  @override
  void initState() {
    super.initState();
    // Best-effort: a missing prefs backend (e.g. widget tests) must never
    // crash startup. The default accent still applies.
    _themeController.load().catchError((Object _) {});
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
          home: AppShell(api: widget.api),
          // Above the Navigator: every touch anywhere (pages, pushed routes,
          // dialogs, sheets, touch keyboard) funnels through here and resets
          // the wall sleep countdown. Only WallPanelHomePage subscribes.
          builder: (context, child) =>
              _WallActivityProbe(child: child ?? const SizedBox.shrink()),
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
