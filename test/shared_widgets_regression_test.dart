import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/ui/shared_widgets.dart';

/// Regression: ToolButton/HeaderRow must render from ANY host without a
/// Scaffold/Material ancestor. The release build crashed with
/// "No Material widget found" because InkWell required a Material ancestor
/// and the host layout did not provide one inside the LookupBoundary.
void main() {
  testWidgets('ToolButton renders without a Material ancestor', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolButton(
            icon: Icons.refresh,
            label: 'Actualizar',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('Actualizar'), findsOneWidget);
    await tester.tap(find.text('Actualizar'));
    expect(taps, 1);
  });

  testWidgets('HeaderRow renders inside a plain host without overflow', (
    tester,
  ) async {
    // Host that does NOT provide a Scaffold around the header: the previous
    // crash happened on such a path (bare Column/ScrollView host).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HeaderRow(title: 'Dispositivos', onRefresh: () {}),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
