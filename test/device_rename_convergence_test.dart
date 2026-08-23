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

/// F3-C final: canonical mutation convergence. Mutations performed through
/// DeviceDetailView must converge back into the AdaptiveFeatureController
/// snapshot (applyCanonicalDevice-style), so master/detail and reselection
/// never show stale values. On HEAD the controller has no such API and
/// DeviceDetailView only mutates its local copy — these tests are RED.
void main() {
  testWidgets('device rename converges to controller', (tester) async {
    final repo = _ConvFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    final loadsBefore = repo.loadCalls;

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

    // The request was normalized by the backend ('Luz   Sala' -> 'Luz Sala');
    // the canonical snapshot must converge to the returned value.
    final converged = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    expect(converged.userName, 'Luz Sala');

    // Convergence must not be a refetch.
    expect(repo.loadCalls, loadsBefore);

    // Master list and reselected detail read the same canonical value.
    expect(find.text('Luz Sala'), findsWidgets);
    controller.selectDevice('dev_fan_01');
    await tester.pumpAndSettle();
    controller.selectDevice('dev_triple_01');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DeviceDetailView),
        matching: find.text('Luz Sala'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('endpoint rename converges', (tester) async {
    final repo = _ConvFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    final loadsBefore = repo.loadCalls;

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cambiar nombre del canal').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz pasillo',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      repo.renamedEndpoints,
      contains(('dev_triple_01', 'relay_1', 'Luz pasillo')),
    );

    final converged = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    final relay1 = converged.endpoints.firstWhere((e) => e.id == 'relay_1');
    expect(relay1.userName, 'Luz pasillo');

    final relay2 = converged.endpoints.firstWhere((e) => e.id == 'relay_2');
    final relay3 = converged.endpoints.firstWhere((e) => e.id == 'relay_3');
    expect(relay2.userName, isNull);
    expect(relay3.userName, isNull);
    expect(repo.loadCalls, loadsBefore);

    // Reselection shows the converged endpoint name, not the stale one.
    controller.selectDevice('dev_fan_01');
    await tester.pumpAndSettle();
    controller.selectDevice('dev_triple_01');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DeviceDetailView),
        matching: find.text('Nombre personalizado: Luz pasillo'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('controlled area mutation converges', (tester) async {
    final repo = _ConvFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    final loadsBefore = repo.loadCalls;

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // Dropdowns: 0 physical area, then per endpoint [Área que controla,
    // Qué controla]. relay_2's Área que controla is index 3.
    final dropdowns = find.byType(DropdownButtonFormField<String?>);
    expect(dropdowns, findsNWidgets(7));
    await tester.ensureVisible(dropdowns.at(3));
    await tester.tap(dropdowns.at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala').last);
    await tester.pumpAndSettle();

    expect(
      repo.endpointAreaWrites,
      contains(('dev_triple_01', 'relay_2', 'sala')),
    );

    final converged = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    final relay1 = converged.endpoints.firstWhere((e) => e.id == 'relay_1');
    final relay2 = converged.endpoints.firstWhere((e) => e.id == 'relay_2');
    final relay3 = converged.endpoints.firstWhere((e) => e.id == 'relay_3');
    expect(relay2.controlledAreaId, 'sala');
    expect(relay1.controlledAreaId, 'sala');
    expect(relay3.controlledAreaId, 'patio');
    expect(repo.loadCalls, loadsBefore);
  });

  testWidgets('semantic role set converges', (tester) async {
    final repo = _ConvFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    final loadsBefore = repo.loadCalls;

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // relay_1's 'Qué controla' dropdown is index 2.
    final dropdowns = find.byType(DropdownButtonFormField<String?>);
    await tester.ensureVisible(dropdowns.at(2));
    await tester.tap(dropdowns.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luz').last);
    await tester.pumpAndSettle();

    expect(repo.roleWrites, contains(('dev_triple_01', 'relay_1', 'light')));

    final converged = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    final relay1 = converged.endpoints.firstWhere((e) => e.id == 'relay_1');
    expect(relay1.semanticRole, 'light');

    // Master/detail converge on the same role; reselection keeps it.
    expect(find.text('Luz'), findsWidgets);
    controller.selectDevice('dev_fan_01');
    await tester.pumpAndSettle();
    controller.selectDevice('dev_triple_01');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DeviceDetailView),
        matching: find.text('Luz'),
      ),
      findsWidgets,
    );
    expect(repo.loadCalls, loadsBefore);
  });

  testWidgets('semantic role clear converges to provider result', (
    tester,
  ) async {
    final repo = _ConvFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // Set a user override first.
    final dropdowns = find.byType(DropdownButtonFormField<String?>);
    await tester.ensureVisible(dropdowns.at(2));
    await tester.tap(dropdowns.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luz').last);
    await tester.pumpAndSettle();
    expect(repo.roleWrites, contains(('dev_triple_01', 'relay_1', 'light')));

    // Clear the override; the backend answers with a provider-effective role.
    final loadsBefore = repo.loadCalls;
    await tester.ensureVisible(dropdowns.at(2));
    await tester.tap(dropdowns.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin configurar').last);
    await tester.pumpAndSettle();

    expect(repo.roleWrites, contains(('dev_triple_01', 'relay_1', null)));

    final converged = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    final relay1 = converged.endpoints.firstWhere((e) => e.id == 'relay_1');
    expect(relay1.semanticRole, 'light');
    expect(relay1.semanticRole, isNotNull);
    expect(relay1.semanticRole, isNot('unknown'));
    expect(repo.loadCalls, loadsBefore);
  });

  testWidgets('failure keeps canonical state', (tester) async {
    final repo = _ConvFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    final loadsBefore = repo.loadCalls;

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

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

    // The server detail surfaces in a SnackBar; no false success.
    expect(find.text('no se pudo renombrar'), findsOneWidget);

    // Canonical state is untouched by the failed mutation.
    final canonical = controller.snapshot!.devices.firstWhere(
      (device) => device.id == 'dev_triple_01',
    );
    expect(canonical.userName, isNull);
    expect(repo.loadCalls, loadsBefore);
    expect(find.text('Interruptor triple'), findsWidgets);
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
        // Scaffold so error SnackBars (MUT-CONV-06) have a host to present in.
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

/// Fake that intentionally returns NORMALIZED canonical DTOs that differ from
/// the request (whitespace-collapsed names; provider-effective role on clear)
/// so the UI can only converge by honoring the returned device, never by
/// replaying the request.
class _ConvFakeRepo implements DeviceInventoryRepository {
  _ConvFakeRepo({List<PhysicalDevice>? devices})
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
  final renamedEndpoints = <(String, String, String?)>[];
  final roleWrites = <(String, String, String?)>[];
  final endpointAreaWrites = <(String, String, String?)>[];
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
    renamedEndpoints.add((deviceId, endpointId, userName));
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
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    endpointAreaWrites.add((deviceId, endpointId, areaId));
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
    final target = current.endpoints.firstWhere((e) => e.id == endpointId);
    // A clear request answers with the provider-effective role, proving the
    // client must converge to the returned DTO instead of replaying null.
    final updatedEndpoint = role == null
        ? target.copyWith(semanticRole: 'light', semanticRoleSource: 'provider')
        : target.copyWith(semanticRole: role, semanticRoleSource: 'user');
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId) updatedEndpoint else endpoint,
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
