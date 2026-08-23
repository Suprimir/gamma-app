import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_home_projection.dart';

/// F3-B Phase 9: multi-gang Area correctness with the mandated provider-neutral
/// fixture. The physical switch hangs in Pasillo; its endpoints control three
/// different rooms.
void main() {
  // Fixture (SPECS #39): physical 3-gang switch in Pasillo.
  //   endpoint A -> controlled_area Sala
  //   endpoint B -> controlled_area Comedor
  //   endpoint C -> controlled_area Patio
  final snapshot = DeviceInventorySnapshot(
    areas: const [
      HomeArea(id: 'pasillo', name: 'Pasillo'),
      HomeArea(id: 'sala', name: 'Sala'),
      HomeArea(id: 'comedor', name: 'Comedor'),
      HomeArea(id: 'patio', name: 'Patio'),
    ],
    devices: [
      const PhysicalDevice(
        id: 'dev_triple',
        name: 'Interruptor triple',
        kind: DeviceKind.switchController,
        provider: 'p',
        providerDeviceId: 'pid',
        model: 'm',
        provisioningState: DeviceProvisioningState.configured,
        online: true,
        health: DeviceHealthState.online,
        physicalAreaId: 'pasillo',
        endpoints: [
          DeviceEndpoint(
            id: 'a',
            name: 'A',
            kind: DeviceKind.switchController,
            controlledAreaId: 'sala',
            capabilities: {'on_off'},
          ),
          DeviceEndpoint(
            id: 'b',
            name: 'B',
            kind: DeviceKind.switchController,
            controlledAreaId: 'comedor',
            capabilities: {'on_off'},
          ),
          DeviceEndpoint(
            id: 'c',
            name: 'C',
            kind: DeviceKind.switchController,
            controlledAreaId: 'patio',
            capabilities: {'on_off'},
          ),
        ],
      ),
    ],
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  test('physical device count is not tripled', () {
    final wall = projectWallHome(snapshot);
    final totalDevices = snapshot.devices.length;
    expect(totalDevices, 1);
    expect(snapshot.devices.single.id, 'dev_triple');
    // The projection counts controls per Area, never physical devices.
    final totalControls = wall.areas.fold<int>(
      0,
      (sum, area) => sum + area.controlCount,
    );
    expect(totalControls, 3);
  });

  test('logical control count follows controlled_area_id', () {
    final wall = projectWallHome(snapshot);
    final byId = {for (final area in wall.areas) area.areaId: area};
    expect(byId['pasillo']!.controlCount, 0);
    expect(byId['sala']!.controlCount, 1);
    expect(byId['comedor']!.controlCount, 1);
    expect(byId['patio']!.controlCount, 1);
  });

  test('physical_area_id remains distinct from controlled areas', () {
    final device = snapshot.devices.single;
    expect(device.physicalAreaId, 'pasillo');
    expect(device.endpoints.map((endpoint) => endpoint.controlledAreaId), [
      'sala',
      'comedor',
      'patio',
    ]);
    // The projection never rewrites physical placement from endpoints.
    final pasillo = projectWallHome(
      snapshot,
    ).areas.firstWhere((area) => area.areaId == 'pasillo');
    expect(pasillo.controlCount, 0);
  });

  test('area drill-down lists the controlled endpoints per room', () {
    final salaControls = projectAreaControls(snapshot, 'sala');
    expect(salaControls.map((control) => control.displayName), ['A']);
    final pasilloControls = projectAreaControls(snapshot, 'pasillo');
    expect(pasilloControls, isEmpty);
  });

  test('infrastructure stays out of the projection', () {
    final withGateway = DeviceInventorySnapshot(
      areas: snapshot.areas,
      devices: [
        ...snapshot.devices,
        const PhysicalDevice(
          id: 'gw',
          name: 'Gateway',
          kind: DeviceKind.gateway,
          provider: 'p',
          providerDeviceId: 'gpid',
          model: 'g',
          provisioningState: DeviceProvisioningState.configured,
          online: true,
          health: DeviceHealthState.online,
          isGateway: true,
          endpoints: [
            DeviceEndpoint(
              id: 'radio',
              name: 'Radio',
              kind: DeviceKind.gateway,
              capabilities: {'radio'},
            ),
          ],
        ),
      ],
      gateways: const [
        GatewayInfo(
          id: 'gw',
          name: 'Gateway',
          provider: 'p',
          health: DeviceHealthState.online,
          childDeviceIds: ['dev_triple'],
        ),
      ],
      lastDiscoveryLabel: '',
    );
    final wall = projectWallHome(withGateway);
    expect(wall.areas.fold<int>(0, (sum, area) => sum + area.controlCount), 3);
    expect(wall.attentionCount, 0);
  });
}
