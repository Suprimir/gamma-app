import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/device_inventory.dart';

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
