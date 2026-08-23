import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/main.dart';

/// Regression: the app UI uses explicit light design tokens (AppColors), so
/// the theme must force Brightness.light even when the device is in dark
/// mode. Without it, `ColorScheme.fromSeed` follows the system brightness
/// and uncolored Text/Icon widgets inherit a dark scheme — reported as
/// "red letters on a weird black background" on the Devices/API screens.
void main() {
  testWidgets('GammaApp theme is always Brightness.light', (tester) async {
    MediaKit.ensureInitialized();
    await tester.pumpWidget(
      GammaApp(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
    );
    await tester.pump();

    final context = tester.element(find.text('Inicio'));
    final theme = Theme.of(context);
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
  });
}
