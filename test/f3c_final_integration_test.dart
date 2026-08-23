import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/features/areas/desktop_areas_page.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/features/wall_home/wall_areas_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

const _powerCapability = <String, dynamic>{
  'capability': 'POWER',
  'readable': true,
  'writable': true,
  'range': null,
  'enum_values': null,
  'confidence': 'HIGH',
  'evidence': <String>[],
};

const _relay1 = <String, dynamic>{
  'endpoint_id': 'relay_1',
  'display_name': 'Canal 1',
  'controlled_area_id': 'sala',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relay2 = <String, dynamic>{
  'endpoint_id': 'relay_2',
  'display_name': 'Canal 2',
  'controlled_area_id': 'comedor',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relay3 = <String, dynamic>{
  'endpoint_id': 'relay_3',
  'display_name': 'Canal 3',
  'controlled_area_id': 'patio',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _outletEndpoint = <String, dynamic>{
  'endpoint_id': 'outlet',
  'display_name': 'Ventilador',
  'controlled_area_id': 'pasillo',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _inventoryDevices = <Map<String, dynamic>>[
  {
    'device_id': 'dev_triple_01',
    'provider_id': 'tuya',
    'display_name': 'Interruptor triple',
    'manufacturer': 'MockCo',
    'model': 'TS0013',
    'product_id': null,
    'category': null,
    'physical_area_id': 'pasillo',
    'parent_device_id': null,
    'is_subdevice': false,
    'is_gateway': false,
    'provisioning_state': 'CONFIGURED',
    'enabled': true,
    'device_class': 'switch',
    'device_class_source': 'provider',
    'endpoints': [_relay1, _relay2, _relay3],
  },
  {
    'device_id': 'dev_fan_01',
    'provider_id': 'tuya',
    'display_name': 'Ventilador estudio',
    'manufacturer': 'MockCo',
    'model': 'TS011F',
    'product_id': null,
    'category': null,
    'physical_area_id': 'pasillo',
    'parent_device_id': null,
    'is_subdevice': false,
    'is_gateway': false,
    'provisioning_state': 'CONFIGURED',
    'enabled': true,
    'device_class': 'outlet',
    'device_class_source': 'provider',
    'endpoints': [_outletEndpoint],
  },
];

/// Fakes the full DevicePlatform HTTP contract the AppShell DevicesPage
/// repository needs: canonical inventory + catalog + provider health + areas.
/// `loadCalls` counts device-inventory fetches (the proxy for "a repository
/// load happened"); `areaCalls` counts /api/v1/areas fetches.
class _FinalDeviceApi extends ApiClient {
  _FinalDeviceApi() : super(baseUrl: 'http://final.test');

  int loadCalls = 0;
  int areaCalls = 0;

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    loadCalls++;
    return {'devices': _inventoryDevices};
  }

  @override
  Future<Map<String, dynamic>> catalog() async => {
    'locations': const <Map<String, dynamic>>[],
    'routines': const <Map<String, dynamic>>[],
    'device_count': 0,
    'version': 1,
  };

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async => {
    'tuya': {
      'provider_id': 'tuya',
      'lan_ready': true,
      'cloud_ready': true,
      'status': 'LAN_READY',
      'detail': null,
    },
  };

  @override
  Future<List<Map<String, dynamic>>> areas() async {
    areaCalls++;
    return const [
      {'id': 'sala', 'name': 'Sala', 'aliases': <String>[]},
      {'id': 'comedor', 'name': 'Comedor', 'aliases': <String>[]},
      {'id': 'patio', 'name': 'Patio', 'aliases': <String>[]},
      {'id': 'pasillo', 'name': 'Pasillo', 'aliases': <String>[]},
    ];
  }

  @override
  Future<Map<String, dynamic>> discoverDevices() async {
    return {
      'tuya': {
        'generation': 2,
        'candidates': 2,
        'enriched': 2,
        'new': 0,
        'missing': 0,
      },
    };
  }

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

/// Canonical AppShell harness: explicit surface mode, linux platform, real
/// AppShell routing through the five destinations. The Devices destination is
/// reached only by tapping the shell (dock or rail), like production.
Future<AdaptiveSurfaceModeController> _pumpShell(
  WidgetTester tester,
  _FinalDeviceApi api,
  AppSurfaceMode mode,
) async {
  MediaKit.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AdaptiveSurfaceModeController();
  await controller.load();
  await controller.setMode(mode);
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(api: api, surfaceModeController: controller),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

void main() {
  // Explicit modes win regardless of platform, but the canonical AppShell
  // tests pin linux; keep the invariant: reset the override inside the body.
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  // Bounded settle: desktop/mobile mount DashboardPage (voice loop), whose
  // media streams never idle; pumpAndSettle would spin until its timeout.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> tapDispositivos(WidgetTester tester) async {
    final dockLabel = find.descendant(
      of: find.byType(FloatingDock),
      matching: find.text('Dispositivos'),
    );
    if (dockLabel.evaluate().isNotEmpty) {
      await tester.tap(dockLabel);
    } else {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Dispositivos'),
        ),
      );
    }
    await settle(tester);
  }

  testWidgets(
    'F3C-INTEGRATION-01 wall panel top-level dispositivos opens wall devices',
    (tester) async {
      useLinuxPlatform();
      final api = _FinalDeviceApi();
      await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

      await tapDispositivos(tester);
      await tester.pumpAndSettle();

      // The wall surface must mount the touch-first wall page, never the
      // mobile composition ('ESPACIOS') or the desktop master/detail.
      expect(find.byType(WallDevicesPage), findsOneWidget);
      expect(find.text('ESPACIOS'), findsNothing);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('wall-device-dev_fan_01')),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'F3C-INTEGRATION-02 desktop top-level dispositivos opens desktop master detail',
    (tester) async {
      useLinuxPlatform();
      final api = _FinalDeviceApi();
      await _pumpShell(tester, api, AppSurfaceMode.desktop);

      await tapDispositivos(tester);

      expect(find.byType(DesktopDevicesPage), findsOneWidget);
      expect(find.text('Selecciona un dispositivo'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-device-dev_fan_01')),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'F3C-INTEGRATION-03 mobile top-level dispositivos keeps sequential flow',
    (tester) async {
      useLinuxPlatform();
      final api = _FinalDeviceApi();
      await _pumpShell(tester, api, AppSurfaceMode.mobile);

      await tapDispositivos(tester);

      expect(find.byType(DesktopDevicesPage), findsNothing);
      expect(find.byType(WallDevicesPage), findsNothing);
      expect(find.text('ESPACIOS'), findsOneWidget);
      expect(find.text('INFRAESTRUCTURA'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('F3C-INTEGRATION-04 desktop dispositivos reaches desktop areas', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.desktop);

    await tapDispositivos(tester);

    // Desktop workspace needs a visible Habitaciones entry that navigates
    // to the desktop master/detail Areas workspace.
    expect(find.text('Habitaciones'), findsOneWidget);
    await tester.tap(find.text('Habitaciones'));
    await settle(tester);

    expect(find.byType(DesktopAreasPage), findsOneWidget);
    expect(find.text('Selecciona un área'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('F3C-INTEGRATION-05 wall dispositivos reaches wall areas', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

    await tapDispositivos(tester);
    await tester.pumpAndSettle();

    expect(find.text('Habitaciones'), findsOneWidget);
    await tester.tap(find.text('Habitaciones'));
    await tester.pumpAndSettle();

    expect(find.byType(WallAreasPage), findsOneWidget);
    expect(find.text('Nueva habitación'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'F3C-INTEGRATION-06 wall top-level does not double-fetch inventory',
    (tester) async {
      useLinuxPlatform();
      final api = _FinalDeviceApi();
      await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

      // The wall home (index 0) already fetched once; entering Dispositivos
      // must add exactly ONE repository load. A second, independently-owned
      // controller (DevicesPage + WallDevicesPage) would add two.
      final before = api.loadCalls;
      await tapDispositivos(tester);
      await tester.pumpAndSettle();

      expect(api.loadCalls, before + 1);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
