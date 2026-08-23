import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/navigation_destinations.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

void main() {
  Widget harness({required ValueChanged<int> onSelected}) {
    return MaterialApp(
      home: WallPanelShell(
        destinations: appDestinations,
        currentIndex: 0,
        onSelected: onSelected,
        page: const Text('workspace'),
      ),
    );
  }

  testWidgets(
    ': wall panel renders a dock, no rail, all labels, and the page',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness(onSelected: (_) {}));

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(FloatingDock), findsOneWidget);
      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('workspace'), findsOneWidget);
    },
  );

  testWidgets(': every dock destination is at least 64 logical px tall', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(harness(onSelected: (_) {}));

    final items = find.descendant(
      of: find.byType(FloatingDock),
      matching: find.byType(InkWell),
    );
    expect(items, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      expect(tester.getSize(items.at(i)).height, greaterThanOrEqualTo(64));
    }
  });

  testWidgets(': tapping a destination invokes onSelected with its index', (
    WidgetTester tester,
  ) async {
    int? selected;
    await tester.pumpWidget(harness(onSelected: (i) => selected = i));

    await tester.tap(find.text('Rutinas'));
    await tester.pump();
    expect(selected, 2);
  });

  testWidgets(': the dock is wrapped in a SafeArea', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(harness(onSelected: (_) {}));

    expect(
      find.descendant(
        of: find.byType(FloatingDock),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
    );
  });
}
