import 'package:flutter_test/flutter_test.dart';
import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/device_inventory.dart';

void main() {
  group('Dirty buffer', () {
    test('initial hasPendingChanges false and pendings null', () async {
      final repo = _FakeDirtyRepo(devices: const [_light]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_light_01');

      expect(controller.hasPendingChanges, isFalse);
      expect(controller.pendingLocationId, isNull);
      expect(controller.pendingPower, isNull);
      expect(controller.pendingBrightness, isNull);
      // aliases per design
      expect(controller.pendingLocation, isNull);
    });

    test('markPendingLocation sets dirty without repo call', () async {
      final repo = _FakeDirtyRepo(devices: const [_light]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      controller.markPendingLocation('cocina');

      expect(controller.pendingLocationId, 'cocina');
      expect(controller.pendingLocation, 'cocina');
      expect(controller.hasPendingChanges, isTrue);
      expect(repo.assignCalls, isEmpty);
    });

    test('markPendingBrightness and markPendingPower set dirty', () async {
      final repo = _FakeDirtyRepo(devices: const [_light]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      controller.markPendingBrightness(25);
      expect(controller.pendingBrightness, 25);
      expect(controller.hasPendingChanges, isTrue);

      controller.markPendingPower(false);
      expect(controller.pendingPower, isFalse);
      expect(controller.hasPendingChanges, isTrue);
    });

    test('generic markDirty sets all', () async {
      final repo = _FakeDirtyRepo(devices: const [_light]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      controller.markDirty(locationId: 'sala', power: true, brightness: 50);

      expect(controller.pendingLocationId, 'sala');
      expect(controller.pendingPower, isTrue);
      expect(controller.pendingBrightness, 50);
      expect(controller.hasPendingChanges, isTrue);
    });

    test('discardPendingChanges clears buffer', () async {
      final repo = _FakeDirtyRepo(devices: const [_light]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.markDirty(locationId: 'cocina', brightness: 100);

      controller.discardPendingChanges();

      expect(controller.hasPendingChanges, isFalse);
      expect(controller.pendingLocationId, isNull);
      expect(controller.pendingBrightness, isNull);
    });

    test(
      'commitPendingChanges sequential canonical updates via repository',
      () async {
        final repo = _FakeDirtyRepo(devices: const [_light]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_light_01');
        controller.markPendingLocation('cocina');

        final result = await controller.commitPendingChanges('dev_light_01');

        expect(repo.assignCalls.length, 1);
        expect(repo.assignCalls.first, ('dev_light_01', 'cocina'));
        expect(controller.hasPendingChanges, isFalse);
        expect(controller.pendingLocationId, isNull);
        // canonical converged
        expect(controller.snapshot!.devices.first.physicalAreaId, 'cocina');
        expect(result.physicalAreaId, 'cocina');
      },
    );

    test('commit failure keeps dirty', () async {
      final repo = _FakeDirtyRepo(
        devices: const [_light],
        shouldFailAssign: true,
      );
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.markPendingLocation('cocina');

      try {
        await controller.commitPendingChanges('dev_light_01');
        fail('should throw');
      } catch (_) {}

      expect(controller.hasPendingChanges, isTrue);
      expect(controller.pendingLocationId, 'cocina');
    });

    test('clear on selection change discards pending', () async {
      final repo = _FakeDirtyRepo(devices: const [_light, _fan]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_light_01');
      controller.markPendingLocation('cocina');
      expect(controller.hasPendingChanges, isTrue);

      controller.selectDevice('dev_fan_01');

      expect(controller.hasPendingChanges, isFalse);
      expect(controller.pendingLocationId, isNull);
      expect(controller.selectedDeviceId, 'dev_fan_01');
    });

    test(
      'preserve applyCanonicalDevice convergence for known unselected',
      () async {
        final repo = _FakeDirtyRepo(devices: const [_light, _fan]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_light_01');
        final updatedFan = _fan.copyWith(userName: 'Fan sala');
        controller.applyCanonicalDevice(updatedFan);
        expect(controller.snapshot!.devices.last.userName, 'Fan sala');
        expect(controller.selectedDeviceId, 'dev_light_01');
      },
    );

    test(
      'commit with power and brightness does not require repo and clears',
      () async {
        final repo = _FakeDirtyRepo(devices: const [_light]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.markPendingPower(true);
        controller.markPendingBrightness(25);

        await controller.commitPendingChanges('dev_light_01');

        expect(controller.hasPendingChanges, isFalse);
        // location repo not called when only power/brightness pending
        expect(repo.assignCalls, isEmpty);
      },
    );
  });
}

const _light = PhysicalDevice(
  id: 'dev_light_01',
  name: 'Luz techo cocina',
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
      capabilities: {'on_off', 'brightness'},
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
  endpoints: [],
);

class _FakeDirtyRepo implements DeviceInventoryRepository {
  _FakeDirtyRepo({
    required List<PhysicalDevice> devices,
    this.shouldFailAssign = false,
  }) : devices = List.of(devices);

  List<PhysicalDevice> devices;
  bool shouldFailAssign;
  final assignCalls = <(String, String?)>[];

  @override
  bool get supportsIdentify => false;
  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: const [
      HomeArea(id: 'sala', name: 'Sala'),
      HomeArea(id: 'cocina', name: 'Cocina'),
      HomeArea(id: 'pasillo', name: 'Pasillo'),
    ],
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
    assignCalls.add((deviceId, areaId));
    if (shouldFailAssign) throw StateError('assign failed');
    final idx = devices.indexWhere((d) => d.id == deviceId);
    final updated = devices[idx].copyWith(physicalAreaId: areaId);
    devices[idx] = updated;
    return updated;
  }

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
  Future<List<HomeArea>> listAreas() async => const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'cocina', name: 'Cocina'),
  ];
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
