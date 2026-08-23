import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/navigation_destinations.dart';

void main() {
  Widget harness({
    required AppWindowClass windowClass,
    required ValueChanged<int> onSelected,
  }) {
    return MaterialApp(
      home: DesktopShell(
        destinations: appDestinations,
        currentIndex: 0,
        onSelected: onSelected,
        windowClass: windowClass,
        page: const Text('workspace'),
      ),
    );
  }

  testWidgets(
    ': expanded desktop shell shows an extended rail, all labels, and the page',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        harness(windowClass: AppWindowClass.expanded, onSelected: (_) {}),
      );

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingDock), findsNothing);
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

  testWidgets(
    ': medium desktop shell keeps the rail, tooltips the icons, and taps select',
    (WidgetTester tester) async {
      int? selected;
      await tester.pumpWidget(
        harness(
          windowClass: AppWindowClass.medium,
          onSelected: (i) => selected = i,
        ),
      );

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(Tooltip), findsNWidgets(5));

      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pump();
      expect(selected, 2);
    },
  );

  testWidgets(': tapping the Cámaras label selects index 4', (
    WidgetTester tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      harness(
        windowClass: AppWindowClass.expanded,
        onSelected: (i) => selected = i,
      ),
    );

    await tester.tap(find.text('Cámaras'));
    await tester.pump();
    expect(selected, 4);
  });

  testWidgets(': rail exposes the current selection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      harness(windowClass: AppWindowClass.large, onSelected: (_) {}),
    );

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 0);
  });
}
