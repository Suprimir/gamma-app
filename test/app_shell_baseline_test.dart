import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/app/floating_dock.dart';

/// Baseline freeze for the mobile AppShell/FloatingDock behavior before the
/// F3-A adaptive shell refactor. Any change that alters these invariants
/// without a deliberate adaptive-shell design is a regression.
void main() {
  testWidgets('app shell freezes the five mobile destinations', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();

    // The five canonical destinations render with visible labels.
    for (final label in [
      'Inicio',
      'Dispositivos',
      'Rutinas',
      'Ajustes',
      'Cámaras',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // The floating dock is the primary navigation and sits at the bottom.
    final dock = find.byType(FloatingDock);
    expect(dock, findsOneWidget);
    final dockRect = tester.getRect(dock);
    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
    expect(dockRect.bottom, lessThanOrEqualTo(screenHeight));

    // Inicio is the initial selection.
    expect(tester.widget<FloatingDock>(dock).currentIndex, 0);
  });
}
