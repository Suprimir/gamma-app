import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/main.dart';

/// Locates a mobile dock destination through the semantics wrapper that carries
/// its accessible name; the redesigned dock only renders a visible `Text` for
/// the active destination.
Finder _dockDestination(String label) => find.descendant(
  of: find.byType(FloatingDock),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  ),
);

void main() {
  testWidgets('app shell shows the navigation destinations', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    await tester.pumpWidget(
      GammaApp(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
    );
    await tester.pump();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Módulos'), findsNothing);
    for (final label in ['Dispositivos', 'Cámaras', 'Rutinas', 'Ajustes']) {
      expect(_dockDestination(label), findsOneWidget);
    }

    expect(find.text('G'), findsOneWidget);

    await tester.tap(_dockDestination('Cámaras'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
