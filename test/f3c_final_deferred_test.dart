import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/features/wall_home/wall_areas_page.dart';
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

/// Canonical inventory fixture: a physical 3-gang switch in Pasillo
/// controlling Sala/Comedor/Patio plus a fan, with area names for all rooms.
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
/// the deterministic proxy for "a repository load happened". `areaCalls`
/// counts area fetches. The same fake serves desktop AND wall content.
class _DeferredDeviceApi extends ApiClient {
  _DeferredDeviceApi() : super(baseUrl: 'http://deferred.test');

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

const _triple = PhysicalDevice(
  id: 'dev_triple_01',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS0013',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'pasillo',
  endpoints: [
    DeviceEndpoint(
      id: 'relay_1',
      name: 'Canal 1',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'comedor',
      capabilities: {'on_off'},
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'patio',
      capabilities: {'on_off'},
    ),
  ],
);

const _fan = PhysicalDevice(
  id: 'dev_fan_01',
  name: 'Ventilador estudio',
  kind: DeviceKind.outlet,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS011F',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'pasillo',
  endpoints: [
    DeviceEndpoint(
      id: 'outlet',
      name: 'Ventilador',
      kind: DeviceKind.outlet,
      controlledAreaId: 'pasillo',
      capabilities: {'on_off'},
    ),
  ],
);

/// Repository fake for the direct-mount WallAreasPage lifecycle test. Both
/// loads are deferred until something actually calls them; the counters prove
/// the offstage (TickerMode-disabled) page never starts them.
class _DeferredAreasRepo implements DeviceInventoryRepository {
  _DeferredAreasRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const [_triple, _fan]);

  final List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  final List<PhysicalDevice> devices;

  int deviceLoadCalls = 0;
  int areaLoadCalls = 0;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async {
    deviceLoadCalls++;
    return DeviceInventorySnapshot(
      areas: List.unmodifiable(areas),
      devices: List.unmodifiable(devices),
      gateways: const [],
      lastDiscoveryLabel: '',
    );
  }

  @override
  Future<DeviceInventorySnapshot> discover() async {
    deviceLoadCalls++;
    return load();
  }

  @override
  Future<List<HomeArea>> listAreas() async {
    areaLoadCalls++;
    return List.unmodifiable(areas);
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignPhysicalArea(String deviceId, String? areaId) =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) => throw UnimplementedError();

  @override
  Future<HomeArea> createArea(String name, {List<String> aliases = const []}) =>
      throw UnimplementedError();

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteArea(String areaId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}

/// Thin wrapper so the Areas lifecycle test can flip TickerMode without
/// recreating the WallAreasPage State.
class _TickerToggle extends StatelessWidget {
  const _TickerToggle({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TickerMode(enabled: enabled, child: child);
  }
}

/// Canonical AppShell harness: explicit surface mode, linux platform, real
/// AppShell routing through the five destinations.
Future<AdaptiveSurfaceModeController> _pumpShellDeferred(
  WidgetTester tester,
  _DeferredDeviceApi api,
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
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  // Bounded settle: desktop/mobile mount DashboardPage (voice loop), whose
  // media streams never idle; pumpAndSettle would spin until its timeout.
  Future<void> settleDeferred(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  // Taps a top-level destination through whichever shell is mounted.
  Future<void> tapDeferred(WidgetTester tester, String label) async {
    final dockLabel = find.descendant(
      of: find.byType(FloatingDock),
      matching: find.text(label),
    );
    if (dockLabel.evaluate().isNotEmpty) {
      await tester.tap(dockLabel);
    } else {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(label),
        ),
      );
    }
    await settleDeferred(tester);
  }

  testWidgets(
    'F3C-OFFSTAGE-NULL-01 visited devices offstage wall switch does not crash or load',
    (tester) async {
      useLinuxPlatform();
      final api = _DeferredDeviceApi();
      final surface = await _pumpShellDeferred(
        tester,
        api,
        AppSurfaceMode.desktop,
      );

      // Dispositivos visited once on desktop: DevicesPage loads its controller.
      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 1);

      // Return to Inicio: Dispositivos stays mounted, now offstage.
      await tapDeferred(tester, 'Inicio');

      // Baseline for the surface switch: only composition may add loads.
      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);

      // RED on HEAD: the offstage WallDevicesPage reaches `snapshot!` with a
      // null snapshot and throws a null-check TypeError during build.
      expect(tester.takeException(), isNull);

      // Home is the ACTIVE destination on wall, so WallPanelHomePage performs
      // its single active load here; the offstage Devices adds 0.
      expect(api.inventoryLoadCalls, 1);
      expect(find.byType(WallPanelShell), findsOneWidget);

      // Activation of Dispositivos loads the wall Devices exactly once.
      final beforeDevices = api.inventoryLoadCalls;
      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls - beforeDevices, 1);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'F3C-OFFSTAGE-NULL-02 activation after offstage creation loads exactly once',
    (tester) async {
      useLinuxPlatform();
      final api = _DeferredDeviceApi();
      final surface = await _pumpShellDeferred(
        tester,
        api,
        AppSurfaceMode.desktop,
      );

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 1);
      await tapDeferred(tester, 'Inicio');

      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);

      // RED on HEAD: the offstage wall Devices null-dereferences on build.
      expect(tester.takeException(), isNull);
      expect(api.inventoryLoadCalls, 1);

      // Activation loads the preserved offstage wall Devices exactly once.
      final before = api.inventoryLoadCalls;
      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls - before, 1);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Tap-away/tap-back keeps the loaded controller alive offstage: +0 more.
      final frozen = api.inventoryLoadCalls;
      await tapDeferred(tester, 'Inicio');
      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, frozen);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'F3C-OFFSTAGE-NO-DUPLICATE rebuilds and resize do not add loads after activation',
    (tester) async {
      useLinuxPlatform();
      final api = _DeferredDeviceApi();
      final surface = await _pumpShellDeferred(
        tester,
        api,
        AppSurfaceMode.desktop,
      );

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 1);
      await tapDeferred(tester, 'Inicio');

      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);

      // RED on HEAD: the offstage wall Devices null-dereferences on build.
      expect(tester.takeException(), isNull);
      expect(api.inventoryLoadCalls, 1);

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 2);

      // Bare rebuilds add no loads.
      final frozen = api.inventoryLoadCalls;
      await settleDeferred(tester);
      await settleDeferred(tester);
      expect(api.inventoryLoadCalls, frozen);

      // Pure geometry changes (still a non-compact wall panel) add no loads.
      await tester.binding.setSurfaceSize(const Size(900, 900));
      await settleDeferred(tester);
      await settleDeferred(tester);
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await settleDeferred(tester);
      await settleDeferred(tester);
      expect(api.inventoryLoadCalls, frozen);
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'F3C-OFFSTAGE-ROUNDTRIP desktop->wall->desktop->wall keeps canonical state and no duplicate inactive loads',
    (tester) async {
      useLinuxPlatform();
      final api = _DeferredDeviceApi();
      final surface = await _pumpShellDeferred(
        tester,
        api,
        AppSurfaceMode.desktop,
      );

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 1);
      await tapDeferred(tester, 'Inicio');

      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);

      // RED on HEAD: the offstage wall Devices null-dereferences on build.
      expect(tester.takeException(), isNull);
      expect(api.inventoryLoadCalls, 1);

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 2);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );

      // Back to desktop: both controllers are already loaded, no new fetch.
      await surface.setMode(AppSurfaceMode.desktop);
      await settleDeferred(tester);
      await settleDeferred(tester);
      expect(api.inventoryLoadCalls, 2);
      expect(tester.takeException(), isNull);

      // Second wall switch with Dispositivos ACTIVE: the fresh wall Devices
      // performs its single bounded load (1); the offstage Home adds 0.
      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);
      expect(api.inventoryLoadCalls, 1);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'F3C-WALL-AREAS-DEFERRED-01 wall areas offstage creation does not crash',
    (tester) async {
      // Direct-mount scope: WallAreasPage is only reached via Navigator.push
      // from WallDevicesPage, so production never caches it offstage through
      // LazyPageHost. The lifecycle still must not null-dereference when the
      // page is created under a disabled TickerMode.
      final repo = _DeferredAreasRepo();
      final api = ApiClient(baseUrl: 'http://deferred.test');

      // Created offstage: TickerMode disabled -> no load starts. RED on HEAD:
      // build falls through to `areas!` with a null list and throws.
      await tester.pumpWidget(
        MaterialApp(
          home: _TickerToggle(
            enabled: false,
            child: WallAreasPage(api: api, repository: repo),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(repo.areaLoadCalls, 0);
      expect(repo.deviceLoadCalls, 0);

      // Activation (TickerMode enabled) starts exactly one areas + devices load.
      await tester.pumpWidget(
        MaterialApp(
          home: _TickerToggle(
            enabled: true,
            child: WallAreasPage(api: api, repository: repo),
          ),
        ),
      );
      await tester.pump();
      expect(repo.areaLoadCalls, 1);
      expect(repo.deviceLoadCalls, 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('wall-area-sala')), findsOneWidget);
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
