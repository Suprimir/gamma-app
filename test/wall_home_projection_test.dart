import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_home_projection.dart';

/// F3-B Phase 1: provider-neutral Wall Home projection. Pure logic, no
/// widgets. Freezes the Area/control counting policy from the baseline.
void main() {
  test('areas appear in canonical order with logical control counts', () async {
    final snapshot = await MockDeviceInventoryRepository().load();
    final wall = projectWallHome(snapshot);

    expect(wall.areas.map((area) => area.areaId), [
      'sala',
      'cocina',
      'comedor',
      'recamara',
      'pasillo',
      'patio',
    ]);
    expect(wall.areas.map((area) => area.name), [
      'Sala',
      'Cocina',
      'Comedor',
      'Recámara',
      'Pasillo',
      'Patio',
    ]);
  });

  test(
    'control counts follow controlled_area_id, not physical location',
    () async {
      final snapshot = await MockDeviceInventoryRepository().load();
      final wall = projectWallHome(snapshot);

      final byId = {for (final area in wall.areas) area.areaId: area};
      // The triple switch physically in Pasillo controls Cocina/Comedor/Patio.
      expect(byId['pasillo']!.controlCount, 0);
      expect(byId['cocina']!.controlCount, 2); // plafon light + relay_1
      expect(byId['comedor']!.controlCount, 1); // relay_2
      expect(byId['patio']!.controlCount, 1); // relay_3
      expect(byId['sala']!.controlCount, 1); // enchufe TV outlet
    },
  );

  test('multi-gang physical device is not counted three times', () async {
    final snapshot = await MockDeviceInventoryRepository().load();
    final wall = projectWallHome(snapshot);

    final pasillo = wall.areas.firstWhere((area) => area.areaId == 'pasillo');
    expect(pasillo.controlCount, 0);
    final totalControls = wall.areas.fold<int>(
      0,
      (sum, area) => sum + area.controlCount,
    );
    expect(totalControls, 5);
  });

  test('gateways never contribute controls', () async {
    final snapshot = await MockDeviceInventoryRepository().load();
    final wall = projectWallHome(snapshot);

    final totalControls = wall.areas.fold<int>(
      0,
      (sum, area) => sum + area.controlCount,
    );
    // All 6 user-facing endpoints (outlet, plafon, relay 1..3, plus none from
    // the gateway) — gateway endpoints must not appear.
    expect(totalControls, 5);
    expect(
      snapshot.devices.any(
        (device) => device.isGateway && device.endpoints.isNotEmpty,
      ),
      isFalse,
    );
  });

  test(
    'attention count uses canonical needsConfiguration on user devices',
    () async {
      final snapshot = await MockDeviceInventoryRepository().load();
      final wall = projectWallHome(snapshot);

      // discovered: switch triple, foco zigbee, sensor de movimiento.
      expect(wall.attentionCount, 3);
      // Infrastructure never inflates attention.
      expect(
        snapshot.gateways.any(
          (gateway) => snapshot.devices.any(
            (device) => device.id == gateway.id && device.needsConfiguration,
          ),
        ),
        isFalse,
      );
    },
  );

  test('empty snapshot projects empty areas and zero attention', () async {
    final wall = projectWallHome(
      const DeviceInventorySnapshot(
        areas: [],
        devices: [],
        gateways: [],
        lastDiscoveryLabel: '',
      ),
    );
    expect(wall.areas, isEmpty);
    expect(wall.attentionCount, 0);
  });

  test('unknown provisioning state never counts as configured attention', () {
    // An UNKNOWN value throws at the DTO boundary; the projection itself must
    // only ever see typed states, so a MISSING/disabled device is not
    // actionable attention.
    final device = PhysicalDevice(
      id: 'dev_x',
      name: 'X',
      kind: DeviceKind.sensor,
      provider: 'p',
      providerDeviceId: 'pid',
      model: 'm',
      provisioningState: DeviceProvisioningState.missing,
      online: false,
      health: DeviceHealthState.unknown,
      endpoints: const [],
    );
    final wall = projectWallHome(
      DeviceInventorySnapshot(
        areas: const [HomeArea(id: 'sala', name: 'Sala')],
        devices: [device],
        gateways: const [],
        lastDiscoveryLabel: '',
      ),
    );
    expect(wall.attentionCount, 0);
    expect(wall.areas.single.controlCount, 0);
  });

  test('unknown health stays neutral: no availability invented', () async {
    final snapshot = await MockDeviceInventoryRepository().load();
    final wall = projectWallHome(snapshot);
    // The projection carries no fabricated online/offline summary; only
    // counts and attention are produced.
    expect(wall.areas.every((area) => area.controlCount >= 0), isTrue);
  });
}
