import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';

import 'fixtures/command_device_fake_repo.dart';

/// F3-C micro-closure II: RED unit contract for
/// AdaptiveFeatureController.applyCanonicalDevice.
///
/// On HEAD (742312e) applyCanonicalDevice gates canonical convergence on the
/// focused selection: a canonical response for a KNOWN device that is NOT
/// currently selected is silently discarded (lib/adaptive_feature_controller.dart
/// lines 137-138). Selection is a display concern and must never decide whether
/// a canonical backend response reaches shared state. The contract:
///
///   * KNOWN-UNSELECTED  — a canonical response for a known device converges
///     even when another device is selected (B' replaces B in place).
///   * UNKNOWN-ID        — a canonical response for an id outside the snapshot
///     is a deterministic no-op (never duplicated, never fabricated).
///   * SELECTED-REPLACEMENT — the focused device still converges in place.
///
/// On HEAD the known-unselected convergence case fails (the guard discards B'); the
/// other two cases already hold and freeze the surrounding behavior.
void main() {
  // known device, not selected
  test(
    'known device not selected still converges into the snapshot in place',
    () async {
      final repo = _UnitFakeRepo(devices: const [_unitA, _unitB]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_a_01');

      // B is KNOWN but NOT selected: a canonical renamed copy of B must still
      // replace B in shared state. Selection (a display concern) must not gate.
      final renamedB = _unitB.copyWith(userName: 'Luz estudio');
      controller.applyCanonicalDevice(renamedB);

      // B replaced by identity, A untouched, order preserved, selection kept.
      expect(controller.snapshot!.devices.length, 2);
      expect(controller.snapshot!.devices.map((device) => device.id).toList(), [
        'dev_a_01',
        'dev_b_01',
      ]);
      expect(identical(controller.snapshot!.devices.last, renamedB), isTrue);
      expect(controller.snapshot!.devices.last.userName, 'Luz estudio');
      expect(controller.snapshot!.devices.first.userName, isNull);
      expect(controller.selectedDeviceId, 'dev_a_01');
    },
  );

  // unknown id outside the snapshot
  test('unknown id is a deterministic no-op (never duplicated)', () async {
    final repo = _UnitFakeRepo(devices: const [_unitA, _unitB]);
    final controller = AdaptiveFeatureController(repo);
    await controller.loadDevices();
    controller.selectDevice('dev_a_01');

    controller.applyCanonicalDevice(_unitC);

    // Snapshot unchanged: same length, same ids, same order, same selection.
    expect(controller.snapshot!.devices.length, 2);
    expect(controller.snapshot!.devices.map((device) => device.id).toList(), [
      'dev_a_01',
      'dev_b_01',
    ]);
    expect(
      controller.snapshot!.devices.map((device) => device.userName).toList(),
      [null, null],
    );
    expect(controller.selectedDeviceId, 'dev_a_01');
  });

  // selected device replacement
  test('selected device still converges in place', () async {
    final repo = _UnitFakeRepo(devices: const [_unitA, _unitB]);
    final controller = AdaptiveFeatureController(repo);
    await controller.loadDevices();
    controller.selectDevice('dev_a_01');

    final renamed = _unitA.copyWith(userName: 'Luz sala');
    controller.applyCanonicalDevice(renamed);

    // The snapshot keeps the same device order and replaces A by identity;
    // B is untouched and the selection survives.
    expect(controller.snapshot!.devices.length, 2);
    expect(controller.snapshot!.devices.map((device) => device.id).toList(), [
      'dev_a_01',
      'dev_b_01',
    ]);
    expect(identical(controller.snapshot!.devices.first, renamed), isTrue);
    expect(controller.snapshot!.devices.first.userName, 'Luz sala');
    expect(controller.snapshot!.devices.last.userName, isNull);
    expect(controller.selectedDeviceId, 'dev_a_01');
  });

  group('endpoint power commands', () {
    test('supportsEndpointCommands is false for a plain repository', () async {
      final repo = _UnitFakeRepo(devices: const [_unitA]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      expect(controller.supportsEndpointCommands, isFalse);
      await expectLater(
        controller.setEndpointPower('dev_a_01', 'light', true),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'setEndpointPower forwards the call and merges the observation',
      () async {
        final repo = CommandDeviceFakeRepo(devices: const [_commandLight]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();

        expect(controller.supportsEndpointCommands, isTrue);

        final result = await controller.setEndpointPower(
          'dev_cmd_01',
          'light',
          true,
        );

        expect(repo.powerCalls, [('dev_cmd_01', 'light', true)]);
        expect(result.outcome, 'SUCCESS');
        final endpoint = controller.snapshot!.devices.first.endpoints.first;
        expect(endpoint.observedPower, isTrue);
        expect(endpoint.observedQuality, 'confirmed');
        expect(endpoint.observedAt, '2026-09-11T00:00:00Z');
      },
    );

    test(
      'setDevicePower resolves the first endpoint with a power channel',
      () async {
        final repo = CommandDeviceFakeRepo(
          devices: const [_commandMultiEndpoint],
        );
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();

        await controller.setDevicePower('dev_cmd_01', false);

        expect(repo.powerCalls, [('dev_cmd_01', 'relay_2', false)]);
      },
    );

    test('setDevicePower throws when no endpoint exposes power', () async {
      final repo = CommandDeviceFakeRepo(devices: const [_commandSensor]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      await expectLater(
        controller.setDevicePower('dev_cmd_01', true),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            'El dispositivo no expone un canal de encendido.',
          ),
        ),
      );
    });

    test('a throwing command repo never fabricates an observation', () async {
      final repo = CommandDeviceFakeRepo(
        devices: const [_commandLight],
        powerError: ApiException(503, {'detail': 'backend down'}),
      );
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      await expectLater(
        controller.setEndpointPower('dev_cmd_01', 'light', true),
        throwsA(isA<ApiException>()),
      );
      final endpoint = controller.snapshot!.devices.first.endpoints.first;
      expect(endpoint.observedPower, isNull);
      expect(endpoint.observedQuality, isNull);
    });

    test(
      'an unparsed response keeps the snapshot observation unknown',
      () async {
        final repo = CommandDeviceFakeRepo(
          devices: const [_commandLight],
          powerResult: const EndpointPowerResult(
            outcome: 'unconfirmed',
            responseParsed: false,
          ),
        );
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();

        final result = await controller.setEndpointPower(
          'dev_cmd_01',
          'light',
          true,
        );

        expect(result.responseParsed, isFalse);
        final endpoint = controller.snapshot!.devices.first.endpoints.first;
        expect(endpoint.observedPower, isNull);
        expect(endpoint.observedQuality, isNull);
      },
    );
  });
}

const _unitA = PhysicalDevice(
  id: 'dev_a_01',
  name: 'Foco sala',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [],
);

const _unitB = PhysicalDevice(
  id: 'dev_b_01',
  name: 'Ventilador estudio',
  kind: DeviceKind.outlet,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS011F',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'pasillo',
  endpoints: [],
);

/// Unknown to the [A, B] snapshot: a canonical response for this id must be a
/// no-op (the ids never appear in the snapshot).
const _unitC = PhysicalDevice(
  id: 'dev_c_01',
  name: 'Luz terraza',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'patio',
  endpoints: [],
);

const _commandLight = PhysicalDevice(
  id: 'dev_cmd_01',
  name: 'Luz comandable',
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

/// First endpoint has no power channel: [AdaptiveFeatureController
/// .setDevicePower] must skip it and resolve `relay_2` (legacy `on_off`).
const _commandMultiEndpoint = PhysicalDevice(
  id: 'dev_cmd_01',
  name: 'Interruptor comandable',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS0013',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'linked',
      name: 'Sensor',
      kind: DeviceKind.sensor,
      capabilities: {'motion'},
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      capabilities: {'on_off'},
    ),
  ],
);

const _commandSensor = PhysicalDevice(
  id: 'dev_cmd_01',
  name: 'Sensor',
  kind: DeviceKind.sensor,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZP01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'motion',
      name: 'Movimiento',
      kind: DeviceKind.sensor,
      capabilities: {'motion'},
    ),
  ],
);

class _UnitFakeRepo implements DeviceInventoryRepository {
  _UnitFakeRepo({required this.devices});

  List<PhysicalDevice> devices;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: const [HomeArea(id: 'sala', name: 'Sala')],
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<DeviceInventorySnapshot> discover() async => load();

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    throw UnimplementedError();
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
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    final index = devices.indexWhere((device) => device.id == deviceId);
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
    throw UnimplementedError();
  }

  @override
  Future<List<HomeArea>> listAreas() async => const [
    HomeArea(id: 'sala', name: 'Sala'),
  ];

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
