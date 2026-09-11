import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/dashboard/home_derivations.dart';

void main() {
  group('joinCameraStatuses', () {
    test('keeps only explicit boolean online statuses', () {
      final join = joinCameraStatuses([
        {'camera_id': 'cam_1', 'online': true},
        {'camera_id': 'cam_2', 'online': false},
        {'camera_id': 'cam_3', 'online': 'yes'},
        {'camera_id': '', 'online': true},
        {'name': 'sin id', 'online': true},
      ]);

      expect(join.onlineFor('cam_1'), isTrue);
      expect(join.onlineFor('cam_2'), isFalse);
      expect(join.onlineFor('cam_3'), isNull);
      expect(join.onlineFor(''), isNull);
      expect(join.onlineFor(null), isNull);
    });

    test('countOnlineCameras ignores configured-only cameras and legacy '
        'enabled flags', () {
      final cameras = <Map<String, dynamic>>[
        {'camera_id': 'cam_1'},
        {'camera_id': 'cam_2'},
        {'camera_id': 'cam_3', 'enabled': true},
      ];
      final join = joinCameraStatuses([
        {'camera_id': 'cam_1', 'online': true},
        {'camera_id': 'cam_2', 'online': false},
      ]);

      expect(countOnlineCameras(cameras, join), 1);
    });
  });

  group('deriveHomeStatus', () {
    test('no devices -> neutral unknown, never a fabricated zero', () {
      final summary = deriveHomeStatus(_snapshot());

      expect(summary.knownCount, 0);
      expect(summary.activeCount, 0);
      expect(summary.valueLabel, '—');
      expect(summary.tone, HomeStatusTone.neutral);
      expect(summary.subtitle, 'Estado local sin validar');
    });

    test('confirmed on counts as active with an ok tone', () {
      final summary = deriveHomeStatus(
        _snapshot(devices: [_confirmedDevice(power: true)]),
      );

      expect(summary.knownCount, 1);
      expect(summary.activeCount, 1);
      expect(summary.valueLabel, '1');
      expect(summary.tone, HomeStatusTone.ok);
      expect(summary.subtitle, 'activos de 1 con estado confirmado');
    });

    test('confirmed off plus offline health reports Revisar', () {
      final summary = deriveHomeStatus(
        _snapshot(
          devices: [
            _confirmedDevice(power: false, health: DeviceHealthState.offline),
          ],
        ),
      );

      expect(summary.knownCount, 1);
      expect(summary.activeCount, 0);
      expect(summary.valueLabel, '0');
      expect(summary.tone, HomeStatusTone.check);
    });

    test('unavailable endpoint observation forces Revisar', () {
      final summary = deriveHomeStatus(
        _snapshot(
          devices: [
            _confirmedDevice(power: true, id: 'dev_known'),
            _confirmedDevice(
              power: true,
              id: 'dev_bad',
              quality: 'unavailable',
            ),
          ],
        ),
      );

      expect(summary.knownCount, 1);
      expect(summary.tone, HomeStatusTone.check);
    });

    test('unconfirmed observation stays unknown (neutral)', () {
      final summary = deriveHomeStatus(
        _snapshot(devices: [_confirmedDevice(power: true, quality: null)]),
      );

      expect(summary.knownCount, 0);
      expect(summary.valueLabel, '—');
      expect(summary.tone, HomeStatusTone.neutral);
    });

    test('demo-only powerOn fallback is a known state (mock path)', () {
      final summary = deriveHomeStatus(
        _snapshot(devices: const [_demoPowerDevice]),
      );

      expect(summary.knownCount, 1);
      expect(summary.activeCount, 1);
      expect(summary.tone, HomeStatusTone.ok);
    });
  });

  group('areaHasPowerOn', () {
    test('true only for areas with a confirmed on device', () {
      final snapshot = _snapshot(
        areas: const [
          HomeArea(id: 'sala', name: 'Sala'),
          HomeArea(id: 'cocina', name: 'Cocina'),
        ],
        devices: [_confirmedDevice(power: true)],
      );

      expect(areaHasPowerOn(snapshot, 'sala'), isTrue);
      expect(areaHasPowerOn(snapshot, 'cocina'), isFalse);
    });

    test('physical-area placement also lights the dot', () {
      final snapshot = _snapshot(
        areas: const [HomeArea(id: 'sala', name: 'Sala')],
        devices: [_confirmedDevice(power: true, physicalAreaId: 'sala')],
      );

      expect(areaHasPowerOn(snapshot, 'sala'), isTrue);
    });

    test('unknown power never lights the dot', () {
      final snapshot = _snapshot(
        areas: const [HomeArea(id: 'sala', name: 'Sala')],
        devices: [_confirmedDevice(power: true, quality: null)],
      );

      expect(areaHasPowerOn(snapshot, 'sala'), isFalse);
    });
  });
}

DeviceInventorySnapshot _snapshot({
  List<HomeArea> areas = const [],
  List<PhysicalDevice> devices = const [],
}) {
  return DeviceInventorySnapshot(
    areas: areas,
    devices: devices,
    gateways: const [],
    lastDiscoveryLabel: '',
  );
}

PhysicalDevice _confirmedDevice({
  required bool power,
  String id = 'dev_1',
  String? physicalAreaId,
  DeviceHealthState health = DeviceHealthState.online,
  String? quality = 'confirmed',
}) {
  return PhysicalDevice(
    id: id,
    name: 'Luz sala',
    kind: DeviceKind.light,
    provider: 'Tuya',
    providerDeviceId: 'tuya-1',
    model: 'ZB-DL01',
    provisioningState: DeviceProvisioningState.configured,
    online: true,
    health: health,
    physicalAreaId: physicalAreaId,
    endpoints: [
      DeviceEndpoint(
        id: 'light',
        name: 'Luz',
        kind: DeviceKind.light,
        capabilities: const {'POWER'},
        controlledAreaId: 'sala',
        observedPower: power,
        observedQuality: quality,
      ),
    ],
  );
}

/// Mock-path device: no endpoint observations, demo-only [PhysicalDevice.powerOn].
const _demoPowerDevice = PhysicalDevice(
  id: 'dev_mock',
  name: 'Foco Zigbee',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: 'tuya-2',
  model: 'ZB-RGBCW',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [],
  powerOn: true,
);
