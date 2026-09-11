import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/app/desktop_drawer.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';
import 'package:gamma_app/data/api_client.dart';

void main() {
  Widget harness({
    required AppWindowClass windowClass,
    required ValueChanged<int> onSelected,
    int currentIndex = 0,
  }) {
    return MaterialApp(
      home: DesktopShell(
        destinations: appDestinations,
        currentIndex: currentIndex,
        onSelected: onSelected,
        windowClass: windowClass,
        api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
        page: const Text('workspace'),
      ),
    );
  }

  testWidgets(
    ': expanded desktop shell stays icon-only with tooltips and the page',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(windowClass: AppWindowClass.expanded, onSelected: (_) {}),
      );

      expect(find.byType(DesktopSidebar), findsOneWidget);
      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DesktopSidebar),
            matching: find.text(label),
          ),
          findsNothing,
        );
      }
      expect(find.text('workspace'), findsOneWidget);

      final sidebar = tester.getSize(find.byType(DesktopSidebar));
      expect(sidebar.width, DesktopSidebar.kCollapsedWidth);
    },
  );

  testWidgets(
    ': medium desktop shell starts collapsed with icon tooltips, taps select',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int? selected;
      await tester.pumpWidget(
        harness(
          windowClass: AppWindowClass.medium,
          onSelected: (i) => selected = i,
        ),
      );

      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(
        tester.getSize(find.byType(DesktopSidebar)).width,
        DesktopSidebar.kCollapsedWidth,
      );
      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
      }

      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pump();
      expect(selected, 2);
    },
  );

  testWidgets(': no hamburger, sidebar stays collapsed icon-only', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(windowClass: AppWindowClass.expanded, onSelected: (_) {}),
    );

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.kCollapsedWidth,
    );
    expect(find.byTooltip('Dispositivos'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('Dispositivos'),
      ),
      findsNothing,
    );
  });

  testWidgets(': tapping the Cámaras icon selects index 4', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? selected;
    await tester.pumpWidget(
      harness(
        windowClass: AppWindowClass.expanded,
        onSelected: (i) => selected = i,
      ),
    );

    await tester.tap(find.byIcon(Icons.videocam_outlined));
    await tester.pump();
    expect(selected, 4);
  });

  testWidgets(': tapping Ajustes icon selects index 3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? selected;
    await tester.pumpWidget(
      harness(
        windowClass: AppWindowClass.expanded,
        onSelected: (i) => selected = i,
      ),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(selected, 3);
  });

  testWidgets(': tapping Rutinas icon selects index 2', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? selected;
    await tester.pumpWidget(
      harness(
        windowClass: AppWindowClass.expanded,
        onSelected: (i) => selected = i,
      ),
    );

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pump();
    expect(selected, 2);
  });

  testWidgets(': sidebar exposes the current selection', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        windowClass: AppWindowClass.large,
        onSelected: (_) {},
        currentIndex: 1,
      ),
    );

    final sidebar = tester.widget<DesktopSidebar>(find.byType(DesktopSidebar));
    expect(sidebar.selectedIndex, 1);
  });
}
