import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

PhysicalDevice _device() => const PhysicalDevice(
  id: 'dev_1',
  name: 'Luz',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: 'tuya-aa22',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER', 'BRIGHTNESS'},
    ),
    DeviceEndpoint(
      id: 'led',
      name: 'LED',
      kind: DeviceKind.light,
      capabilities: {'BRIGHTNESS'},
    ),
  ],
);

class _CommandFakeRepo
    implements DeviceInventoryRepository, DeviceCommandRepository {
  _CommandFakeRepo() : devices = [_device()];

  final List<PhysicalDevice> devices;
  bool identifySupported = true;
  String? identifyReason;
  final identifyCalls = <(String, String?)>[];
  Object? bindError;
  final bindCalls = <(String, String, String, String)>[];

  /// Configurable result for [executeAction]; defaults to a parsed SUCCESS.
  CapabilityActionResult? actionResult;

  /// When set, [executeAction] throws it instead of returning a result.
  Object? actionError;

  /// Recorded `executeAction` calls as (deviceId, endpointId, action, value).
  final actionCalls = <(String, String, String, Object)>[];

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: const [],
    devices: devices,
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<DeviceInventorySnapshot> discover() async => load();

  @override
  Future<IdentifyResult> identifyDevice(
    String deviceId, {
    String? endpointId,
  }) async {
    identifyCalls.add((deviceId, endpointId));
    return IdentifyResult(supported: identifySupported, reason: identifyReason);
  }

  @override
  Future<PhysicalDevice> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  }) async {
    bindCalls.add((deviceId, endpointId, entityId, capability));
    final error = bindError;
    if (error != null) throw error;
    final index = devices.indexWhere((device) => device.id == deviceId);
    final updated = devices[index].copyWith(
      endpoints: [
        for (final endpoint in devices[index].endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(
              bindings: [
                DeviceBinding(targetEntityId: entityId, label: entityId),
              ],
            )
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  @override
  Future<CapabilityActionResult> executeAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  }) async {
    actionCalls.add((deviceId, endpointId, action, value));
    final error = actionError;
    if (error != null) throw error;
    return actionResult ??
        CapabilityActionResult(
          action: action,
          outcome: 'SUCCESS',
          changed: true,
        );
  }

  @override
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> unbindEntity(
    String deviceId,
    String bindingId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> refreshDevice(String deviceId) async =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameDevice(
    String deviceId,
    String? userName,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async => throw UnimplementedError();

  @override
  Future<List<HomeArea>> listAreas() async => const [];

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async => throw UnimplementedError();

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteArea(String areaId) async => throw UnimplementedError();

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}

/// Plain repository (no command surface) used to pin the legacy fallback.
class _PlainFakeRepo implements DeviceInventoryRepository {
  @override
  bool get supportsIdentify => true;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: const [],
    devices: [_device()],
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<DeviceInventorySnapshot> discover() async => load();

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameDevice(
    String deviceId,
    String? userName,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async => throw UnimplementedError();

  @override
  Future<List<HomeArea>> listAreas() async => const [];

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async => throw UnimplementedError();

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteArea(String areaId) async => throw UnimplementedError();
}

Future<void> _pumpDetail(
  WidgetTester tester,
  DeviceInventoryRepository repository, {
  ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged,
}) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DeviceDetailView(
          device: _device(),
          areas: const [],
          gateways: const [],
          repository: repository,
          onCanonicalDeviceChanged: onCanonicalDeviceChanged,
        ),
      ),
    ),
  );
  await tester.pump();
  // Per-channel configuration (identify, bind, area, role) is collapsed
  // under 'Configuración' by default: expand it for these action tests.
  await tester.tap(find.text('Configuración'));
  await tester.pumpAndSettle();
}

Future<void> _submitBinding(WidgetTester tester, String entityId) async {
  await tester.tap(find.text('Vincular entidad').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), entityId);
  await tester.tap(find.text('Vincular'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('identify rejected by the provider shows the honest reason', (
    tester,
  ) async {
    final repo = _CommandFakeRepo()
      ..identifySupported = false
      ..identifyReason = 'el proveedor no expone LED';

    await _pumpDetail(tester, repo);
    await tester.tap(find.text('Identificar').first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'El proveedor no soporta identificación: '
        'el proveedor no expone LED',
      ),
      findsOneWidget,
    );
    expect(repo.identifyCalls.single, ('dev_1', 'light'));
  });

  testWidgets('identify accepted keeps the current success copy', (
    tester,
  ) async {
    final repo = _CommandFakeRepo();

    await _pumpDetail(tester, repo);
    await tester.tap(find.text('Identificar').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Se envió la orden de identificación a light.'),
      findsOneWidget,
    );
  });

  testWidgets('bind entity calls the command layer with POWER and converges', (
    tester,
  ) async {
    final repo = _CommandFakeRepo();
    PhysicalDevice? converged;

    await _pumpDetail(
      tester,
      repo,
      onCanonicalDeviceChanged: (device) => converged = device,
    );
    await _submitBinding(tester, 'luz_sala');

    expect(repo.bindCalls.single, ('dev_1', 'light', 'luz_sala', 'POWER'));
    expect(find.text('Entidad vinculada'), findsOneWidget);
    expect(
      converged?.endpoints.first.bindings.single.targetEntityId,
      'luz_sala',
    );
  });

  testWidgets('bind entity falls back to the first capability without POWER', (
    tester,
  ) async {
    final repo = _CommandFakeRepo();

    await _pumpDetail(tester, repo);
    // The second channel exposes only BRIGHTNESS.
    await tester.tap(find.text('Vincular entidad').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'led_sala');
    await tester.tap(find.text('Vincular'));
    await tester.pumpAndSettle();

    expect(repo.bindCalls.single, ('dev_1', 'led', 'led_sala', 'BRIGHTNESS'));
  });

  testWidgets(
    'bind failure shows the real backend detail, not simulated copy',
    (tester) async {
      final repo = _CommandFakeRepo()
        ..bindError = ApiException(400, {'detail': 'Entidad no encontrada'});

      await _pumpDetail(tester, repo);
      await _submitBinding(tester, 'luz_fantasma');

      expect(find.text('Entidad no encontrada'), findsOneWidget);
      expect(find.textContaining('Vinculación simulada'), findsNothing);
    },
  );

  testWidgets('plain repository keeps the legacy simulated binding', (
    tester,
  ) async {
    final repo = _PlainFakeRepo();

    await _pumpDetail(tester, repo);
    await _submitBinding(tester, 'luz_sala');

    expect(
      find.text('Vinculación simulada con éxito: luz_sala'),
      findsOneWidget,
    );
  });
}
