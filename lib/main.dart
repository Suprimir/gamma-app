import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/api_client.dart';
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

class GammaApp extends StatelessWidget {
  const GammaApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAMMA',
      theme: ThemeData(
        // The whole UI uses explicit light design tokens (AppColors). Force
        // Brightness.light so a system dark-mode device does not flip the
        // inherited colorScheme (uncolored Text/Icon widgets would otherwise
        // render light-on-dark over the light background, e.g. red/white
        // text on dark surfaces).
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.bg,
      ),
      home: AppShell(api: api),
    );
  }
}
