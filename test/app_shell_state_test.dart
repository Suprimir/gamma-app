import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/features/dashboard/dashboard_page.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/lazy_page_host.dart';

/// Locates a mobile dock destination through the semantics wrapper that carries
/// its accessible name: the redesigned dock only renders a visible `Text` for
/// the active destination.
Finder _dockDestination(String label) => find.descendant(
  of: find.byType(FloatingDock),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  ),
);

void main() {
  testWidgets(': shell keeps visited pages alive across tab switches', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    // The square test font renders the active 'Dispositivos' pill wider than
    // the dock's fixed cap; a reduced scale keeps the semantics harness free of
    // test-font overflow without touching the production layout.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();

    expect(find.byType(LazyPageHost), findsOneWidget);
    expect(
      tester.widget<LazyPageHost>(find.byType(LazyPageHost)).key,
      isA<GlobalKey>(),
    );
    expect(find.byType(DevicesPage), findsNothing);

    await tester.tap(_dockDestination('Dispositivos'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DevicesPage), findsOneWidget);

    await tester.tap(_dockDestination('Inicio'));
    await tester.pump();
    expect(find.byType(DashboardPage), findsOneWidget);

    await tester.tap(_dockDestination('Dispositivos'));
    await tester.pump();
    expect(find.byType(DevicesPage), findsOneWidget);
  });
}
