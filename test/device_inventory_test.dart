import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/device_inventory.dart';

void main() {
  test('mock inventory separates physical devices from endpoints', () async {
    final repository = MockDeviceInventoryRepository();
    final snapshot = await repository.load();
    final triple = snapshot.devices.firstWhere(
      (device) => device.id == 'dev_switch_triple_01',
    );

    expect(triple.physicalAreaId, isNull);
    expect(triple.endpoints, hasLength(3));
    expect(
      triple.endpoints.every((endpoint) => endpoint.controlledAreaId == null),
      isTrue,
    );
    expect(triple.needsConfiguration, isTrue);
  });

  test(
    'triple switch stays pending until physical area and all endpoints are assigned',
    () async {
      final repository = MockDeviceInventoryRepository();

      var device = await repository.assignPhysicalArea(
        'dev_switch_triple_01',
        'pasillo',
      );
      expect(
        device.provisioningState,
        DeviceProvisioningState.partiallyConfigured,
      );
      expect(device.needsConfiguration, isTrue);

      device = await repository.assignEndpointArea(
        device.id,
        'relay_1',
        'cocina',
      );
      device = await repository.assignEndpointArea(
        device.id,
        'relay_2',
        'comedor',
      );
      device = await repository.assignEndpointArea(
        device.id,
        'relay_3',
        'patio',
      );

      expect(device.physicalAreaId, 'pasillo');
      expect(device.provisioningState, DeviceProvisioningState.configured);
      expect(device.needsConfiguration, isFalse);
      expect(device.endpoints.map((endpoint) => endpoint.controlledAreaId), [
        'cocina',
        'comedor',
        'patio',
      ]);
    },
  );

  test(
    'area lookup includes devices controlled from another physical area',
    () async {
      final repository = MockDeviceInventoryRepository();
      final snapshot = await repository.load();

      final kitchen = snapshot
          .devicesInArea('cocina')
          .map((device) => device.id)
          .toSet();

      expect(kitchen, contains('dev_plafon_cocina'));
      expect(kitchen, contains('dev_wall_pasillo'));
    },
  );

  group('parseProvisioningState', () {
    test('ENRICHED maps to enriched', () {
      expect(
        parseProvisioningState('ENRICHED'),
        DeviceProvisioningState.enriched,
      );
    });

    test('known values map to their states', () {
      expect(
        parseProvisioningState('DISCOVERED'),
        DeviceProvisioningState.discovered,
      );
      expect(
        parseProvisioningState('PARTIALLY_CONFIGURED'),
        DeviceProvisioningState.partiallyConfigured,
      );
      expect(
        parseProvisioningState('CONFIGURED'),
        DeviceProvisioningState.configured,
      );
      expect(
        parseProvisioningState('MISSING'),
        DeviceProvisioningState.missing,
      );
      expect(
        parseProvisioningState('DISABLED'),
        DeviceProvisioningState.disabled,
      );
    });

    test('unknown value throws DeviceDtoException', () {
      expect(
        () => parseProvisioningState('whatever'),
        throwsA(isA<DeviceDtoException>()),
      );
    });

    test('null throws DeviceDtoException', () {
      expect(
        () => parseProvisioningState(null),
        throwsA(isA<DeviceDtoException>()),
      );
    });
  });

  group('ProviderHealth', () {
    test('parseProviderHealthState maps known values', () {
      expect(
        parseProviderHealthState('LAN_READY'),
        ProviderHealthState.lanReady,
      );
      expect(
        parseProviderHealthState('CLOUD_READY'),
        ProviderHealthState.cloudReady,
      );
      expect(
        parseProviderHealthState('CLOUD_DEGRADED'),
        ProviderHealthState.cloudDegraded,
      );
      expect(
        parseProviderHealthState('CLOUD_NOT_CONFIGURED'),
        ProviderHealthState.cloudNotConfigured,
      );
      expect(
        parseProviderHealthState('AUTH_ERROR'),
        ProviderHealthState.authError,
      );
    });

    test('parseProviderHealthState fails safe to unknown', () {
      expect(parseProviderHealthState('weird'), ProviderHealthState.unknown);
      expect(parseProviderHealthState(null), ProviderHealthState.unknown);
    });

    test('fromJson parses a complete health entry', () {
      final health = ProviderHealth.fromJson(const {
        'provider_id': 'tuya',
        'lan_ready': true,
        'cloud_ready': true,
        'status': 'LAN_READY',
      });

      expect(health.providerId, 'tuya');
      expect(health.lanReady, isTrue);
      expect(health.cloudReady, isTrue);
      expect(health.state, ProviderHealthState.lanReady);
    });

    test('fromJson defaults missing fields without throwing', () {
      final health = ProviderHealth.fromJson(const {'status': 'WEIRD'});

      expect(health.providerId, '');
      expect(health.lanReady, isFalse);
      expect(health.cloudReady, isNull);
      expect(health.state, ProviderHealthState.unknown);
    });
  });

  test('mock repository advertises identify support', () {
    expect(MockDeviceInventoryRepository().supportsIdentify, isTrue);
  });

  group('parseDeviceHealthState', () {
    test('known values map to their states', () {
      expect(parseDeviceHealthState('ONLINE'), DeviceHealthState.online);
      expect(parseDeviceHealthState('OFFLINE'), DeviceHealthState.offline);
      expect(parseDeviceHealthState('SLEEPING'), DeviceHealthState.sleeping);
      expect(
        parseDeviceHealthState('UNREACHABLE'),
        DeviceHealthState.unreachable,
      );
      expect(parseDeviceHealthState('AUTH_ERROR'), DeviceHealthState.authError);
    });

    test('unknown value fails safe to unknown', () {
      expect(parseDeviceHealthState('weird'), DeviceHealthState.unknown);
    });

    test('null fails safe to unknown', () {
      expect(parseDeviceHealthState(null), DeviceHealthState.unknown);
    });
  });

  group('needsConfiguration matrix', () {
    PhysicalDevice deviceWith(DeviceProvisioningState state) => PhysicalDevice(
      id: 'dev_test',
      name: 'Test',
      kind: DeviceKind.sensor,
      provider: 'Test',
      providerDeviceId: 'test-1',
      model: 'M1',
      provisioningState: state,
      online: true,
      health: DeviceHealthState.online,
      endpoints: const [],
    );

    test('discovered/enriched/partiallyConfigured need configuration', () {
      expect(
        deviceWith(DeviceProvisioningState.discovered).needsConfiguration,
        isTrue,
      );
      expect(
        deviceWith(DeviceProvisioningState.enriched).needsConfiguration,
        isTrue,
      );
      expect(
        deviceWith(
          DeviceProvisioningState.partiallyConfigured,
        ).needsConfiguration,
        isTrue,
      );
    });

    test('configured/missing/disabled do not need configuration', () {
      expect(
        deviceWith(DeviceProvisioningState.configured).needsConfiguration,
        isFalse,
      );
      expect(
        deviceWith(DeviceProvisioningState.missing).needsConfiguration,
        isFalse,
      );
      expect(
        deviceWith(DeviceProvisioningState.disabled).needsConfiguration,
        isFalse,
      );
    });
  });

  group('snapshot partition', () {
    const gateway = PhysicalDevice(
      id: 'dev_gw',
      name: 'Gateway',
      kind: DeviceKind.gateway,
      provider: 'Test',
      providerDeviceId: 'gw-1',
      model: 'GW',
      provisioningState: DeviceProvisioningState.enriched,
      online: true,
      health: DeviceHealthState.online,
      isGateway: true,
      endpoints: [],
    );
    const switchController = PhysicalDevice(
      id: 'dev_sw',
      name: 'Switch',
      kind: DeviceKind.switchController,
      provider: 'Test',
      providerDeviceId: 'sw-1',
      model: 'SW',
      provisioningState: DeviceProvisioningState.enriched,
      online: true,
      health: DeviceHealthState.online,
      endpoints: [],
    );
    const sensor = PhysicalDevice(
      id: 'dev_sensor',
      name: 'Sensor',
      kind: DeviceKind.sensor,
      provider: 'Test',
      providerDeviceId: 's-1',
      model: 'S',
      physicalAreaId: 'pasillo',
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.online,
      endpoints: [],
    );

    test('unassigned excludes gateway and configured devices', () {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [gateway, switchController, sensor],
        gateways: const [],
        lastDiscoveryLabel: 'Ahora',
      );

      final unassignedIds = snapshot.unassigned.map((d) => d.id).toList();
      expect(unassignedIds, ['dev_sw']);
      expect(unassignedIds, isNot(contains('dev_gw')));
      expect(unassignedIds, isNot(contains('dev_sensor')));
    });

    test('userDevices excludes the gateway', () {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [gateway, switchController, sensor],
        gateways: const [],
        lastDiscoveryLabel: 'Ahora',
      );

      expect(snapshot.userDevices, hasLength(2));
      expect(snapshot.userDevices.map((d) => d.id), isNot(contains('dev_gw')));
    });

    test('devicesInArea still works for devices with a physical area', () {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [gateway, switchController, sensor],
        gateways: const [],
        lastDiscoveryLabel: 'Ahora',
      );

      final pasillo = snapshot
          .devicesInArea('pasillo')
          .map((d) => d.id)
          .toList();
      expect(pasillo, ['dev_sensor']);
    });
  });
}
