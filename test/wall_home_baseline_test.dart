import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/app/desktop_drawer.dart';
import 'package:gamma_app/features/dashboard/dashboard_page.dart';
import 'package:gamma_app/features/dashboard/desktop_dashboard_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

/// Desktop sidebar destinations are collapsed to icon-only: the accessible
/// name lives on the semantics wrapper, not on a visible `Text`.
Finder _sidebarDestination(String label) => find.descendant(
  of: find.byType(DesktopSidebar),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  ),
);

/// F3-B baseline freeze. These invariants describe the current Home/data flow
/// before Wall Home exists. Any F3-B change that breaks one of these without
/// a deliberate wall-design is a regression.
void main() {
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  group('surface routing baseline', () {
    testWidgets('compact width renders mobile shell with the voice Home', (
      WidgetTester tester,
    ) async {
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
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(WallPanelShell), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'wide desktop width renders desktop shell with the voice Home',
      (WidgetTester tester) async {
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

        expect(find.byType(WallPanelShell), findsNothing);
        // Desktop renders the dedicated desktop dashboard; mobile keeps the
        // voice DashboardPage.
        expect(find.byType(DesktopDashboardPage), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('compact width with persisted wallPanel falls back to mobile', (
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

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('mode switch preserves visited DevicesPage State', (
      WidgetTester tester,
    ) async {
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

      await tester.tap(_sidebarDestination('Dispositivos'));
      await tester.pump();
      await tester.pump();
      final devicesState = tester.state(find.byType(DevicesPage));

      await controller.setMode(AppSurfaceMode.wallPanel);
      await tester.pump();

      expect(find.byType(WallPanelShell), findsOneWidget);
      expect(tester.state(find.byType(DevicesPage)), same(devicesState));

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('counting policy inputs', () {
    test('needsConfiguration uses canonical provisioning semantics', () async {
      final repository = MockDeviceInventoryRepository();
      final snapshot = await repository.load();
      final pending = snapshot.unassigned;

      // Three discovered devices are pending; configured devices are not.
      expect(
        pending.map((device) => device.id).toSet(),
        containsAll(['dev_switch_triple_01', 'dev_bulb_new_01']),
      );
      expect(
        pending.any((device) => device.id == 'dev_plafon_cocina'),
        isFalse,
      );
      // Infrastructure is never part of the user attention set.
      expect(pending.any((device) => device.isGateway), isFalse);
    });

    test('gateways stay out of user devices', () async {
      final repository = MockDeviceInventoryRepository();
      final snapshot = await repository.load();
      expect(snapshot.userDevices.every((device) => !device.isGateway), isTrue);
      expect(snapshot.gateways, isNotEmpty);
    });

    test('physical and controlled areas remain distinct', () async {
      final repository = MockDeviceInventoryRepository();
      final snapshot = await repository.load();
      final switchDevice = snapshot.devices.firstWhere(
        (device) => device.id == 'dev_wall_pasillo',
      );
      expect(switchDevice.physicalAreaId, 'pasillo');
      expect(
        switchDevice.endpoints.map((endpoint) => endpoint.controlledAreaId),
        ['cocina', 'comedor', 'patio'],
      );
      // One physical device, not three.
      expect(
        snapshot.devices.where((device) => device.id == 'dev_wall_pasillo'),
        hasLength(1),
      );
    });

    test('logical control grouping follows controlled_area_id', () async {
      final repository = MockDeviceInventoryRepository();
      final snapshot = await repository.load();
      final salaControls = snapshot.devices
          .where(
            (device) => device.endpoints.any(
              (endpoint) => endpoint.controlledAreaId == 'sala',
            ),
          )
          .expand((device) => device.endpoints)
          .where((endpoint) => endpoint.controlledAreaId == 'sala')
          .toList();
      expect(salaControls.map((endpoint) => endpoint.id), contains('outlet'));
    });
  });

  group('inicio destination identity', () {
    testWidgets('dock labels and Inicio initial selection remain', (
      WidgetTester tester,
    ) async {
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

      final dock = find.byType(FloatingDock);
      expect(dock, findsOneWidget);
      expect(tester.widget<FloatingDock>(dock).currentIndex, 0);
      // Only the active destination renders a visible label now; every
      // destination still exposes its readable name through the dock semantics.
      expect(find.text('Inicio'), findsOneWidget);
      for (final label in [
        'Inicio',
        'Dispositivos',
        'Rutinas',
        'Ajustes',
        'Cámaras',
      ]) {
        expect(
          find.descendant(
            of: dock,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == label,
            ),
          ),
          findsOneWidget,
        );
      }

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
