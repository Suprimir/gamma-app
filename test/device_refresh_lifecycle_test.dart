import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/areas/desktop_areas_page.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

import 'fixtures/areas_fake_repo.dart';

/// F3-C Phase 12: error and lifecycle hardening — user-facing load errors with
/// retry, refresh failures keeping the snapshot, truthful mutation errors,
/// stale-selection cleanup, safe disposal and no polling.
void main() {
  testWidgets('initial error shows user-facing message and retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _LifecycleFakeRepo(devices: const [_lcTriple, _lcFan])
      ..loadError = Exception('backend boom');
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
    await tester.pumpAndSettle();

    // The raw exception never leaks to the user.
    expect(find.text('No se pudieron cargar los dispositivos'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('backend boom'), findsNothing);

    repo.loadError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudieron cargar los dispositivos'), findsNothing);
    expect(find.text('Dispositivos'), findsOneWidget);
  });

  testWidgets('refresh failure retains the snapshot', (tester) async {
    final repo = _LifecycleFakeRepo(devices: const [_lcTriple, _lcFan]);
    final controller = await pumpDesktop(tester, repo);
    expect(repo.loadCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    repo.loadError = Exception('network down');
    await controller.loadDevices();
    await tester.pumpAndSettle();

    expect(controller.snapshot, isNotNull);
    expect(controller.deviceError, isNotNull);
    // The list stays visible; the error never replaces the snapshot.
    expect(find.text('Reintentar'), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );
  });

  testWidgets('mutation 4xx is truthful', (tester) async {
    final repo = _LifecycleFakeRepo(devices: const [_lcTriple, _lcFan]);
    final controller = await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    repo.renameError = ApiException(422, {
      'detail': 'El nombre ya está en uso',
    });
    await tester.tap(find.byTooltip('Cambiar nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Nombre falso',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Guardar'),
      ),
    );
    await tester.pumpAndSettle();

    // The server detail surfaces in a SnackBar and the canonical name stays.
    expect(find.text('El nombre ya está en uso'), findsOneWidget);
    expect(find.text('Nombre falso'), findsNothing);
    expect(find.text('Interruptor triple'), findsWidgets);
    expect(controller.selectedDeviceId, 'dev_triple_01');
  });

  testWidgets('stale selected object clears on wall', (tester) async {
    final repo = _LifecycleFakeRepo(devices: const [_lcTriple, _lcFan]);
    await pumpWall(tester, repo);

    await tester.tap(find.byKey(const ValueKey('wall-device-dev_triple_01')));
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);

    // The device disappears concurrently; coming back refreshes the list.
    repo.devices = const [_lcFan];
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsNothing);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('wall-device-dev_fan_01')),
      findsOneWidget,
    );
  });

  testWidgets('area deleted during selection clears it', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    final controller = await pumpDesktopAreas(tester, repo);

    await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
    await tester.pumpAndSettle();
    expect(controller.selectedAreaId, 'area_SALA');

    repo.areas = const [HomeArea(id: 'area_COCINA', name: 'Cocina')];
    await controller.loadAreas();
    await tester.pumpAndSettle();

    expect(controller.selectedAreaId, isNull);
    expect(find.byKey(const ValueKey('desktop-area-area_SALA')), findsNothing);
    expect(find.text('Selecciona un área'), findsOneWidget);
  });

  testWidgets('controller disposal is safe', (tester) async {
    final repo = _LifecycleFakeRepo(devices: const [_lcTriple, _lcFan]);
    final controller = AdaptiveFeatureController(repo)..loadDevices();
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: DesktopDevicesPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    // Unmount the tree, then dispose the controller: no exceptions.
    await tester.pumpWidget(const MaterialApp(home: Text('replaced')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('b dispose during in-flight load never notifies', (tester) async {
    final repo = _LifecycleFakeRepo(devices: const [_lcTriple]);
    repo.pendingLoad = Completer<DeviceInventorySnapshot>();
    final controller = AdaptiveFeatureController(repo);
    final loading = controller.loadDevices();
    await tester.pump();

    controller.dispose();
    repo.pendingLoad!.complete(repo._snapshot());
    await loading;

    expect(tester.takeException(), isNull);
  });

  testWidgets('no polling after load', (tester) async {
    final repo = _LifecycleFakeRepo(devices: const [_lcTriple]);
    final controller = AdaptiveFeatureController(repo)..loadDevices();
    await tester.pump();
    await tester.pump();
    expect(repo.loadCount, 1);

    await tester.pump(const Duration(seconds: 5));
    expect(repo.loadCount, 1);
    expect(controller.snapshot, isNotNull);
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
      home: Scaffold(
        body: AppAdaptiveScope(
          windowClass: AppWindowClass.expanded,
          effectiveSurface: EffectiveAppSurface.desktop,
          controller: AdaptiveSurfaceModeController(),
          child: DesktopDevicesPage(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

Future<AdaptiveFeatureController> pumpDesktopAreas(
  WidgetTester tester,
  DeviceInventoryRepository repo, {
  Size size = const Size(1440, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = AdaptiveFeatureController(repo)..loadAreas();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppAdaptiveScope(
          windowClass: AppWindowClass.expanded,
          effectiveSurface: EffectiveAppSurface.desktop,
          controller: AdaptiveSurfaceModeController(),
          child: DesktopAreasPage(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
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

const _lcTriple = PhysicalDevice(
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

const _lcFan = PhysicalDevice(
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

class _LifecycleFakeRepo implements DeviceInventoryRepository {
  _LifecycleFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;
  Object? loadError;
  Object? renameError;
  Completer<DeviceInventorySnapshot>? pendingLoad;
  int loadCount = 0;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCount++;
    if (pendingLoad != null) return pendingLoad!.future;
    if (loadError != null) throw loadError!;
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
    if (renameError != null) throw renameError!;
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
