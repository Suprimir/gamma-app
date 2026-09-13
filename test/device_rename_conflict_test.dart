import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';

/// Backend contract regression: renaming an endpoint to a normalized duplicate
/// within the same semantic area answers HTTP 409 with a household-language
/// `detail`. The app must surface that exact message and converge nothing: the
/// rejected name never reaches the canonical controller snapshot and no reload
/// is triggered.
void main() {
  testWidgets(
    'endpoint rename conflict surfaces backend detail, no convergence',
    (tester) async {
      final repo = _ConflictFakeRepo(devices: const [_triple, _fan]);
      final controller = await pumpDesktop(tester, repo);
      final loadsBefore = repo.loadCalls;

      await tester.tap(
        find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      );
      await tester.pumpAndSettle();

      final relayBefore = controller.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .endpoints
          .firstWhere((endpoint) => endpoint.id == 'relay_1');

      await tester.tap(find.byTooltip('Cambiar nombre del canal').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Luz',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // The 409 detail is surfaced verbatim and the rejected mutation shows no
      // fake success.
      expect(
        find.text(
          "Ya existe otro control con el nombre 'Luz' en la misma ubicación",
        ),
        findsOneWidget,
      );
      expect(find.text('Nombre actualizado'), findsNothing);

      // The canonical snapshot keeps the previous name; the conflict does not
      // converge the request value and does not trigger a refetch.
      final relayAfter = controller.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .endpoints
          .firstWhere((endpoint) => endpoint.id == 'relay_1');
      expect(relayAfter.userName, relayBefore.userName);
      expect(relayAfter.userName, isNull);
      expect(
        repo.renamedEndpointAttempts,
        contains(('dev_triple_01', 'relay_1', 'Luz')),
      );
      expect(repo.loadCalls, loadsBefore);
    },
  );
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
        // Scaffold so the conflict SnackBar has a host to present in.
        child: Scaffold(body: DesktopDevicesPage(controller: controller)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
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

/// Fake that rejects both rename mutations with the backend duplicate-name
/// conflict, so the UI can only pass by surfacing the 409 `detail` verbatim.
class _ConflictFakeRepo implements DeviceInventoryRepository {
  _ConflictFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;

  int loadCalls = 0;
  final renamedEndpointAttempts = <(String, String, String?)>[];

  static const conflictMessage =
      "Ya existe otro control con el nombre 'Luz' en la misma ubicación";

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

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    throw ApiException(409, {'detail': conflictMessage});
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    renamedEndpointAttempts.add((deviceId, endpointId, userName));
    throw ApiException(409, {'detail': conflictMessage});
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    throw UnimplementedError();
  }

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
