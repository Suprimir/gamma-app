import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/devices/desktop_device_detail_pane.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

/// F3-C Phase 11: freeze the adaptive layout matrix — compact mobile stays a
/// sequential list, narrow desktop falls back to list+push, expanded/large
/// desktop keep the master/detail split, wall renders cards, and both a
/// composition change and a live resize preserve selection without refetch.
void main() {
  testWidgets('compact mobile stays a sequential list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
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

    expect(tester.takeException(), isNull);
    // Single-column sequential mobile page: header entries + control groups,
    // never a split pane.
    expect(find.byKey(const ValueKey('open-devices-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-offline-list')), findsOneWidget);
    expect(find.text('Selecciona un dispositivo'), findsNothing);
    expect(find.byType(DesktopDevicesPage), findsNothing);
  });

  testWidgets('narrow desktop falls back to list+push', (tester) async {
    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
    await pumpDesktop(tester, repo, size: const Size(700, 900));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Selecciona un dispositivo'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);
    // The physical-area selector lives in the collapsed Configuración block.
    await tester.scrollUntilVisible(
      find.text('Configuración'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
  });

  testWidgets('expanded desktop shows master and detail', (tester) async {
    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
    await pumpDesktop(tester, repo, size: const Size(1440, 900));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Selecciona un dispositivo'), findsOneWidget);
  });

  testWidgets('large desktop detail pane is bounded', (tester) async {
    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
    final controller = await pumpDesktop(
      tester,
      repo,
      size: const Size(2560, 1440),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Selecciona un dispositivo'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.selectedDeviceId, 'dev_triple_01');
    final pane = find.byType(DesktopDeviceDetailPane);
    expect(pane, findsOneWidget);
    final paneWidth = tester.getSize(pane).width;
    // The detail pane is bounded: the fixed master column keeps it from
    // stretching across the full viewport.
    expect(paneWidth, lessThan(2560));
    expect(paneWidth, greaterThan(1000));
    expect(find.text('Canal 1'), findsOneWidget);
  });

  testWidgets('wall page renders cards without overflow', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
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

    expect(tester.takeException(), isNull);
    // Controles is the default wall view; the device list is one tap away.
    expect(find.byKey(const ValueKey('wall-devices-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wall-device-dev_fan_01')),
      findsOneWidget,
    );
  });

  testWidgets('composition change preserves selection', (tester) async {
    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
    final controller = AdaptiveFeatureController(repo)..loadDevices();
    await tester.pump();
    await tester.pump();

    controller.selectDevice('dev_triple_01');

    await tester.pumpWidget(
      MaterialApp(home: DesktopDevicesPage(controller: controller)),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );

    // Simulate a mode switch that unmounts the page tree.
    await tester.pumpWidget(const MaterialApp(home: Text('other surface')));
    await tester.pump();

    // Same controller remounts the desktop workspace.
    await tester.pumpWidget(
      MaterialApp(home: DesktopDevicesPage(controller: controller)),
    );
    await tester.pump();

    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(controller.selectedDevice, isNotNull);
  });

  testWidgets('resize across threshold keeps selection and no refetch', (
    tester,
  ) async {
    final repo = _MatrixFakeRepo(devices: const [_mTriple, _mFan]);
    final controller = await pumpDesktop(
      tester,
      repo,
      size: const Size(1440, 900),
    );

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');
    final loadsBefore = repo.loadCount;

    // Cross the feature threshold: master/detail -> narrow fallback.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();

    expect(repo.loadCount, loadsBefore);
    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
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

const _mTriple = PhysicalDevice(
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

const _mFan = PhysicalDevice(
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

class _MatrixFakeRepo implements DeviceInventoryRepository {
  _MatrixFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;
  int loadCount = 0;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCount++;
    return _snapshot();
  }

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
