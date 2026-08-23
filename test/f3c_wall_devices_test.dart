import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-C Phase 5: touch-first Wall Panel Devices — large tappable cards,
/// simplified detail reusing DeviceDetailView, no raw technical vocabulary,
/// no physical controls, wall home attention entry.
void main() {
  testWidgets('F3C-WALL-01 large card summary in household language', (
    tester,
  ) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    final triple = find.byKey(const ValueKey('wall-device-dev_triple_01'));
    expect(triple, findsOneWidget);
    expect(find.text('Interruptor triple'), findsOneWidget);
    expect(
      find.descendant(
        of: triple,
        matching: find.text('Habitación física: Pasillo'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: triple, matching: find.text('Sin configurar')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: triple, matching: find.text('3 controles')),
      findsOneWidget,
    );

    final fan = find.byKey(const ValueKey('wall-device-dev_fan_01'));
    expect(fan, findsOneWidget);
    expect(find.text('Ventilador estudio'), findsOneWidget);
    expect(
      find.descendant(
        of: fan,
        matching: find.text('Habitación física: Pasillo'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fan, matching: find.text('Configurado')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fan, matching: find.text('1 control')),
      findsOneWidget,
    );

    // Raw provider/endpoint/DP vocabulary never reaches the wall list, even
    // though the fixtures carry provider IDs.
    expect(find.textContaining('tuya-'), findsNothing);
    expect(find.textContaining('endpoint'), findsNothing);
    expect(find.textContaining('DP'), findsNothing);
  });

  testWidgets('F3C-WALL-02 card opens simplified detail and back returns', (
    tester,
  ) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsOneWidget);
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    expect(find.text('Controles'), findsOneWidget);
    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsNothing);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Interruptor triple'), findsOneWidget);
  });

  testWidgets('F3C-WALL-03 touch target at least 72 dp high', (tester) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);

    final card = find.byKey(const ValueKey('wall-device-dev_triple_01'));
    final size = tester.getSize(card);
    expect(size.height, greaterThanOrEqualTo(72));
    expect(size.width, greaterThanOrEqualTo(64));
  });

  testWidgets('F3C-WALL-04 multi-gang independence on wall', (tester) async {
    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await pumpWall(tester, repo);
    final controller = _wallController(tester);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);

    await repo.assignEndpointSemanticRole('dev_triple_01', 'relay_1', 'fan');
    await controller.loadDevices();
    await tester.pumpAndSettle();

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

    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
  });

  testWidgets('F3C-WALL-05 no ON/OFF controls on list or detail', (
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

  testWidgets('F3C-WALL-06 wall home attention opens wall devices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _WallFakeRepo(devices: const [_wallTriple, _wallFan]);
    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Necesita atención'), findsOneWidget);
    await tester.tap(find.text('Necesita atención'));
    await tester.pumpAndSettle();

    expect(find.byType(WallDevicesPage), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Interruptor triple'), findsOneWidget);
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

/// The page owns its AdaptiveFeatureController; reach it through its
/// ListenableBuilder without exposing test-only API in production.
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

const _wallTriple = PhysicalDevice(
  id: 'dev_triple_01',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: 'tuya-bf8a••••',
  model: 'TS0013',
  provisioningState: DeviceProvisioningState.discovered,
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
  final roleWrites = <(String, String, String?)>[];

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
