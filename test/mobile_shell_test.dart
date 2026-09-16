import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';

/// Locates a dock destination through the semantics wrapper that carries its
/// accessible name; the redesigned dock only renders a visible `Text` for the
/// active destination.
Finder _dockDestination(String label) => find.descendant(
  of: find.byType(FloatingDock),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  ),
);

void main() {
  testWidgets(
    ': mobile shell renders five destinations and hosts the page slot',
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

      // The active destination keeps its visible pill label; every other
      // destination is reachable through the dock's accessible name.
      expect(find.text('Inicio'), findsOneWidget);
      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(_dockDestination(label), findsOneWidget);
      }
      expect(find.byType(FloatingDock), findsOneWidget);
      expect(find.text('page-area'), findsOneWidget);
    },
  );

  testWidgets(
    ': tapping a destination label invokes onSelected with its index',
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

      await tester.tap(_dockDestination('Rutinas'));
      await tester.pump();
      expect(selected, 2);
    },
  );

  testWidgets(
    ': page area extends behind the dock while content keeps its inset',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const pageKey = ValueKey('page-fills-shell');
      late double bottomInset;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileShell(
              destinations: appDestinations,
              currentIndex: 0,
              onSelected: (_) {},
              // Pages consume the injected inset through their root SafeArea;
              // read it back here to pin the contract.
              page: Builder(
                builder: (context) {
                  bottomInset = MediaQuery.paddingOf(context).bottom;
                  return const SizedBox.expand(key: pageKey);
                },
              ),
            ),
          ),
        ),
      );

      // The page paints edge to edge, so its background stays visible behind
      // the transparent dock.
      expect(tester.getRect(find.byKey(pageKey)).bottom, 844);
      // Content stays clear of the dock through the injected bottom inset.
      expect(bottomInset, greaterThanOrEqualTo(kMobileDockReserve));
    },
  );
}
