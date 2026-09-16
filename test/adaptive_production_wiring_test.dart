import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/app/desktop_drawer.dart';
import 'package:gamma_app/features/dashboard/desktop_dashboard_page.dart';
import 'package:gamma_app/features/devices/desktop_device_detail_pane.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/features/routines/routines_page.dart';
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
/// DevicesPage repository needs. `loadCalls` counts device-inventory fetches;
/// `areaCalls` counts /api/v1/areas fetches. The legacy catalog reports a
/// non-empty `locations` list so tests can prove the canonical areas stay
/// authoritative (no legacy fallback). `renameDevice` normalizes the name and
/// persists it into the mutable inventory, so every fresh repository load
/// (e.g. the wall surface's own controller) observes the mutation.
class _ProdFinalDeviceApi extends ApiClient {
  _ProdFinalDeviceApi() : super(baseUrl: 'http://final.test');

  int loadCalls = 0;
  int areaCalls = 0;

  List<Map<String, dynamic>> inventory = [
    for (final device in _inventoryDevices) Map<String, dynamic>.of(device),
  ];

  List<Map<String, dynamic>> areaDtos = [for (final area in _areaDtos) area];

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    loadCalls++;
    return {
      'devices': [
        for (final device in inventory) Map<String, dynamic>.of(device),
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> catalog() async => {
    'locations': const [
      {'id': 'cocina', 'name': 'Cocina', 'aliases': <String>[]},
    ],
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
    return [for (final area in areaDtos) area];
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
  _ProdFinalDeviceApi api,
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

/// Typed repository-level fixtures for the direct-mount tests.
const _prodTriple = PhysicalDevice(
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

const _prodFan = PhysicalDevice(
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

/// Fake that returns NORMALIZED canonical DTOs on rename (whitespace-collapsed)
/// so convergence can only come from honoring the returned device, never from
/// replaying the request. `failRename` throws a 422 with a Spanish detail.
class _ProdFakeRepo implements DeviceInventoryRepository {
  _ProdFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;

  int loadCalls = 0;
  final renamedDevices = <(String, String?)>[];
  bool failRename = false;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCalls++;
    return _snapshot();
  }

  @override
  Future<DeviceInventorySnapshot> discover() async {
    loadCalls++;
    return _snapshot();
  }

  DeviceInventorySnapshot _snapshot() => DeviceInventorySnapshot(
    areas: List.unmodifiable(areas),
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  String? _normalize(String? name) {
    if (name == null) return null;
    final collapsed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.isEmpty ? null : collapsed;
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    renamedDevices.add((deviceId, userName));
    if (failRename) throw ApiException(422, {'detail': 'no se pudo renombrar'});
    final index = _indexOf(deviceId);
    final updated = devices[index].copyWith(userName: _normalize(userName));
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(userName: _normalize(userName))
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    final index = _indexOf(deviceId);
    final updated = devices[index].copyWith(physicalAreaId: areaId);
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(controlledAreaId: areaId)
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(semanticRole: role)
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  int _indexOf(String deviceId) =>
      devices.indexWhere((device) => device.id == deviceId);

  @override
  Future<List<HomeArea>> listAreas() async => List.unmodifiable(areas);

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteArea(String areaId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}

/// Direct-mount desktop master/detail workspace (no shell).
Future<AdaptiveFeatureController> pumpDesktop(
  WidgetTester tester,
  DeviceInventoryRepository repo, {
  Size size = const Size(1440, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = AdaptiveFeatureController(repo)..loadDevices();
  await tester.pumpWidget(
    MaterialApp(
      home: AppAdaptiveScope(
        windowClass: AppWindowClass.expanded,
        effectiveSurface: EffectiveAppSurface.desktop,
        controller: AdaptiveSurfaceModeController(),
        child: Scaffold(body: DesktopDevicesPage(controller: controller)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

/// Direct-mount wall devices list (no shell).
Future<void> pumpWall(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WallDevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  // Controles is the wall default; the card list/detail tests need the
  // Dispositivos view.
  await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
  await tester.pumpAndSettle();
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

  // Taps a top-level destination through whichever shell is mounted.
  Future<void> tapDestination(WidgetTester tester, String label) async {
    await tester.tap(_destination(label));
    await settle(tester);
  }

  testWidgets('desktop reselect never shows stale device', (tester) async {
    final repo = _ProdFakeRepo(devices: const [_prodTriple, _prodFan]);
    final controller = await pumpDesktop(tester, repo);
    final loadsAtStart = repo.loadCalls;
    expect(loadsAtStart, 1);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    await tester.tap(find.byTooltip('Cambiar nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz   Sala',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repo.renamedDevices, contains(('dev_triple_01', 'Luz   Sala')));
    final converged = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    expect(converged.userName, 'Luz Sala');

    // Reselect fan then triple: the detail must read the canonical value,
    // never the stale provider name.
    controller.selectDevice('dev_fan_01');
    await tester.pumpAndSettle();
    controller.selectDevice('dev_triple_01');
    await tester.pumpAndSettle();
    expect(
      controller.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .userName,
      'Luz Sala',
    );
    expect(
      find.descendant(
        of: find.byType(DesktopDeviceDetailPane),
        matching: find.text('Luz Sala'),
      ),
      findsOneWidget,
    );

    // No extra load during the whole flow: initial 1, rename 0, reselect 0.
    expect(repo.loadCalls, loadsAtStart);
  });

  testWidgets('desktop -> wall -> desktop keeps mutated selection', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _ProdFinalDeviceApi();
    final surface = await _pumpShell(tester, api, AppSurfaceMode.desktop);
    // The desktop Home is the DashboardPage replacement now and fetches the
    // canonical inventory for its own panels.
    expect(api.loadCalls, 1);

    await tapDestination(tester, 'Dispositivos');
    // One fresh controller load plus its one-shot bulk state sweep reload.
    expect(api.loadCalls, 3);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await settle(tester);
    await settle(tester);
    expect(
      tester
          .widget<DesktopDevicesPage>(find.byType(DesktopDevicesPage))
          .controller
          .selectedDeviceId,
      'dev_triple_01',
    );

    await tester.tap(find.byTooltip('Cambiar nombre'));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz   Sala',
    );
    await settle(tester);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    await settle(tester);

    // Rename converged with zero extra loads.
    expect(api.loadCalls, 3);
    final feature = tester
        .widget<DesktopDevicesPage>(find.byType(DesktopDevicesPage))
        .controller;
    expect(feature.selectedDeviceId, 'dev_triple_01');
    expect(
      feature.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .userName,
      'Luz Sala',
    );

    // Wall phase: the wall surface's own controller reloads the repository
    // and must observe the persisted renamed value.
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settle(tester);
    await settle(tester);
    // The active WallDevicesPage owns a fresh controller: one production load
    // plus its bulk state sweep. The offstage home stays inert (its load is
    // deferred until the wall home is activated).
    expect(api.loadCalls, 5);
    expect(find.byType(WallPanelShell), findsOneWidget);
    // Controles is the wall default; the card list is one tap away.
    await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
    await settle(tester);
    final wallCard = find.byKey(const ValueKey('wall-device-dev_triple_01'));
    expect(wallCard, findsOneWidget);
    expect(
      find.descendant(of: wallCard, matching: find.text('Luz Sala')),
      findsOneWidget,
    );

    // Back to desktop: same selection, same converged snapshot, no stale
    // copy anywhere. No new load (both visited controllers stay mounted).
    await surface.setMode(AppSurfaceMode.desktop);
    await settle(tester);
    await settle(tester);
    expect(api.loadCalls, 5);
    expect(find.byType(DesktopShell), findsOneWidget);
    final back = tester
        .widget<DesktopDevicesPage>(find.byType(DesktopDevicesPage))
        .controller;
    expect(back.selectedDeviceId, 'dev_triple_01');
    expect(
      back.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .userName,
      'Luz Sala',
    );
    expect(find.text('Luz Sala'), findsWidgets);
    expect(find.text('Selecciona un dispositivo'), findsNothing);
    expect(find.text('Interruptor triple'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('resize across threshold keeps selection and mutated state', (
    tester,
  ) async {
    final repo = _ProdFakeRepo(devices: const [_prodTriple, _prodFan]);
    final controller = await pumpDesktop(
      tester,
      repo,
      size: const Size(1440, 900),
    );
    expect(repo.loadCalls, 1);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    await tester.tap(find.byTooltip('Cambiar nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz   Sala',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.loadCalls, 1);

    // Narrow fallback: list+push. Resizing alone must not push or fetch.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    expect(repo.loadCalls, 1);
    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Configurar dispositivo'), findsNothing);
    expect(find.text('Luz Sala'), findsOneWidget);

    // Back to wide: master/detail restored with the mutated name.
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(repo.loadCalls, 1);
    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(
      find.descendant(
        of: find.byType(DesktopDeviceDetailPane),
        matching: find.text('Luz Sala'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('lazy host invariants through production shell', (tester) async {
    useLinuxPlatform();
    final api = _ProdFinalDeviceApi();
    final surface = await _pumpShell(tester, api, AppSurfaceMode.desktop);

    // Destination 0 (Inicio) is built at mount; desktop renders Dashboard.
    expect(find.byType(AdaptiveHomePage), findsOneWidget);
    expect(find.byType(DesktopDashboardPage), findsOneWidget);

    await tapDestination(tester, 'Dispositivos');
    expect(find.byType(DevicesPage), findsOneWidget);
    expect(find.byType(DesktopDevicesPage), findsOneWidget);
    final devicesState = tester.state(find.byType(DevicesPage));

    // An unvisited destination stays unbuilt.
    expect(find.byType(RoutinesPage), findsNothing);

    // Round trip Inicio -> Dispositivos preserves the same State.
    await tapDestination(tester, 'Inicio');
    expect(find.byType(AdaptiveHomePage), findsOneWidget);
    expect(find.byType(DevicesPage), findsNothing);
    await tapDestination(tester, 'Dispositivos');
    expect(find.byType(DevicesPage), findsOneWidget);
    expect(tester.state(find.byType(DevicesPage)), same(devicesState));

    // Surface switch preserves the visited page State (F3-A lifecycle).
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settle(tester);
    expect(find.byType(WallPanelShell), findsOneWidget);
    expect(find.byType(DevicesPage), findsOneWidget);
    expect(tester.state(find.byType(DevicesPage)), same(devicesState));

    await surface.setMode(AppSurfaceMode.desktop);
    await settle(tester);
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(DevicesPage), findsOneWidget);
    expect(tester.state(find.byType(DevicesPage)), same(devicesState));

    // Tapping Rutinas finally creates it.
    await tapDestination(tester, 'Rutinas');
    expect(find.byType(RoutinesPage), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wall home drill-down still works from production shell', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _ProdFinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

    // Wall home is destination 0; the area grid renders canonical areas.
    await tapDestination(tester, 'Inicio');
    expect(find.byType(WallPanelHomePage), findsOneWidget);
    expect(find.text('Mi casa'), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-sala')), findsOneWidget);

    // The legacy catalog location never fabricates an area card.
    expect(find.text('Cocina'), findsNothing);

    final areaCard = find.byKey(const ValueKey('wall-area-sala'));
    await tester.ensureVisible(areaCard);
    await settle(tester);
    await tester.tap(areaCard);
    // The wall surfaces carry a continuous idle animation, so route
    // transitions use bounded pumps instead of pumpAndSettle.
    await settle(tester);
    await settle(tester);

    // The area card opens the wall action menu; 'Ver dispositivos' drills
    // into the wall devices list pre-filtered to that area.
    expect(find.text('Ver dispositivos'), findsOneWidget);
    await tester.tap(find.text('Ver dispositivos'));
    await settle(tester);
    await settle(tester);
    expect(find.byType(WallDevicesPage), findsWidgets);
    expect(find.text('Sala'), findsWidgets);
    expect(find.text('Canal 1'), findsOneWidget);

    // The pushed wall page has no AppBar back button; pop the route directly.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    await settle(tester);
    expect(find.text('Mi casa'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('canonical empty areas stay authoritative (no legacy fallback)', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _ProdFinalDeviceApi()..areaDtos = [];
    await _pumpShell(tester, api, AppSurfaceMode.wallPanel);
    await tapDestination(tester, 'Inicio');

    expect(find.byType(WallPanelHomePage), findsOneWidget);
    expect(find.text('Aún no hay habitaciones configuradas'), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-sala')), findsNothing);
    // The legacy catalog ships a 'Cocina' location; it must never repopulate
    // the canonical areas path.
    expect(find.text('Cocina'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop areas reachable and usable from production', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _ProdFinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.desktop);

    await tapDestination(tester, 'Dispositivos');

    // Areas are managed inline from the master list now: the location picker
    // lists the canonical areas with edit/delete and the add entry.
    expect(find.byKey(const Key('desktop-location-filter')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-location-filter')));
    await settle(tester);
    await settle(tester);

    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Agregar área'), findsOneWidget);

    // Choosing a location closes the dialog and keeps the master list usable.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Todas las ubicaciones'),
      ),
    );
    await settle(tester);
    expect(find.text('Ubicación'), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wall detail failure keeps canonical state', (tester) async {
    final repo = _ProdFakeRepo(devices: const [_prodTriple, _prodFan]);
    await pumpWall(tester, repo);

    await tester.tap(find.byKey(const ValueKey('wall-device-dev_triple_01')));
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);

    repo.failRename = true;
    await tester.tap(find.byTooltip('Cambiar nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz sala',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repo.renamedDevices, contains(('dev_triple_01', 'Luz sala')));
    // The server detail now surfaces inline: the dialog stays open with the
    // typed value preserved for correction, and no false success is shown.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('no se pudo renombrar'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'Luz sala',
    );

    // Canonical state is untouched: the repo device and the visible wall
    // detail keep the old name, never converging to the failed value.
    expect(
      repo.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .userName,
      isNull,
    );
    expect(find.text('Interruptor triple'), findsWidgets);

    // Dismiss the still-open dialog (typed value unsubmitted), then return to
    // the wall list: the card still shows the canonical old name.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('wall-device-dev_triple_01')),
        matching: find.text('Interruptor triple'),
      ),
      findsOneWidget,
    );
  });
}
