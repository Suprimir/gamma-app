import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';

void main() {
  testWidgets(
    'F3A-M01: mobile shell renders five destinations and hosts the page slot',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileShell(
              destinations: appDestinations,
              currentIndex: 0,
              onSelected: (_) {},
              page: const Text('page-area'),
            ),
          ),
        ),
      );

      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(FloatingDock), findsOneWidget);
      expect(find.text('page-area'), findsOneWidget);
    },
  );

  testWidgets(
    'F3A-M02: tapping a destination label invokes onSelected with its index',
    (WidgetTester tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileShell(
              destinations: appDestinations,
              currentIndex: 0,
              onSelected: (i) => selected = i,
              page: const Text('page-area'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Rutinas'));
      await tester.pump();
      expect(selected, 2);
    },
  );
}
