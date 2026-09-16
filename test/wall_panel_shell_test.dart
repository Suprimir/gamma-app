import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/app/navigation_destinations.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

/// The wall-only navigation rail replaced the floating bottom dock in the
/// adaptive redesign; the destinations themselves are unchanged.
const _railKey = ValueKey('wall-panel-side-rail');

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
      expect(find.byKey(_railKey), findsOneWidget);
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

    // Each destination row is an AnimatedContainer with a min height; the
    // interactive InkWell inside is inset by the row padding.
    final items = find.descendant(
      of: find.byKey(_railKey),
      matching: find.byType(AnimatedContainer),
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

    // The rail must sit inside a safe area so touch targets stay clear of the
    // panel bezel/insets.
    expect(
      find.ancestor(of: find.byKey(_railKey), matching: find.byType(SafeArea)),
      findsWidgets,
    );
  });
}
