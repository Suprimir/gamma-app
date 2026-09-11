import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/app/desktop_drawer.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/features/settings/settings_page.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

class _FakeSettingsApi extends ApiClient {
  _FakeSettingsApi() : super(baseUrl: 'http://test');

  @override
  Future<Map<String, dynamic>> ttsSettings() async => {'edge_voice': ''};

  @override
  Future<Map<String, dynamic>> ttsVoices() async => {'edge': []};

  @override
  Future<Map<String, dynamic>> spotifySettings() async => {
    'authenticated': false,
    'client_id_configured': false,
  };

  @override
  Future<List<Map<String, dynamic>>> modules() async => [];

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  // Auto-selection of desktop for wide widths depends on a desktop platform.
  // The override must be reset inside the test body (the framework checks the
  // foundation debug variables before running tearDown callbacks). When a test
  // fails early, the invariant check is skipped, so an early failure cannot
  // produce a spurious "debug variable changed" error on top.
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  testWidgets(
    ': live resize compact to desktop keeps selection and page state',
    (WidgetTester tester) async {
      MediaKit.ensureInitialized();
      useLinuxPlatform();
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);

      await tester.tap(find.text('Dispositivos'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(DevicesPage), findsOneWidget);
      final devicesState = tester.state(find.byType(DevicesPage));

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pump();

      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(MobileShell), findsNothing);
      expect(find.byType(FloatingDock), findsNothing);
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(
        tester
            .widget<DesktopSidebar>(find.byType(DesktopSidebar))
            .selectedIndex,
        1,
      );
      expect(tester.state(find.byType(DevicesPage)), same(devicesState));

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    ': resizing back to compact restores mobile with the same state',
    (WidgetTester tester) async {
      MediaKit.ensureInitialized();
      useLinuxPlatform();
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Dispositivos'));
      await tester.pump();
      await tester.pump();
      final devicesState = tester.state(find.byType(DevicesPage));

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pump();
      expect(find.byType(DesktopShell), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pump();

      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);
      expect(
        tester.widget<FloatingDock>(find.byType(FloatingDock)).currentIndex,
        1,
      );
      expect(tester.state(find.byType(DevicesPage)), same(devicesState));

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    ': mode switch to wallPanel and back at desktop keeps page state',
    (WidgetTester tester) async {
      MediaKit.ensureInitialized();
      useLinuxPlatform();
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AdaptiveSurfaceModeController();
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            surfaceModeController: controller,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DesktopShell), findsOneWidget);

      await tester.tap(find.text('Dispositivos'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(DevicesPage), findsOneWidget);
      final devicesState = tester.state(find.byType(DevicesPage));

      await controller.setMode(AppSurfaceMode.wallPanel);
      await tester.pump();

      expect(find.byType(WallPanelShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);
      expect(
        tester.widget<FloatingDock>(find.byType(FloatingDock)).currentIndex,
        1,
      );
      expect(tester.state(find.byType(DevicesPage)), same(devicesState));

      await controller.setMode(AppSurfaceMode.auto);
      await tester.pump();

      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(WallPanelShell), findsNothing);
      expect(tester.state(find.byType(DevicesPage)), same(devicesState));

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    ': persisted wallPanel at root renders the wall panel without interaction',
    (WidgetTester tester) async {
      MediaKit.ensureInitialized();
      useLinuxPlatform();
      SharedPreferences.setMockInitialValues({
        'adaptive_surface_mode': 'wallPanel',
      });
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(WallPanelShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);
      expect(find.byType(MobileShell), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(': compact width with persisted wallPanel falls back to mobile', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    useLinuxPlatform();
    SharedPreferences.setMockInitialValues({
      'adaptive_surface_mode': 'wallPanel',
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(WallPanelShell), findsNothing);

    // The preference itself stays persisted as wallPanel.
    final scope = tester.widget<AppAdaptiveScope>(
      find.byType(AppAdaptiveScope),
    );
    expect(scope.controller.value, AppSurfaceMode.wallPanel);
    expect(scope.effectiveSurface, EffectiveAppSurface.mobile);
    expect(scope.windowClass.isCompact, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(': scope exposes stable presentation facts', (tester) async {
    final controller = AdaptiveSurfaceModeController();
    await controller.load();

    AppWindowClass? windowClass;
    EffectiveAppSurface? effectiveSurface;
    bool? isCompact;
    bool? isDesktop;
    bool? isWallPanel;

    await tester.pumpWidget(
      MaterialApp(
        home: AppAdaptiveScope(
          windowClass: AppWindowClass.large,
          effectiveSurface: EffectiveAppSurface.desktop,
          controller: controller,
          child: Builder(
            builder: (context) {
              final scope = AppAdaptiveScope.of(context);
              windowClass = scope.windowClass;
              effectiveSurface = scope.effectiveSurface;
              isCompact = scope.isCompact;
              isDesktop = scope.isDesktopSurface;
              isWallPanel = scope.isWallPanel;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(windowClass, AppWindowClass.large);
    expect(effectiveSurface, EffectiveAppSurface.desktop);
    expect(isCompact, isFalse);
    expect(isDesktop, isTrue);
    expect(isWallPanel, isFalse);
  });

  testWidgets(': SettingsPage inside the scope uses the scope controller', (
    tester,
  ) async {
    final controller = AdaptiveSurfaceModeController();
    await controller.setMode(AppSurfaceMode.desktop);

    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AppAdaptiveScope(
          windowClass: AppWindowClass.large,
          effectiveSurface: EffectiveAppSurface.desktop,
          controller: controller,
          child: Scaffold(body: SettingsPage(api: _FakeSettingsApi())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final group = find.byType(RadioGroup<AppSurfaceMode>);
    await tester.scrollUntilVisible(
      find.text('Panel de pared'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<RadioGroup<AppSurfaceMode>>(group).groupValue,
      AppSurfaceMode.desktop,
    );

    await controller.setMode(AppSurfaceMode.wallPanel);
    await tester.pump();
    expect(
      tester.widget<RadioGroup<AppSurfaceMode>>(group).groupValue,
      AppSurfaceMode.wallPanel,
    );
  });

  testWidgets(': dock labels survive 1.5x text scaling on mobile', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileShell), findsOneWidget);
    for (final label in [
      'Inicio',
      'Dispositivos',
      'Rutinas',
      'Ajustes',
      'Cámaras',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
