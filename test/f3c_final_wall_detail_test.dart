import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

/// F3-C final: the wall device detail must be household-first. On HEAD
/// _WallDeviceDetailPage wraps the generic DeviceDetailView unchanged, so raw
/// technical vocabulary ('ENDPOINTS / CANALES', 'ID Gamma', 'ID proveedor',
/// capabilities), fully visible integration metadata and mobile-sized
/// controls all leak into the wall surface. These tests are RED.
void main() {
  testWidgets('F3C-WALL-DETAIL-COPY primary wall detail is human-first', (
    tester,
  ) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsOneWidget);

    // Household vocabulary is the primary content of the wall detail.
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Habitación física'), findsOneWidget);
    expect(find.text('Controles'), findsOneWidget);

    // Technical vocabulary never surfaces in the primary wall view.
    expect(find.text('ENDPOINTS / CANALES'), findsNothing);
    expect(find.text('ID proveedor'), findsNothing);
    expect(find.text('ID Gamma'), findsNothing);
    expect(find.textContaining('on_off'), findsNothing);
  });

  testWidgets(
    'F3C-WALL-TECHNICAL-COLLAPSED technical info collapsed by default',
    (tester) async {
      final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
      await pumpWall(tester, repo);

      await tester.tap(find.text('Interruptor triple'));
      await tester.pumpAndSettle();

      // A technical section exists but stays collapsed: raw metadata (IDs,
      // provider gateway fields) is hidden until explicitly expanded.
      expect(find.text('Información técnica'), findsOneWidget);
      expect(find.text('ID Gamma'), findsNothing);
      expect(find.text('ID proveedor'), findsNothing);
      expect(find.text('Modelo'), findsNothing);
    },
  );

  testWidgets('F3C-WALL-TOUCH wall detail interactive controls >= 64dp', (
    tester,
  ) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    final rename = find.byTooltip('Cambiar nombre');
    final renameSize = tester.getSize(rename);
    expect(renameSize.height, greaterThanOrEqualTo(64));
    expect(renameSize.width, greaterThanOrEqualTo(64));

    final physicalArea = find.descendant(
      of: find.byKey(const Key('physical-area-dropdown')),
      matching: find.byType(DropdownButtonFormField<String?>),
    );
    final areaSize = tester.getSize(physicalArea);
    expect(areaSize.height, greaterThanOrEqualTo(64));
  });

  testWidgets('F3C-WALL-TEXT-SCALE labels not clipped at large scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in [
      'Nombre',
      'Habitación física',
      'Controles',
      'Qué controla',
      'Habitación que controla',
    ]) {
      expect(find.textContaining(label), findsWidgets);
    }
  });

  testWidgets('F3C-WALL-NEGATIVE no power controls on wall detail', (
    tester,
  ) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(find.textContaining('ON'), findsNothing);
    expect(find.textContaining('OFF'), findsNothing);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(find.textContaining('ON'), findsNothing);
    expect(find.textContaining('OFF'), findsNothing);
  });
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

const _wallTriple = PhysicalDevice(
  id: 'dev_triple_01',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: 'tuya-bf8a••••',
  model: 'TS0013',
  manufacturer: 'MockCo',
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

const _wallFan = PhysicalDevice(
  id: 'dev_fan_01',
  name: 'Ventilador estudio',
  kind: DeviceKind.outlet,
  provider: 'Tuya',
  providerDeviceId: 'tuya-a911••••',
  model: 'TS011F',
  manufacturer: 'MockCo',
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

class _WallFakeRepo implements DeviceInventoryRepository {
  _WallFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;

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
