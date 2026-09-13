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
    const offlineOutlet = PhysicalDevice(
      id: 'dev_offline',
      name: 'Enchufe',
      kind: DeviceKind.outlet,
      provider: 'Test',
      providerDeviceId: 'off-1',
      model: 'OFF',
      physicalAreaId: 'sala',
      provisioningState: DeviceProvisioningState.configured,
      online: false,
      health: DeviceHealthState.offline,
      endpoints: [],
    );
    const unreachableSensor = PhysicalDevice(
      id: 'dev_unreachable',
      name: 'Sensor lejano',
      kind: DeviceKind.sensor,
      provider: 'Test',
      providerDeviceId: 'un-1',
      model: 'UN',
      provisioningState: DeviceProvisioningState.configured,
      online: false,
      health: DeviceHealthState.unreachable,
      endpoints: [],
    );
    const offlinePending = PhysicalDevice(
      id: 'dev_offline_pending',
      name: 'Interruptor apagado',
      kind: DeviceKind.switchController,
      provider: 'Test',
      providerDeviceId: 'ofp-1',
      model: 'OFP',
      provisioningState: DeviceProvisioningState.enriched,
      online: false,
      health: DeviceHealthState.offline,
      endpoints: [],
    );
    const authErrorLight = PhysicalDevice(
      id: 'dev_auth_error',
      name: 'Luz',
      kind: DeviceKind.light,
      provider: 'Test',
      providerDeviceId: 'ae-1',
      model: 'AE',
      provisioningState: DeviceProvisioningState.configured,
      online: false,
      health: DeviceHealthState.authError,
      endpoints: [],
    );
    const sleepingLight = PhysicalDevice(
      id: 'dev_sleeping',
      name: 'Luz dormida',
      kind: DeviceKind.light,
      provider: 'Test',
      providerDeviceId: 'sl-1',
      model: 'SL',
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.sleeping,
      endpoints: [],
    );
    const unknownHealthLight = PhysicalDevice(
      id: 'dev_unknown',
      name: 'Luz sin datos',
      kind: DeviceKind.light,
      provider: 'Test',
      providerDeviceId: 'uk-1',
      model: 'UK',
      provisioningState: DeviceProvisioningState.configured,
      online: false,
      health: DeviceHealthState.unknown,
      endpoints: [],
    );
    const offlineGateway = PhysicalDevice(
      id: 'dev_gw_offline',
      name: 'Gateway apagado',
      kind: DeviceKind.gateway,
      provider: 'Test',
      providerDeviceId: 'gwo-1',
      model: 'GW',
      provisioningState: DeviceProvisioningState.configured,
      online: false,
      health: DeviceHealthState.offline,
      isGateway: true,
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

    test('unassigned never counts offline pending devices', () {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [switchController, offlinePending],
        gateways: const [],
        lastDiscoveryLabel: 'Ahora',
      );

      // The offline row lives in the offline surface, never in the pending
      // count; the online pending sibling still counts.
      expect(snapshot.unassigned.map((d) => d.id), ['dev_sw']);
      expect(
        snapshot.offlineDevices.map((d) => d.id),
        contains('dev_offline_pending'),
      );
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

    test('isOfflineDevice only flags known connectivity trouble', () {
      expect(DeviceInventorySnapshot.isOfflineDevice(offlineOutlet), isTrue);
      expect(
        DeviceInventorySnapshot.isOfflineDevice(unreachableSensor),
        isTrue,
      );
      expect(DeviceInventorySnapshot.isOfflineDevice(authErrorLight), isTrue);
      expect(DeviceInventorySnapshot.isOfflineDevice(sensor), isFalse);
      expect(DeviceInventorySnapshot.isOfflineDevice(sleepingLight), isFalse);
      expect(
        DeviceInventorySnapshot.isOfflineDevice(unknownHealthLight),
        isFalse,
      );
    });

    test('offlineDevices partitions user devices with trouble', () {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [
          gateway,
          switchController,
          sensor,
          offlineOutlet,
          unreachableSensor,
          authErrorLight,
          sleepingLight,
          unknownHealthLight,
          offlineGateway,
        ],
        gateways: const [],
        lastDiscoveryLabel: 'Ahora',
      );

      final ids = snapshot.offlineDevices.map((d) => d.id).toList();
      expect(ids, ['dev_offline', 'dev_unreachable', 'dev_auth_error']);
      expect(ids, isNot(contains('dev_gw_offline')));
    });

    test('activeDevices is the complement within userDevices', () {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [
          gateway,
          switchController,
          sensor,
          offlineOutlet,
          unreachableSensor,
          authErrorLight,
          sleepingLight,
          unknownHealthLight,
          offlineGateway,
        ],
        gateways: const [],
        lastDiscoveryLabel: 'Ahora',
      );

      expect(snapshot.activeDevices.map((d) => d.id), [
        'dev_sw',
        'dev_sensor',
        'dev_sleeping',
        'dev_unknown',
      ]);
      expect(snapshot.activeDevices, hasLength(snapshot.userDevices.length - 3));
    });
  });

  group('DeviceEndpoint observed state', () {
    const endpoint = DeviceEndpoint(
      id: 'relay_1',
      name: 'Canal 1',
      kind: DeviceKind.switchController,
      capabilities: {'POWER'},
    );

    test('defaults to null observed fields', () {
      expect(endpoint.observedPower, isNull);
      expect(endpoint.observedQuality, isNull);
      expect(endpoint.observedAt, isNull);
    });

    test('copyWith sets and clears observed fields', () {
      final observed = endpoint.copyWith(
        observedPower: true,
        observedQuality: 'confirmed',
        observedAt: '2026-09-11T12:00:00Z',
      );
      expect(observed.observedPower, isTrue);
      expect(observed.observedQuality, 'confirmed');
      expect(observed.observedAt, '2026-09-11T12:00:00Z');

      final cleared = observed.copyWith(observedPower: null);
      expect(cleared.observedPower, isNull);
      expect(cleared.observedQuality, 'confirmed');
      expect(cleared.id, 'relay_1');
    });
  });

  group('power endpoint helpers', () {
    const triple = PhysicalDevice(
      id: 'dev_triple',
      name: 'Triple',
      kind: DeviceKind.switchController,
      provider: 'Test',
      providerDeviceId: '',
      model: 'TS0013',
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.online,
      endpoints: [
        DeviceEndpoint(
          id: 'relay_1',
          name: 'Canal 1',
          kind: DeviceKind.switchController,
          capabilities: {'POWER'},
          observedPower: true,
          observedQuality: 'confirmed',
        ),
        DeviceEndpoint(
          id: 'relay_2',
          name: 'Canal 2',
          kind: DeviceKind.switchController,
          capabilities: {'on_off'},
          observedPower: false,
          observedQuality: 'confirmed',
        ),
        DeviceEndpoint(
          id: 'relay_3',
          name: 'Canal 3',
          kind: DeviceKind.switchController,
          capabilities: {'POWER'},
          observedQuality: 'confirmed',
        ),
        DeviceEndpoint(
          id: 'temperature',
          name: 'Temperatura',
          kind: DeviceKind.sensor,
          capabilities: {'TEMPERATURE'},
        ),
      ],
    );

    test('powerEndpoints keeps only power-capable endpoints', () {
      expect(powerEndpoints(triple).map((endpoint) => endpoint.id), [
        'relay_1',
        'relay_2',
        'relay_3',
      ]);
    });

    test('powerStateCounts reports (confirmedOn, total, unknown)', () {
      expect(powerStateCounts(triple), (1, 3, 1));
    });

    test('stale observations never count as confirmed', () {
      final stale = triple.copyWith(
        endpoints: [
          triple.endpoints.first.copyWith(observedQuality: 'stale'),
          ...triple.endpoints.skip(1),
        ],
      );

      expect(powerStateCounts(stale), (0, 3, 2));
    });

    test('devices without power endpoints report (0, 0, 0)', () {
      final sensor = triple.copyWith(endpoints: [triple.endpoints.last]);

      expect(powerEndpoints(sensor), isEmpty);
      expect(powerStateCounts(sensor), (0, 0, 0));
    });
  });

  group('PhysicalDevice credentials', () {
    const device = PhysicalDevice(
      id: 'dev_creds',
      name: 'Creds',
      kind: DeviceKind.light,
      provider: 'Test',
      providerDeviceId: '',
      model: 'X',
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.online,
      endpoints: [],
    );

    test('defaults hasKey/pendingKey to null', () {
      expect(device.hasKey, isNull);
      expect(device.pendingKey, isNull);
    });

    test('copyWith sets and clears hasKey/pendingKey', () {
      final set = device.copyWith(hasKey: true, pendingKey: false);
      expect(set.hasKey, isTrue);
      expect(set.pendingKey, isFalse);

      final cleared = set.copyWith(hasKey: null, pendingKey: null);
      expect(cleared.hasKey, isNull);
      expect(cleared.pendingKey, isNull);
    });
  });

  test('command result types carry the parsed facts', () {
    const power = EndpointPowerResult(
      outcome: 'SUCCESS',
      changed: true,
      observedPower: true,
    );
    expect(power.outcome, 'SUCCESS');
    expect(power.changed, isTrue);
    expect(power.responseParsed, isTrue);

    const unconfirmed = EndpointPowerResult(
      outcome: 'unconfirmed',
      responseParsed: false,
    );
    expect(unconfirmed.responseParsed, isFalse);
    expect(unconfirmed.changed, isNull);

    const identify = IdentifyResult(supported: false, reason: 'nope');
    expect(identify.supported, isFalse);
    expect(identify.reason, 'nope');

    const capability = CapabilityActionResult(
      action: 'set_brightness',
      capability: 'BRIGHTNESS',
      outcome: 'SUCCESS',
      changed: true,
      observedValue: 70,
      observedQuality: 'confirmed',
    );
    expect(capability.action, 'set_brightness');
    expect(capability.capability, 'BRIGHTNESS');
    expect(capability.observedValue, 70);
    expect(capability.responseParsed, isTrue);
  });

  group('DeviceCapability parsing', () {
    test('parses a complete descriptor', () {
      final capability = parseDeviceCapability(const {
        'capability': 'BRIGHTNESS',
        'readable': true,
        'writable': true,
        'range': [0, 100],
        'confidence': 0.9,
        'evidence': 'provider',
      });

      expect(capability, isNotNull);
      expect(capability!.name, 'BRIGHTNESS');
      expect(capability.readable, isTrue);
      expect(capability.writable, isTrue);
      expect(capability.range, [0.0, 100.0]);
      expect(capability.enumValues, isNull);
      expect(capability.confidence, 0.9);
    });

    test('parses enum values and degrades malformed metadata', () {
      final mode = parseDeviceCapability(const {
        'capability': 'MODE',
        'readable': true,
        'writable': true,
        'enum_values': ['auto', 'manual', 3],
        'range': [1],
        'confidence': 'high',
      });

      expect(mode!.enumValues, ['auto', 'manual']);
      expect(mode.range, isNull);
      expect(mode.confidence, isNull);
    });

    test('malformed entries return null instead of throwing', () {
      expect(parseDeviceCapability(null), isNull);
      expect(parseDeviceCapability('BRIGHTNESS'), isNull);
      expect(parseDeviceCapability(const {}), isNull);
      expect(parseDeviceCapability(const {'capability': '  '}), isNull);
      expect(parseDeviceCapability(const {'capability': 42}), isNull);
    });
  });

  group('EndpointCapabilityObservation parsing', () {
    test('parses values/quality/at and skips malformed entries', () {
      final parsed = parseObservedCapabilities(const {
        'BRIGHTNESS': {
          'value': 80,
          'quality': 'confirmed',
          'observed_at': '2026-09-11T12:00:00Z',
        },
        'MODE': {'value': 'manual', 'quality': 'stale'},
        'COLOR': {'value': '#FFAA00'},
        'POWER': {'value': true, 'quality': ''},
        'BROKEN': 'nope',
        '': {'value': 1},
      });

      expect(parsed, hasLength(4));
      expect(parsed['BRIGHTNESS']!.value, 80);
      expect(parsed['BRIGHTNESS']!.quality, 'confirmed');
      expect(parsed['BRIGHTNESS']!.observedAt, '2026-09-11T12:00:00Z');
      expect(parsed['MODE']!.value, 'manual');
      expect(parsed['MODE']!.quality, 'stale');
      expect(parsed['COLOR']!.value, '#FFAA00');
      expect(parsed['COLOR']!.quality, isNull);
      expect(parsed['POWER']!.value, isTrue);
      expect(parsed['POWER']!.quality, isNull);
      expect(parsed.containsKey('BROKEN'), isFalse);
      expect(parsed.containsKey(''), isFalse);
    });

    test('non-map input degrades to an empty map', () {
      expect(parseObservedCapabilities(null), isEmpty);
      expect(parseObservedCapabilities('nope'), isEmpty);
      expect(parseObservedCapabilities(const []), isEmpty);
    });
  });

  group('capability helpers', () {
    const endpoint = DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER', 'BRIGHTNESS', 'MODE'},
      capabilityDetails: {
        'BRIGHTNESS': DeviceCapability(
          name: 'BRIGHTNESS',
          readable: true,
          writable: true,
          range: [0, 100],
          confidence: 0.8,
        ),
        'MODE': DeviceCapability(
          name: 'MODE',
          readable: true,
          writable: false,
          enumValues: ['auto', 'manual'],
        ),
      },
      observedCapabilities: {
        'BRIGHTNESS': EndpointCapabilityObservation(
          value: 80,
          quality: 'confirmed',
          observedAt: 't1',
        ),
        'MODE': EndpointCapabilityObservation(value: 'auto', quality: 'stale'),
      },
    );

    test('confirmedCapabilityValue only returns confirmed values', () {
      expect(confirmedCapabilityValue(endpoint, 'BRIGHTNESS'), 80);
      expect(confirmedCapabilityValue(endpoint, 'MODE'), isNull);
      expect(confirmedCapabilityValue(endpoint, 'POWER'), isNull);
    });

    test('capabilityWritable prefers the descriptor over the legacy set', () {
      expect(capabilityWritable(endpoint, 'BRIGHTNESS'), isTrue);
      expect(capabilityWritable(endpoint, 'MODE'), isFalse);
      expect(capabilityWritable(endpoint, 'POWER'), isTrue);
      expect(capabilityWritable(endpoint, 'SPEED'), isFalse);
    });

    test('firstEndpointWithCapability resolves presence and writability', () {
      const device = PhysicalDevice(
        id: 'dev_1',
        name: 'Equipo',
        kind: DeviceKind.light,
        provider: 'Tuya',
        providerDeviceId: '',
        model: 'M1',
        provisioningState: DeviceProvisioningState.configured,
        online: true,
        health: DeviceHealthState.online,
        endpoints: [
          DeviceEndpoint(
            id: 'mode_blocked',
            name: 'Modo',
            kind: DeviceKind.unknown,
            capabilities: {'MODE'},
            capabilityDetails: {
              'MODE': DeviceCapability(
                name: 'MODE',
                readable: true,
                writable: false,
              ),
            },
          ),
          DeviceEndpoint(
            id: 'mode_writable',
            name: 'Modo 2',
            kind: DeviceKind.unknown,
            capabilities: {'MODE'},
            capabilityDetails: {
              'MODE': DeviceCapability(
                name: 'MODE',
                readable: true,
                writable: true,
              ),
            },
          ),
          DeviceEndpoint(
            id: 'legacy_power',
            name: 'Canal',
            kind: DeviceKind.switchController,
            capabilities: {'POWER'},
          ),
        ],
      );

      expect(firstEndpointWithCapability(device, 'MODE')!.id, 'mode_writable');
      expect(firstEndpointWithCapability(device, 'POWER')!.id, 'legacy_power');
      expect(firstEndpointWithCapability(device, 'SPEED'), isNull);
    });

    test('speed level and percent mapping round-trip', () {
      expect(speedLevelToPercent(1), 33);
      expect(speedLevelToPercent(2), 67);
      expect(speedLevelToPercent(3), 100);

      expect(percentToSpeedLevel(33), 1);
      expect(percentToSpeedLevel(67), 2);
      expect(percentToSpeedLevel(80), 2);
      expect(percentToSpeedLevel(100), 3);
      expect(percentToSpeedLevel(0), 1);
      expect(percentToSpeedLevel(150), 3);

      for (final level in [1, 2, 3]) {
        expect(percentToSpeedLevel(speedLevelToPercent(level)), level);
      }
    });

    test('copyWith preserves and replaces capability maps', () {
      final untouched = endpoint.copyWith();
      expect(untouched.capabilityDetails.keys, endpoint.capabilityDetails.keys);
      expect(untouched.observedCapabilities['BRIGHTNESS']!.value, 80);

      final replaced = endpoint.copyWith(
        capabilityDetails: const {},
        observedCapabilities: const {
          'MODE': EndpointCapabilityObservation(
            value: 'manual',
            quality: 'confirmed',
          ),
        },
      );
      expect(replaced.capabilityDetails, isEmpty);
      expect(replaced.observedCapabilities, hasLength(1));
      expect(confirmedCapabilityValue(replaced, 'MODE'), 'manual');
    });
  });
}
