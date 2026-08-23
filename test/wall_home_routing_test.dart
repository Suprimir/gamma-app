import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/features/dashboard/dashboard_page.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

/// F3-B Phase 2: Inicio must render the dedicated Wall Home only for the
/// effective wall panel surface. Mobile, desktop, and the compact wall
/// fallback keep the existing Home.
void main() {
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  testWidgets('wall gets the dedicated Wall Home at wide width', (
    WidgetTester tester,
  ) async {
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
    expect(find.byType(WallPanelHomePage), findsOneWidget);
    expect(find.byType(DashboardPage), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop at the same width keeps the existing Home', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    useLinuxPlatform();
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(WallPanelHomePage), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile keeps the existing Home', (WidgetTester tester) async {
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
    expect(find.byType(WallPanelHomePage), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('compact wallPanel preference falls back to mobile Home', (
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
    expect(find.byType(WallPanelHomePage), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'mode switch wall to desktop swaps the Home and keeps other state',
    (WidgetTester tester) async {
      MediaKit.ensureInitialized();
      useLinuxPlatform();
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AdaptiveSurfaceModeController();
      await controller.setMode(AppSurfaceMode.wallPanel);
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            surfaceModeController: controller,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(WallPanelHomePage), findsOneWidget);

      await controller.setMode(AppSurfaceMode.desktop);
      await tester.pump();
      expect(find.byType(WallPanelHomePage), findsNothing);
      expect(find.byType(DashboardPage), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('visited DevicesPage State survives wall -> desktop -> wall', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    useLinuxPlatform();
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = AdaptiveSurfaceModeController();
    await controller.setMode(AppSurfaceMode.wallPanel);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          surfaceModeController: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Dispositivos'));
    await tester.pump();
    await tester.pump();
    final devicesState = tester.state(find.byType(DevicesPage));

    await controller.setMode(AppSurfaceMode.desktop);
    await tester.pump();
    await controller.setMode(AppSurfaceMode.wallPanel);
    await tester.pump();

    expect(find.byType(WallPanelShell), findsOneWidget);
    expect(tester.state(find.byType(DevicesPage)), same(devicesState));

    debugDefaultTargetPlatformOverride = null;
  });
}
