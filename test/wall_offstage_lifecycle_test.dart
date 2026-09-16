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
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

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

/// Spec #39 fixture: physical 3-gang switch in Pasillo controlling
/// Sala/Comedor/Patio plus a fan, with area names for all four rooms.
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

const _areaDtos = <Map<String, dynamic>>[
  {'id': 'sala', 'name': 'Sala', 'aliases': <String>[]},
  {'id': 'comedor', 'name': 'Comedor', 'aliases': <String>[]},
  {'id': 'patio', 'name': 'Patio', 'aliases': <String>[]},
  {'id': 'pasillo', 'name': 'Pasillo', 'aliases': <String>[]},
];

/// Fakes the full DevicePlatform HTTP contract the production AppShell
/// repository needs. `inventoryLoadCalls` counts device-inventory fetches —
/// the deterministic proxy for "a repository load happened". The same fake
/// serves desktop AND wall content, so the counter reflects the composition.
class _OffstageDeviceApi extends ApiClient {
  _OffstageDeviceApi() : super(baseUrl: 'http://offstage.test');

  int inventoryLoadCalls = 0;
  int areaCalls = 0;

  List<Map<String, dynamic>> inventory = [
    for (final device in _inventoryDevices) Map<String, dynamic>.of(device),
  ];

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    inventoryLoadCalls++;
    return {
      'devices': [
        for (final device in inventory) Map<String, dynamic>.of(device),
      ],
    };
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
    return [for (final area in _areaDtos) area];
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
  Future<Map<String, dynamic>> renameDevice(
    String deviceId,
    String? userName,
  ) async {
    final index = inventory.indexWhere((d) => d['device_id'] == deviceId);
    final normalized = userName?.trim().replaceAll(RegExp(r'\s+'), ' ');
    final updated = Map<String, dynamic>.of(inventory[index])
      ..['user_name'] = normalized;
    inventory[index] = updated;
    return updated;
  }

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

/// Canonical AppShell harness: explicit surface mode, linux platform, real
/// AppShell routing through the five destinations.
Future<AdaptiveSurfaceModeController> _pumpShell(
  WidgetTester tester,
  _OffstageDeviceApi api,
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

/// Locates a top-level destination on whichever shell is mounted. The mobile
/// dock only renders a visible `Text` for the active destination and the
/// desktop sidebar is icon-only, so both expose the name on a semantics
/// wrapper; the wall rail still renders every label.
Finder _destination(String label) {
  if (find.byType(FloatingDock).evaluate().isNotEmpty) {
    return find.descendant(
      of: find.byType(FloatingDock),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    );
  }
  if (find.byType(WallPanelShell).evaluate().isNotEmpty) {
    return find.descendant(
      of: find.byKey(const ValueKey('wall-panel-side-rail')),
      matching: find.text(label),
    );
  }
  return find.descendant(
    of: find.byType(DesktopSidebar),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
}

void main() {
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  // Bounded settle: desktop/mobile mount DashboardPage (voice loop), whose
  // media streams never idle; pumpAndSettle would spin until its timeout.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  // Taps a top-level destination through whichever shell is mounted.
  Future<void> tapDestination(WidgetTester tester, String label) async {
    await tester.tap(_destination(label));
    await settle(tester);
  }

  testWidgets('wall switch does not fetch offstage home', (tester) async {
    useLinuxPlatform();
    final api = _OffstageDeviceApi();
    final surface = await _pumpShell(tester, api, AppSurfaceMode.desktop);

    // The desktop Home fetches the canonical inventory for its dashboard;
    // Devices adds one controller load plus its bulk state sweep reload.
    await tapDestination(tester, 'Inicio');
    expect(api.inventoryLoadCalls, 1);
    await tapDestination(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, 3);

    // Baseline for the switch: only composition may add loads from here.
    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settle(tester);
    await settle(tester);

    // Only the active WallDevicesPage loads (its own load plus one-shot bulk
    // sweep). The offstage Home must NOT rebuild into WallPanelHomePage and
    // fetch.
    expect(api.inventoryLoadCalls, 2);
    expect(find.byType(WallPanelShell), findsOneWidget);

    // Home becomes active now: the Wall Home performs its FIRST load HERE.
    final beforeHome = api.inventoryLoadCalls;
    await tapDestination(tester, 'Inicio');
    expect(api.inventoryLoadCalls - beforeHome, 1);
    expect(find.byType(WallPanelHomePage), findsOneWidget);
    expect(find.text('Mi casa'), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-sala')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('active wall devices loads once', (tester) async {
    useLinuxPlatform();
    final api = _OffstageDeviceApi();
    final surface = await _pumpShell(tester, api, AppSurfaceMode.desktop);

    await tapDestination(tester, 'Inicio');
    await tapDestination(tester, 'Dispositivos');
    // Desktop Home load + one Devices controller load + its bulk sweep.
    expect(api.inventoryLoadCalls, 3);

    // Baseline for the switch.
    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settle(tester);
    await settle(tester);

    // Only the active WallDevicesPage loads (load + bulk sweep).
    expect(api.inventoryLoadCalls, 2);
    expect(find.byType(WallDevicesPage), findsOneWidget);

    // Back to desktop adds no inventory load (both controllers loaded).
    await surface.setMode(AppSurfaceMode.desktop);
    await settle(tester);
    await settle(tester);
    expect(api.inventoryLoadCalls, 2);

    // A second wall switch adds the same bounded controller load (never a
    // second, independently-owned controller).
    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settle(tester);
    await settle(tester);
    expect(api.inventoryLoadCalls, 2);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wall home loads when it becomes active', (tester) async {
    useLinuxPlatform();
    final api = _OffstageDeviceApi();
    final surface = await _pumpShell(tester, api, AppSurfaceMode.desktop);

    // Desktop Home load, then Devices active (controller load + bulk sweep).
    await tapDestination(tester, 'Inicio');
    expect(api.inventoryLoadCalls, 1);
    await tapDestination(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, 3);

    // Baseline for the switch.
    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settle(tester);
    await settle(tester);

    // The switch loads only the active wall Devices (load + bulk sweep); the
    // offstage Home adds nothing.
    expect(api.inventoryLoadCalls, 2);

    // Activating Home triggers the Wall Home's first load (+1, not consumed
    // offstage at the switch).
    final beforeHome = api.inventoryLoadCalls;
    await tapDestination(tester, 'Inicio');
    await settle(tester);
    expect(api.inventoryLoadCalls - beforeHome, 1);

    // The Wall Home projection renders canonical areas, never legacy ones.
    expect(find.byType(WallPanelHomePage), findsOneWidget);
    expect(find.text('Mi casa'), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-sala')), findsOneWidget);
    expect(find.text('Cocina'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('resize alone never fetches inventory', (tester) async {
    useLinuxPlatform();
    final api = _OffstageDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.desktop);

    await tapDestination(tester, 'Dispositivos');
    // Desktop Home load + one Devices controller load + its bulk sweep.
    expect(api.inventoryLoadCalls, 3);

    // Baseline: a pure geometry change must not re-fetch inventory.
    api.inventoryLoadCalls = 0;
    await tester.binding.setSurfaceSize(const Size(700, 900));
    await settle(tester);
    await settle(tester);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await settle(tester);
    await settle(tester);

    expect(api.inventoryLoadCalls, 0);

    debugDefaultTargetPlatformOverride = null;
  });
}
