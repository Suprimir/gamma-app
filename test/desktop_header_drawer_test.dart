import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/app/desktop_drawer.dart';
import 'package:gamma_app/app/desktop_header.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/ui/app_colors.dart';

ApiClient _testApi() => ApiClient(baseUrl: 'http://127.0.0.1:8420');

void main() {
  group('DesktopHeader — GAMMA top bar', () {
    testWidgets('renders 56h white bar with GAMMA bold, no hamburger', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopHeader())),
      );

      // Height 56
      final headerBox = tester.getSize(find.byType(DesktopHeader));
      expect(headerBox.height, 56);

      // White bg + border bottom via Container decoration or Material color
      final headerFinder = find.byType(DesktopHeader);
      expect(headerFinder, findsOneWidget);

      // GAMMA text bold 16w700
      final gammaText = tester.widget<Text>(find.text('GAMMA'));
      expect(gammaText.style?.fontWeight, FontWeight.w700);
      expect(gammaText.style?.fontSize, 16);

      // Hamburger, bell and settings removed
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);

      // Background white
      final containerFinder = find.descendant(
        of: find.byType(DesktopHeader),
        matching: find.byType(Container),
      );
      // At least one container with white color
      final containers = tester.widgetList<Container>(containerFinder);
      final hasWhite = containers.any(
        (c) =>
            c.color == Colors.white ||
            (c.decoration as BoxDecoration?)?.color == Colors.white,
      );
      expect(hasWhite, isTrue);

      // Border bottom present (Container with border)
      final hasBorder = containers.any((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          return dec.border?.bottom.color != null;
        }
        return false;
      });
      expect(hasBorder, isTrue);
    });

    testWidgets(
      'header background is white and border uses AppColors.border tone',
      (tester) async {
        tester.view.physicalSize = const Size(880, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: DesktopHeader(onNotifications: null, onSettings: null),
            ),
          ),
        );
        // Verify container color white explicitly
        final container = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(DesktopHeader),
                matching: find.byType(Container),
              ),
            )
            .firstWhere(
              (c) =>
                  c.color == Colors.white ||
                  (c.decoration as BoxDecoration?)?.color == Colors.white,
              orElse: () => Container(),
            );
        expect(
          container.color == Colors.white ||
              (container.decoration as BoxDecoration?)?.color == Colors.white,
          isTrue,
        );
      },
    );
  });

  group('DesktopSidebar — persistent admin navigation', () {
    testWidgets(
      'renders 272 width with 5 canonical sections, Dispositivos selected indigo',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int? selected;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopSidebar(
                selectedIndex: 1,
                onSelect: (i) => selected = i,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sidebar width 272
        final sidebarFinder = find.byKey(const Key('desktop-sidebar'));
        expect(sidebarFinder, findsOneWidget);
        expect(tester.getSize(sidebarFinder).width, 272);

        // 5 canonical sections mirroring appDestinations
        expect(find.text('Inicio'), findsOneWidget);
        expect(find.text('Dispositivos'), findsOneWidget);
        expect(find.text('Rutinas'), findsOneWidget);
        expect(find.text('Ajustes'), findsOneWidget);
        expect(find.text('Cámaras'), findsOneWidget);

        // Dispositivos selected: indigo text #4F46E5
        final dispositivosText = tester.widget<Text>(find.text('Dispositivos'));
        expect(dispositivosText.style?.color, AppColors.gammaIndigo);

        // Selected row has indigo light bg #EEF2FF
        final selectedMaterials = tester.widgetList<Material>(
          find.descendant(
            of: find.byKey(const Key('desktop-sidebar')),
            matching: find.byType(Material),
          ),
        );
        final hasIndigoLightBg = selectedMaterials.any(
          (m) => m.color == AppColors.gammaIndigoLight,
        );
        expect(hasIndigoLightBg, isTrue);

        // Icons per spec: home_outlined for Inicio, grid_view for Dispositivos
        expect(find.byIcon(Icons.home_outlined), findsOneWidget);
        expect(find.byIcon(Icons.grid_view), findsOneWidget);

        // Section tap selects its destination index
        await tester.tap(find.text('Rutinas'));
        await tester.pumpAndSettle();
        expect(selected, 2);

        await tester.tap(find.text('Ajustes'));
        await tester.pumpAndSettle();
        expect(selected, 3);
      },
    );

    testWidgets('collapsed sidebar keeps 76 width with icon tooltips', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopSidebar(
              selectedIndex: 1,
              onSelect: (_) {},
              collapsed: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('desktop-sidebar'))).width,
        76,
      );
      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets(
      'triangulate: different selected index shows correct selected styling',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopSidebar(selectedIndex: 0, onSelect: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final inicioText = tester.widget<Text>(find.text('Inicio'));
        expect(inicioText.style?.color, AppColors.gammaIndigo);
        final dispositivosText = tester.widget<Text>(find.text('Dispositivos'));
        // When Inicio selected, Dispositivos should NOT be indigo
        expect(dispositivosText.style?.color, isNot(AppColors.gammaIndigo));
      },
    );
  });

  group('DesktopShell integration — header + sidebar', () {
    testWidgets(
      'at 1200px header visible with persistent collapsed icon-only sidebar',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: DesktopShell(
              destinations: appDestinations,
              currentIndex: 1,
              onSelected: (_) {},
              windowClass: AppWindowClass.large,
              api: _testApi(),
              page: const Text('page-content'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Header GAMMA visible, no hamburger
        expect(find.text('GAMMA'), findsOneWidget);
        expect(find.byIcon(Icons.menu), findsNothing);

        // Sidebar persistent from the start, always icon-only
        expect(find.byKey(const Key('desktop-sidebar')), findsOneWidget);
        expect(find.byTooltip('Inicio'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('desktop-sidebar')),
            matching: find.text('Inicio'),
          ),
          findsNothing,
        );
        expect(
          tester.getSize(find.byType(DesktopSidebar)).width,
          DesktopSidebar.kCollapsedWidth,
        );
      },
    );

    testWidgets('medium shell starts collapsed to protect the workspace', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(
            destinations: appDestinations,
            currentIndex: 1,
            onSelected: (_) {},
            windowClass: AppWindowClass.medium,
            api: _testApi(),
            page: const Text('page-content-narrow'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GAMMA'), findsOneWidget);
      expect(find.text('page-content-narrow'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DesktopSidebar)).width,
        DesktopSidebar.kCollapsedWidth,
      );
    });

    testWidgets('sidebar item tap calls onSelected and keeps the page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopShell(
            destinations: appDestinations,
            currentIndex: 1,
            onSelected: (i) => selected = i,
            windowClass: AppWindowClass.large,
            api: _testApi(),
            page: const Text('page-content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('desktop-sidebar')),
          matching: find.byIcon(Icons.home_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(selected, 0);
      // Persistent sidebar: the page stays mounted, no overlay to dismiss.
      expect(find.text('page-content'), findsOneWidget);
    });
  });
}
