import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

import 'fixtures/command_device_fake_repo.dart';

/// F3-C Phase 9: multi-gang correctness across the three adaptive surfaces.
/// A physical device keeps one physical identity, three independent controls,
/// three independent controlled areas, endpoint-scoped role/user_name
/// mutations and a physical-area change that never writes endpoint areas.
void main() {
  testWidgets('model preserves physical vs controlled', (tester) async {
    final repo = _MultiGangFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    // One physical device, never collapsed into per-endpoint devices.
    final snapshot = controller.snapshot!;
    expect(snapshot.devices.where((d) => d.id == 'dev_triple_01').length, 1);
    final device = snapshot.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(device.physicalAreaId, 'pasillo');
    expect(device.endpoints.length, 3);
    expect(device.endpoints.map((e) => e.id).toList(), [
      'relay_1',
      'relay_2',
      'relay_3',
    ]);

    // Three independent controlled areas, all distinct.
    final controlled = device.endpoints.map((e) => e.controlledAreaId).toList();
    expect(controlled, ['sala', 'comedor', 'patio']);
    expect(controlled.toSet().length, 3);

    // The canonical repo model carries the same separation.
    final canonical = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(canonical.endpoints[0].controlledAreaId, 'sala');
    expect(canonical.endpoints[1].controlledAreaId, 'comedor');
    expect(canonical.endpoints[2].controlledAreaId, 'patio');
  });

  testWidgets('mobile endpoint independence', (tester) async {
    final repo = _MultiGangFakeRepo(devices: const [_triple, _fan]);
    await pumpMobileDevices(tester, repo);

    // Sequential mobile flow: area card -> device list -> detail.
    await tester.tap(find.text('Sala'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);
    expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);

    // relay_1 semantic role changes; siblings stay untouched (model).
    await repo.assignEndpointSemanticRole('dev_triple_01', 'relay_1', 'fan');
    await tester.pump();

    expect(repo.roleWrites, [('dev_triple_01', 'relay_1', 'fan')]);
    final updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').semanticRole,
      'fan',
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').semanticRole,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').semanticRole,
      isNull,
    );

    // UI still renders all three independent channels.
    await tester.scrollUntilVisible(
      find.text('Canal 3'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
  });

  testWidgets('desktop endpoint independence via UI', (tester) async {
    final repo = _MultiGangFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // Edit relay_1's semantic role through the real role dropdown.
    final roleLabel = find.text('Qué controla').first;
    final roleColumn = find
        .ancestor(of: roleLabel, matching: find.byType(Column))
        .first;
    final roleDropdown = find
        .descendant(
          of: roleColumn,
          matching: find.byType(DropdownButtonFormField<String?>),
        )
        .first;
    await tester.ensureVisible(roleDropdown);
    await tester.pumpAndSettle();
    await tester.tap(roleDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ventilador').last);
    await tester.pumpAndSettle();

    expect(repo.roleWrites, [('dev_triple_01', 'relay_1', 'fan')]);
    var updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').semanticRole,
      'fan',
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').semanticRole,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').semanticRole,
      isNull,
    );
    expect(controller.selectedDeviceId, 'dev_triple_01');

    // Rename relay_3 through the endpoint rename dialog; siblings keep their
    // user_name.
    final canal3Editor = find
        .ancestor(
          of: find.text('Canal 3'),
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_EndpointEditor',
          ),
        )
        .first;
    await tester.tap(
      find.descendant(
        of: canal3Editor,
        matching: find.byTooltip('Cambiar nombre del canal'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz terraza',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Guardar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.endpointRenames, [('dev_triple_01', 'relay_3', 'Luz terraza')]);
    updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').userName,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').userName,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').userName,
      'Luz terraza',
    );
  });

  testWidgets('wall endpoint independence', (tester) async {
    final repo = _MultiGangFakeRepo(devices: const [_triple, _fan]);
    await pumpWall(tester, repo);
    final controller = _wallController(tester);

    await tester.tap(find.byKey(const ValueKey('wall-device-dev_triple_01')));
    await tester.pumpAndSettle();
    expect(find.text('Controles'), findsOneWidget);

    await repo.assignEndpointSemanticRole('dev_triple_01', 'relay_1', 'fan');
    await controller.loadDevices();
    await tester.pumpAndSettle();

    expect(repo.roleWrites, [('dev_triple_01', 'relay_1', 'fan')]);
    var updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').semanticRole,
      'fan',
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').semanticRole,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').semanticRole,
      isNull,
    );

    // Endpoint rename stays endpoint-scoped on the wall surface too.
    await repo.renameEndpoint('dev_triple_01', 'relay_3', 'Luz patio');
    await controller.loadDevices();
    await tester.pumpAndSettle();

    updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').userName,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').userName,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').userName,
      'Luz patio',
    );

    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
  });

  testWidgets('physical area change never writes endpoint areas', (
    tester,
  ) async {
    final repo = _MultiGangFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    await repo.assignPhysicalArea('dev_triple_01', 'cocina');
    await controller.loadDevices();
    await tester.pumpAndSettle();

    final updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(updated.physicalAreaId, 'cocina');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').controlledAreaId,
      'sala',
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').controlledAreaId,
      'comedor',
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').controlledAreaId,
      'patio',
    );

    // UI keeps showing the three independent channels.
    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
  });

  testWidgets('mobile power toggle issues the canonical command', (
    tester,
  ) async {
    final repo = CommandDeviceFakeRepo(
      devices: const [_commandLight],
      areas: const [HomeArea(id: 'sala', name: 'Sala')],
    );
    await pumpMobileDevicesWide(tester, repo);

    await tester.tap(find.text('Sala'));
    await tester.pumpAndSettle();

    // No confirmed observation: the card is honest, never a fake "Apagado".
    expect(find.text('Sin datos'), findsOneWidget);

    await tester.tap(find.text('Luz sala'));
    await tester.pump();

    expect(repo.powerCalls, [('dev_power_01', 'light', true)]);
    expect(find.text('Luz sala — Encendido'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Encendido'), findsWidgets);
  });

  testWidgets('mobile unknown health with commands powers on', (tester) async {
    final repo = CommandDeviceFakeRepo(
      devices: const [_commandUnknownLight],
      areas: const [HomeArea(id: 'sala', name: 'Sala')],
    );
    await pumpMobileDevicesWide(tester, repo);

    await tester.tap(find.text('Sala'));
    await tester.pumpAndSettle();

    // Health is unvalidated but the device is commandable: honest 'Sin datos',
    // not a dead 'Estado desconocido'.
    expect(find.text('Estado desconocido'), findsNothing);
    expect(find.text('Sin datos'), findsOneWidget);

    await tester.tap(find.text('Luz sin validar'));
    await tester.pump();

    // Unknown power resolves to power-on, never off.
    expect(repo.powerCalls, [('dev_unknown_01', 'light', true)]);
    expect(find.text('Luz sin validar — Encendido'), findsOneWidget);
  });

  testWidgets('mobile unknown health without commands stays unknowable', (
    tester,
  ) async {
    final repo = _MultiGangFakeRepo(devices: const [_legacyUnknownLight]);
    await pumpMobileDevicesWide(tester, repo);

    await tester.tap(find.text('Sala'));
    await tester.pumpAndSettle();

    // Plain fakes keep the exact old behavior: not controllable.
    expect(find.text('Estado desconocido'), findsOneWidget);
    expect(find.text('Sin datos'), findsNothing);

    await tester.tap(find.text('Luz sin validar'));
    await tester.pump();
    expect(find.text('Luz sin validar — Estado desconocido'), findsOneWidget);
  });
}

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
        child: DesktopDevicesPage(controller: controller),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

Future<void> pumpMobileDevices(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}

/// Mobile-area-first pump at 520 dp: the pre-existing home header overflow at
/// 390 dp (known failing `mobile endpoint independence`) is unrelated to the
/// power flow and would fail any test that navigates the grid at that width.
Future<void> pumpMobileDevicesWide(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(520, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}

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
}

AdaptiveFeatureController _wallController(WidgetTester tester) {
  final builder = tester.widget<ListenableBuilder>(
    find.byWidgetPredicate(
      (widget) =>
          widget is ListenableBuilder &&
          widget.listenable is AdaptiveFeatureController,
    ),
  );
  return builder.listenable as AdaptiveFeatureController;
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

const _commandLight = PhysicalDevice(
  id: 'dev_power_01',
  name: 'Luz sala',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);

/// HTTP-parsed shape: health is unvalidated (unknown) but the device exposes
/// a canonical POWER channel, so with a command repository it stays
/// commandable.
const _commandUnknownLight = PhysicalDevice(
  id: 'dev_unknown_01',
  name: 'Luz sin validar',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: false,
  health: DeviceHealthState.unknown,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);

/// Same unvalidated shape with a legacy `on_off` channel for the plain-fake
/// fallback path.
const _legacyUnknownLight = PhysicalDevice(
  id: 'dev_unknown_01',
  name: 'Luz sin validar',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: false,
  health: DeviceHealthState.unknown,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'on_off'},
    ),
  ],
);

class _MultiGangFakeRepo implements DeviceInventoryRepository {
  _MultiGangFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
    HomeArea(id: 'cocina', name: 'Cocina'),
  ];

  List<PhysicalDevice> devices;
  final roleWrites = <(String, String, String?)>[];
  final renamedDevices = <(String, String?)>[];
  final endpointRenames = <(String, String, String?)>[];

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async => _snapshot();

  @override
  Future<DeviceInventorySnapshot> discover() async => _snapshot();

  DeviceInventorySnapshot _snapshot() => DeviceInventorySnapshot(
    areas: List.unmodifiable(areas),
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

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
    roleWrites.add((deviceId, endpointId, role));
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

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    renamedDevices.add((deviceId, userName));
    final index = _indexOf(deviceId);
    final updated = devices[index].copyWith(userName: userName);
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    endpointRenames.add((deviceId, endpointId, userName));
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(userName: userName)
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
