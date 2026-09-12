import 'package:flutter/material.dart';

import 'home_theme_controller.dart';

/// Soft, theme-aware gradient backdrop for desktop workspaces.
///
/// Uses the selected preset's pale gradient colors so every desktop screen
/// (Inicio, Dispositivos, Rutinas, Ajustes, Cámaras) shares the same
/// background without painting a solid saturated color. Card surfaces and
/// text stay neutral on top of it.
class HomeThemeBackground extends StatelessWidget {
  const HomeThemeBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HomeThemeController.instance.presetIdNotifier,
      builder: (context, _) {
        final preset = HomeThemeController.instance.preset;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: preset.gradientColors,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
