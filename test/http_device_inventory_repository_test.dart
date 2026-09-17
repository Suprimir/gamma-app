import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/data/http_device_inventory_repository.dart';

import 'fixtures/deviceplatform_fixtures.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient({
    Map<String, dynamic>? inventoryData,
    Map<String, dynamic>? healthData,
    List<Map<String, dynamic>>? areasData,
    this.inventoryError,
    this.healthError,
  }) : inventoryData = inventoryData ?? deviceplatformInventoryJson,
       healthData = healthData ?? deviceplatformHealthJson,
       areasData = areasData ?? _defaultAreas,
       super(baseUrl: 'http://fake');

  Map<String, dynamic> inventoryData;
  Map<String, dynamic> healthData;

  /// Canonical `/api/v1/areas` payload por defecto (antes derivado del
  /// catálogo legacy, hoy explícito: el repo ya no pide `/catalog`).
  static const _defaultAreas = <Map<String, dynamic>>[
    {'id': 'pasillo', 'name': 'pasillo', 'aliases': <String>[]},
    {'id': 'cocina', 'name': 'cocina', 'aliases': <String>[]},
    {'id': 'comedor', 'name': 'comedor', 'aliases': <String>[]},
    {'id': 'sala', 'name': 'sala', 'aliases': <String>[]},
    {'id': 'patio', 'name': 'patio', 'aliases': <String>[]},
  ];

  List<Map<String, dynamic>> areasData;

  ApiException? inventoryError;
  ApiException? healthError;
  int discoveryCalls = 0;

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    if (inventoryError != null) throw inventoryError!;
    return inventoryData;
  }

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async {
    if (healthError != null) throw healthError!;
    return healthData;
  }

  @override
  Future<List<Map<String, dynamic>>> areas() async => areasData;

  final deletedAreas = <String>[];
  Object? deleteError;

  @override
  Future<void> deleteArea(String areaId) async {
    deletedAreas.add(areaId);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Map<String, dynamic>> discoverDevices() async {
    discoveryCalls++;
    return deviceplatformDiscoveryJson;
  }

  @override
  Future<Map<String, dynamic>> updateDevicePhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    final dto = _deviceDto(deviceId);
    dto['physical_area_id'] = areaId;
    return dto;
  }

  @override
  Future<Map<String, dynamic>> updateEndpointControlledArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    final dto = _deviceDto(deviceId);
    final endpoints = (dto['endpoints'] as List)
        .cast<Map<String, dynamic>>()
        .map((endpoint) => Map<String, dynamic>.from(endpoint))
        .toList();
    endpoints.firstWhere(
      (endpoint) => endpoint['endpoint_id'] == endpointId,
    )['controlled_area_id'] = areaId;
    dto['endpoints'] = endpoints;
    return dto;
  }

  Map<String, dynamic> _deviceDto(String deviceId) {
    return Map<String, dynamic>.from(
      (deviceplatformInventoryJson['devices'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((device) => device['device_id'] == deviceId),
    );
  }

  // ---- DeviceCommandRepository surface fakes ----

  final actionCalls = <Map<String, Object?>>[];
  Map<String, dynamic>? endpointActionData;
  ApiException? endpointActionError;

  @override
  Future<Map<String, dynamic>?> endpointAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object? value,
    String? requestId,
  }) async {
    actionCalls.add({
      'device_id': deviceId,
      'endpoint_id': endpointId,
      'action': action,
      'value': value,
      'request_id': requestId,
    });
    if (endpointActionError != null) throw endpointActionError!;
    return endpointActionData;
  }

  final identifyCalls = <String>[];
  Map<String, dynamic> identifyData = const {
    'supported': false,
    'reason': 'not supported',
  };

  @override
  Future<Map<String, dynamic>> identifyDevice(String deviceId) async {
    identifyCalls.add(deviceId);
    return identifyData;
  }

  final refreshCalls = <String>[];
  Map<String, dynamic>? refreshedDeviceData;

  @override
  Future<Map<String, dynamic>> refreshDevice(String deviceId) async {
    refreshCalls.add(deviceId);
    return refreshedDeviceData ?? _deviceDto(deviceId);
  }

  final stateRefreshCalls = <bool>[];

  @override
  Future<Map<String, dynamic>> refreshDeviceStates({
    bool includeOffline = false,
  }) async {
    stateRefreshCalls.add(includeOffline);
    return const {
      'scanned': 0,
      'refreshed': 0,
      'skipped_offline': 0,
      'duration_ms': 0,
    };
  }

  // ---- DeviceEventStreamRepository surface fakes ----

  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> events() => _eventsController.stream;

  /// Pushes one raw frame in the shape yielded by `ApiClient.events()`.
  void emitEvent(String name, Map<String, dynamic> data) {
    _eventsController.add({'event': name, 'data': data});
  }

  Future<void> closeEvents() => _eventsController.close();

  final bindCalls = <Map<String, Object?>>[];
  final unbindCalls = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  }) async {
    bindCalls.add({
      'device_id': deviceId,
      'endpoint_id': endpointId,
      'entity_id': entityId,
      'capability': capability,
      'controlled_area_id': controlledAreaId,
    });
    final dto = _deviceDto(deviceId);
    final endpoints = (dto['endpoints'] as List)
        .cast<Map<String, dynamic>>()
        .map((endpoint) => Map<String, dynamic>.from(endpoint))
        .toList();
    endpoints
        .firstWhere((endpoint) => endpoint['endpoint_id'] == endpointId)
        .addAll({'binding_id': 'b_$entityId', 'binding_entity': entityId});
    dto['endpoints'] = endpoints;
    return dto;
  }

  @override
  Future<Map<String, dynamic>> unbindEntity(
    String deviceId,
    String bindingId,
  ) async {
    unbindCalls.add({'device_id': deviceId, 'binding_id': bindingId});
    final dto = _deviceDto(deviceId);
    final endpoints = (dto['endpoints'] as List)
        .cast<Map<String, dynamic>>()
        .map((endpoint) => Map<String, dynamic>.from(endpoint))
        .toList();
    for (final endpoint in endpoints) {
      if (endpoint['binding_id'] == bindingId) {
        endpoint['binding_id'] = null;
        endpoint['binding_entity'] = null;
      }
    }
    dto['endpoints'] = endpoints;
    return dto;
  }
}

Map<String, dynamic> inventoryWith(Map<String, dynamic> device) {
  return {
    'devices': [device],
  };
}

Map<String, dynamic> deviceMap({
  required String id,
  String provisioningState = 'ENRICHED',
  Map<String, dynamic>? fields,
}) {
  return {
    'device_id': id,
    'provider_id': 'tuya',
    'display_name': 'Device $id',
    'physical_area_id': null,
    'parent_device_id': null,
    'is_subdevice': false,
    'is_gateway': false,
    'provisioning_state': provisioningState,
    'endpoints': <Map<String, dynamic>>[],
    ...?fields,
  };
}

void main() {
  f2cDeleteRepoTests();

  group('HttpDeviceInventoryRepository', () {
    test('load maps 6 records: 5 user devices + 1 gateway', () async {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());
      final snapshot = await repository.load();

      expect(snapshot.devices, hasLength(6));
      expect(snapshot.userDevices, hasLength(5));

      final gateway = snapshot.devices.firstWhere(
        (device) => device.id == 'gateway_1',
      );
      expect(gateway.kind, DeviceKind.gateway);
      expect(
        snapshot.unassigned.map((device) => device.id),
        isNot(contains('gateway_1')),
      );
    });

    test(
      'pending partition excludes the configured child and the gateway',
      () async {
        final repository = HttpDeviceInventoryRepository(FakeApiClient());
        final snapshot = await repository.load();

        final unassigned = snapshot.unassigned
            .map((device) => device.id)
            .toList();
        expect(unassigned, ['device_1', 'child_1', 'child_2', 'child_3']);
        expect(unassigned, isNot(contains('child_4')));
        expect(unassigned, isNot(contains('gateway_1')));
      },
    );

    test('3-gang device keeps its three canonical POWER endpoints', () async {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());
      final snapshot = await repository.load();

      final device = snapshot.devices.firstWhere((d) => d.id == 'device_1');
      expect(device.endpoints.map((endpoint) => endpoint.id), [
        'relay_1',
        'relay_2',
        'relay_3',
      ]);
      expect(
        device.endpoints.every(
          (endpoint) => endpoint.capabilities.contains('POWER'),
        ),
        isTrue,
      );
    });

    test('unknown capability is preserved without enabling anything', () async {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());
      final snapshot = await repository.load();

      final child = snapshot.devices.firstWhere((d) => d.id == 'child_4');
      final endpoint = child.endpoints.single;
      expect(endpoint.capabilities, containsAll(['POWER', 'SOMETHING_NEW']));
    });

    test('ENRICHED parses as enriched', () async {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());
      final snapshot = await repository.load();

      final device = snapshot.devices.firstWhere((d) => d.id == 'device_1');
      expect(device.provisioningState, DeviceProvisioningState.enriched);
    });

    test(
      'gateway partition lists children and reads lan_ready health',
      () async {
        final repository = HttpDeviceInventoryRepository(FakeApiClient());
        final snapshot = await repository.load();

        final gateway = snapshot.gateways.single;
        expect(gateway.id, 'gateway_1');
        expect(gateway.childDeviceIds, [
          'child_1',
          'child_2',
          'child_3',
          'child_4',
        ]);
        // Provider lanReady describes the Tuya integration, NOT the physical
        // gateway: before LAN validation the honest gateway health is unknown.
        expect(gateway.health, DeviceHealthState.unknown);
      },
    );

    test('areas come from the canonical endpoint', () async {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());
      final snapshot = await repository.load();

      expect(
        snapshot.areas.map((area) => area.id),
        containsAll(['pasillo', 'cocina', 'comedor', 'sala', 'patio']),
      );
    });

    test('AREA-AUTH-01: canonical non-empty areas are authoritative', () async {
      final fake = FakeApiClient(
        areasData: [
          {'id': 'area_1', 'name': 'Sala', 'aliases': const <String>[]},
        ],
      );
      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.areas.map((area) => area.id), ['area_1']);
      expect(snapshot.areas.single.name, 'Sala');
    });

    test(
      'AREA-AUTH-02: canonical empty areas stay empty (no legacy fallback)',
      () async {
        // The canonical endpoint succeeds and returns []; the legacy catalog
        // still has locations. The canonical empty set must remain [].
        final fake = FakeApiClient(areasData: const []);
        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        expect(snapshot.areas, isEmpty);
        expect(
          snapshot.areas.map((area) => area.name),
          isNot(contains('Sala legacy')),
        );
        expect(
          snapshot.areas.map((area) => area.name),
          isNot(contains('Cocina legacy')),
        );
      },
    );

    test('AREA-AUTH-05: valid canonical area behavior is unchanged', () async {
      final fake = FakeApiClient(
        areasData: [
          {'id': 'area_1', 'name': 'Sala', 'aliases': const <String>[]},
          {'id': 'area_2', 'name': 'Cocina', 'aliases': const <String>[]},
        ],
      );
      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.areas.map((area) => area.name), ['Sala', 'Cocina']);
    });

    test('missing device_id throws DeviceDtoException', () async {
      final fake = FakeApiClient(
        inventoryData: {
          'devices': [
            {'display_name': 'x'},
          ],
        },
      );

      await expectLater(
        HttpDeviceInventoryRepository(fake).load(),
        throwsA(isA<DeviceDtoException>()),
      );
    });

    test('unknown provisioning state throws DeviceDtoException', () async {
      final fake = FakeApiClient(
        inventoryData: {
          'devices': [
            {'device_id': 'x', 'provisioning_state': 'WEIRD', 'endpoints': []},
          ],
        },
      );

      await expectLater(
        HttpDeviceInventoryRepository(fake).load(),
        throwsA(isA<DeviceDtoException>()),
      );
    });

    test('endpoints of the wrong type throw DeviceDtoException', () async {
      final fake = FakeApiClient(
        inventoryData: {
          'devices': [
            {
              'device_id': 'x',
              'provisioning_state': 'ENRICHED',
              'endpoints': 'nope',
            },
          ],
        },
      );

      await expectLater(
        HttpDeviceInventoryRepository(fake).load(),
        throwsA(isA<DeviceDtoException>()),
      );
    });

    test('503 persistence errors propagate from load', () async {
      final fake = FakeApiClient(
        healthError: ApiException(503, {'detail': 'persistence unavailable'}),
      );

      await expectLater(
        HttpDeviceInventoryRepository(fake).load(),
        throwsA(
          isA<ApiException>().having((error) => error.statusCode, 'code', 503),
        ),
      );
    });

    test(
      'discover triggers discovery and refetches a fresh snapshot',
      () async {
        final fake = FakeApiClient();
        final repository = HttpDeviceInventoryRepository(fake);

        final snapshot = await repository.discover();

        expect(fake.discoveryCalls, 1);
        expect(snapshot.devices, isNotEmpty);
      },
    );

    test('assignPhysicalArea returns the canonical device and keeps cache '
        'consistent', () async {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());
      await repository.load();

      final device = await repository.assignPhysicalArea('device_1', 'sala');

      expect(device.id, 'device_1');
      expect(device.physicalAreaId, 'sala');

      final reloaded = await repository.load();
      expect(reloaded.devices, hasLength(6));
    });

    test(
      'assignEndpointArea clears controlled_area_id when area is null',
      () async {
        final repository = HttpDeviceInventoryRepository(FakeApiClient());
        await repository.load();

        final device = await repository.assignEndpointArea(
          'child_4',
          'light',
          null,
        );

        expect(device.endpoints.single.controlledAreaId, isNull);
      },
    );

    test('identify is unsupported on the HTTP repository', () {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());

      expect(repository.supportsIdentify, isFalse);
      expect(
        () => repository.identify('device_1'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'the HTTP repository opts into the bulk state sweep and forwards it',
      () async {
        final fake = FakeApiClient();
        final repository = HttpDeviceInventoryRepository(fake);

        // Production wiring: the controller detects the sweep surface here.
        expect(asDeviceStateRefreshRepository(repository), isNotNull);

        await repository.refreshDeviceStates();
        await repository.refreshDeviceStates();

        expect(fake.stateRefreshCalls, [false, false]);
      },
    );

    test(
      'the HTTP repository opts into the event stream surface and forwards it',
      () async {
        final fake = FakeApiClient();
        final repository = HttpDeviceInventoryRepository(fake);
        addTearDown(fake.closeEvents);

        // Production wiring: the controller detects the live-update surface
        // here, exactly like the bulk state sweep.
        expect(asDeviceEventStreamRepository(repository), isNotNull);

        final frames = <Map<String, dynamic>>[];
        final subscription = repository.deviceEvents().listen(frames.add);
        fake.emitEvent('devices_state_updated', {
          'at': '2026-09-13T00:00:00Z',
          'refreshed': 2,
          'scanned': 4,
        });
        await pumpEventQueue();
        await subscription.cancel();

        expect(frames.single['event'], 'devices_state_updated');
        expect((frames.single['data'] as Map)['refreshed'], 2);
      },
    );

    test('no fallback to mock when every call fails', () async {
      final fake = FakeApiClient(
        inventoryError: ApiException(500, {'detail': 'boom'}),
        healthError: ApiException(500, {'detail': 'boom'}),
      );

      await expectLater(
        HttpDeviceInventoryRepository(fake).load(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('final gate — DTO mapping', () {
    test(
      'is_gateway true parses as gateway and lands in snapshot.gateways',
      () async {
        final fake = FakeApiClient(
          inventoryData: inventoryWith(
            deviceMap(id: 'gateway_x', fields: {'is_gateway': true}),
          ),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        final gateway = snapshot.devices.single;
        expect(gateway.isGateway, isTrue);
        expect(gateway.kind, DeviceKind.gateway);
        expect(snapshot.gateways, hasLength(1));
        expect(snapshot.gateways.single.id, 'gateway_x');
      },
    );

    test(
      'is_gateway false parses as a non-gateway and stays out of gateways',
      () async {
        final fake = FakeApiClient(
          inventoryData: inventoryWith(
            deviceMap(id: 'device_x', fields: {'is_gateway': false}),
          ),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        expect(snapshot.devices.single.isGateway, isFalse);
        expect(snapshot.gateways, isEmpty);
      },
    );

    test(
      'missing is_gateway defaults to false for backward compatibility',
      () async {
        final source = (deviceplatformInventoryCloudOnlyJson['devices'] as List)
            .firstWhere((device) => device['device_id'] == 'device_1');
        final device = Map<String, dynamic>.from(source as Map)
          ..remove('is_gateway');
        final fake = FakeApiClient(inventoryData: inventoryWith(device));

        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        expect(snapshot.devices.single.isGateway, isFalse);
        expect(snapshot.gateways, isEmpty);
      },
    );

    test('malformed is_gateway throws DeviceDtoException for that field', () {
      final map = deviceMap(id: 'device_x', fields: {'is_gateway': 'yes'});

      DeviceDtoException? caught;
      try {
        parsePhysicalDevice(map, gatewayIds: const {});
      } on DeviceDtoException catch (error) {
        caught = error;
      }

      expect(caught, isNotNull);
      expect(caught!.field, 'is_gateway');
    });

    test(
      'cloud-only child is valid: is_subdevice true with a null parent',
      () async {
        final fake = FakeApiClient(
          inventoryData: inventoryWith(
            deviceMap(
              id: 'child_x',
              fields: {'is_subdevice': true, 'parent_device_id': null},
            ),
          ),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        final child = snapshot.devices.single;
        expect(child.isSubdevice, isTrue);
        expect(child.parentDeviceId, isNull);
        expect(child.isGateway, isFalse);
        expect(
          snapshot.userDevices.map((device) => device.id),
          contains('child_x'),
        );
        expect(snapshot.gateways, isEmpty);
      },
    );

    test('resolved child parses its parent_device_id', () async {
      final fake = FakeApiClient(
        inventoryData: inventoryWith(
          deviceMap(
            id: 'child_x',
            fields: {'is_subdevice': true, 'parent_device_id': 'gateway_1'},
          ),
        ),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.devices.single.parentDeviceId, 'gateway_1');
    });

    test('malformed is_subdevice throws DeviceDtoException for that field', () {
      final map = deviceMap(id: 'device_x', fields: {'is_subdevice': 42});

      DeviceDtoException? caught;
      try {
        parsePhysicalDevice(map, gatewayIds: const {});
      } on DeviceDtoException catch (error) {
        caught = error;
      }

      expect(caught, isNotNull);
      expect(caught!.field, 'is_subdevice');
    });

    test('has_key/pending_key true/false parse as bools', () {
      final map = deviceMap(
        id: 'device_x',
        fields: {'has_key': true, 'pending_key': false},
      );

      final device = parsePhysicalDevice(map, gatewayIds: const {});

      expect(device.hasKey, isTrue);
      expect(device.pendingKey, isFalse);
    });

    test('missing has_key/pending_key stay unknown (null)', () {
      final device = parsePhysicalDevice(
        deviceMap(id: 'device_x'),
        gatewayIds: const {},
      );

      expect(device.hasKey, isNull);
      expect(device.pendingKey, isNull);
    });

    test('malformed has_key throws DeviceDtoException for that field', () {
      final map = deviceMap(id: 'device_x', fields: {'has_key': 'yes'});

      DeviceDtoException? caught;
      try {
        parsePhysicalDevice(map, gatewayIds: const {});
      } on DeviceDtoException catch (error) {
        caught = error;
      }

      expect(caught, isNotNull);
      expect(caught!.field, 'has_key');
    });

    test(
      'DeviceDtoException through load carries the malformed device id',
      () async {
        final fake = FakeApiClient(
          inventoryData: {
            'devices': [
              {'device_id': 'bad_1', 'display_name': 'Malformed'},
              {
                'device_id': 'ok_1',
                'display_name': 'OK',
                'provisioning_state': 'ENRICHED',
                'endpoints': <Map<String, dynamic>>[],
              },
            ],
          },
        );

        DeviceDtoException? caught;
        try {
          await HttpDeviceInventoryRepository(fake).load();
        } on DeviceDtoException catch (error) {
          caught = error;
        }

        expect(caught, isNotNull);
        final error = caught as DeviceDtoException;
        expect(error.deviceId, 'bad_1');
        expect(error.field, 'provisioning_state');
      },
    );
  });

  group('final gate — device online tri-state', () {
    test('online true parses as health online and reachable', () async {
      final fake = FakeApiClient(
        inventoryData: inventoryWith(
          deviceMap(id: 'device_x', fields: {'online': true}),
        ),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      final device = snapshot.devices.single;
      expect(device.health, DeviceHealthState.online);
      expect(device.online, isTrue);
    });

    test('online false parses as health offline and not reachable', () async {
      final fake = FakeApiClient(
        inventoryData: inventoryWith(
          deviceMap(id: 'device_x', fields: {'online': false}),
        ),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      final device = snapshot.devices.single;
      expect(device.health, DeviceHealthState.offline);
      expect(device.online, isFalse);
    });

    test('online null stays unknown instead of collapsing to offline', () async {
      final fake = FakeApiClient(
        inventoryData: inventoryWith(
          deviceMap(id: 'device_x', fields: {'online': null}),
        ),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      final device = snapshot.devices.single;
      expect(device.health, DeviceHealthState.unknown);
      expect(device.online, isFalse);
    });

    test('absent online stays unknown for backward compatibility', () async {
      final fake = FakeApiClient(
        inventoryData: inventoryWith(deviceMap(id: 'device_x')),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      final device = snapshot.devices.single;
      expect(device.health, DeviceHealthState.unknown);
      expect(device.online, isFalse);
    });
  });

  group('final gate — Cloud-only and resolved partition', () {
    test('cloud-only 6 records partition into 5 users + 1 gateway', () async {
      final fake = FakeApiClient(
        inventoryData: Map.from(deviceplatformInventoryCloudOnlyJson),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.devices, hasLength(6));
      expect(snapshot.userDevices, hasLength(5));
      expect(snapshot.gateways, hasLength(1));
      expect(snapshot.gateways.single.id, 'gateway_1');
      final gateway = snapshot.devices.firstWhere(
        (device) => device.id == 'gateway_1',
      );
      expect(gateway.kind, DeviceKind.gateway);
      final userIds = snapshot.userDevices.map((device) => device.id).toSet();
      expect(
        userIds,
        containsAll(['device_1', 'child_1', 'child_2', 'child_3', 'child_4']),
      );
    });

    test(
      'cloud-only gateway stays out of unassigned despite ENRICHED state',
      () async {
        final fake = FakeApiClient(
          inventoryData: Map.from(deviceplatformInventoryCloudOnlyJson),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        expect(
          snapshot.unassigned.map((device) => device.id),
          isNot(contains('gateway_1')),
        );
      },
    );

    test(
      'cloud-only pending count is 4 because child_4 is CONFIGURED',
      () async {
        final fake = FakeApiClient(
          inventoryData: Map.from(deviceplatformInventoryCloudOnlyJson),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();

        expect(snapshot.unassigned.map((device) => device.id).toSet(), {
          'device_1',
          'child_1',
          'child_2',
          'child_3',
        });
      },
    );

    test('all-five-pending variant counts 5 in unassigned', () async {
      final devices = (deviceplatformInventoryCloudOnlyJson['devices'] as List)
          .map((device) => Map<String, dynamic>.from(device as Map))
          .toList();
      devices.firstWhere(
        (device) => device['device_id'] == 'child_4',
      )['provisioning_state'] = 'ENRICHED';
      final fake = FakeApiClient(inventoryData: {'devices': devices});

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.unassigned, hasLength(5));
      expect(
        snapshot.unassigned.map((device) => device.id),
        contains('child_4'),
      );
    });

    test('resolved topology keeps the same partition as Cloud-only', () async {
      final fake = FakeApiClient(
        inventoryData: Map.from(deviceplatformInventoryResolvedJson),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.userDevices, hasLength(5));
      expect(snapshot.gateways, hasLength(1));
      expect(snapshot.gateways.single.childDeviceIds, [
        'child_1',
        'child_2',
        'child_3',
        'child_4',
      ]);
    });

    test('resolved child remains a user device', () async {
      final fake = FakeApiClient(
        inventoryData: Map.from(deviceplatformInventoryResolvedJson),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      final child = snapshot.devices.firstWhere(
        (device) => device.id == 'child_1',
      );
      expect(child.isGateway, isFalse);
      expect(
        snapshot.userDevices.map((device) => device.id),
        contains('child_1'),
      );
    });
  });

  group('final gate — gateway health truthfulness', () {
    test('provider healthy but gateway stays unknown', () async {
      final fake = FakeApiClient();
      final repository = HttpDeviceInventoryRepository(fake);

      final snapshot = await repository.load();

      final providerHealth = ProviderHealth.fromJson(
        fake.healthData['tuya'] as Map<String, dynamic>,
      );
      expect(providerHealth.lanReady, isTrue);

      final gateway = snapshot.gateways.single;
      expect(gateway.health, DeviceHealthState.unknown);
      expect(gateway.health, isNot(DeviceHealthState.online));
    });

    test('provider degraded but gateway still unknown', () async {
      final fake = FakeApiClient(
        healthData: {
          'tuya': {
            'provider_id': 'tuya',
            'lan_ready': false,
            'cloud_ready': false,
            'status': 'CLOUD_NOT_CONFIGURED',
            'detail': null,
          },
        },
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();

      expect(snapshot.gateways.single.health, DeviceHealthState.unknown);
    });
  });

  group('device command surface', () {
    test(
      'observed_state fills observedPower/Quality/At on endpoints',
      () async {
        final fake = FakeApiClient(
          inventoryData: inventoryWith(
            deviceMap(
              id: 'device_x',
              fields: {
                'endpoints': <Map<String, dynamic>>[
                  {
                    'endpoint_id': 'relay_1',
                    'display_name': 'Canal 1',
                    'observed_state': <String, dynamic>{
                      'power': true,
                      'quality': 'confirmed',
                      'observed_at': '2026-09-11T12:00:00Z',
                    },
                  },
                ],
              },
            ),
          ),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();
        final endpoint = snapshot.devices.single.endpoints.single;

        expect(endpoint.observedPower, isTrue);
        expect(endpoint.observedQuality, 'confirmed');
        expect(endpoint.observedAt, '2026-09-11T12:00:00Z');
      },
    );

    test('null or malformed observed_state degrades to null fields', () async {
      final fake = FakeApiClient(
        inventoryData: inventoryWith(
          deviceMap(
            id: 'device_x',
            fields: {
              'endpoints': <Map<String, dynamic>>[
                {'endpoint_id': 'relay_1', 'display_name': 'Canal 1'},
                {
                  'endpoint_id': 'relay_2',
                  'display_name': 'Canal 2',
                  'observed_state': <String, dynamic>{
                    'power': 'yes',
                    'quality': '',
                    'observed_at': 42,
                  },
                },
                {
                  'endpoint_id': 'relay_3',
                  'display_name': 'Canal 3',
                  'observed_state': null,
                },
              ],
            },
          ),
        ),
      );

      final snapshot = await HttpDeviceInventoryRepository(fake).load();
      final endpoints = snapshot.devices.single.endpoints;

      expect(endpoints, hasLength(3));
      for (final endpoint in endpoints) {
        expect(endpoint.observedPower, isNull);
        expect(endpoint.observedQuality, isNull);
        expect(endpoint.observedAt, isNull);
      }
    });

    test('asDeviceCommandRepository narrows only command repositories', () {
      final repository = HttpDeviceInventoryRepository(FakeApiClient());

      expect(asDeviceCommandRepository(repository), same(repository));
      expect(
        asDeviceCommandRepository(MockDeviceInventoryRepository()),
        isNull,
      );
    });

    test(
      'setEndpointPower maps the typed outcome and observed state',
      () async {
        final fake = FakeApiClient()
          ..endpointActionData = {
            'outcome': 'SUCCESS',
            'changed': true,
            'observed_state': {
              'power': true,
              'quality': 'confirmed',
              'observed_at': '2026-09-11T12:00:00Z',
            },
            'error_code': null,
            'error_detail': null,
          };
        final repository = HttpDeviceInventoryRepository(fake);

        final result = await repository.setEndpointPower(
          'device_1',
          'relay_1',
          true,
        );

        expect(result.outcome, 'SUCCESS');
        expect(result.changed, isTrue);
        expect(result.observedPower, isTrue);
        expect(result.observedQuality, 'confirmed');
        expect(result.observedAt, '2026-09-11T12:00:00Z');
        expect(result.errorCode, isNull);
        expect(result.errorDetail, isNull);
        expect(result.responseParsed, isTrue);
        expect(fake.actionCalls.single, {
          'device_id': 'device_1',
          'endpoint_id': 'relay_1',
          'action': 'set_power',
          'value': true,
          'request_id': null,
        });
      },
    );

    test(
      'setEndpointPower reports unconfirmed when the body is null',
      () async {
        final fake = FakeApiClient();
        final repository = HttpDeviceInventoryRepository(fake);

        final result = await repository.setEndpointPower(
          'device_1',
          'relay_1',
          false,
        );

        expect(result.outcome, 'unconfirmed');
        expect(result.responseParsed, isFalse);
        expect(result.changed, isNull);
        expect(result.observedPower, isNull);
        expect(result.observedQuality, isNull);
        expect(fake.actionCalls.single['value'], false);
      },
    );

    test('setEndpointPower propagates ApiException untouched', () async {
      final fake = FakeApiClient()
        ..endpointActionError = ApiException(422, {'detail': 'unknown_action'});
      final repository = HttpDeviceInventoryRepository(fake);

      await expectLater(
        repository.setEndpointPower('device_1', 'relay_1', true),
        throwsA(
          isA<ApiException>().having((error) => error.statusCode, 'code', 422),
        ),
      );
    });

    test(
      'capability descriptors and per-capability observations parse',
      () async {
        final fake = FakeApiClient(
          inventoryData: inventoryWith(
            deviceMap(
              id: 'device_x',
              fields: {
                'endpoints': <Map<String, dynamic>>[
                  {
                    'endpoint_id': 'main',
                    'display_name': 'Principal',
                    'capabilities': <Map<String, dynamic>>[
                      {
                        'capability': 'BRIGHTNESS',
                        'readable': true,
                        'writable': true,
                        'range': [0, 100],
                        'enum_values': null,
                        'confidence': 0.9,
                      },
                      {
                        'capability': 'MODE',
                        'readable': true,
                        'writable': true,
                        'enum_values': ['auto', 'manual'],
                      },
                      // No capability name: malformed and skipped.
                      {'readable': true},
                    ],
                    'observed_state': <String, dynamic>{
                      'power': true,
                      'quality': 'confirmed',
                      'observed_at': '2026-09-11T12:00:00Z',
                      'capabilities': <String, dynamic>{
                        'BRIGHTNESS': {
                          'value': 80,
                          'quality': 'confirmed',
                          'observed_at': '2026-09-11T13:00:00Z',
                        },
                        'MODE': {'value': 'manual', 'quality': 'confirmed'},
                        'GHOST': 'nope',
                      },
                    },
                  },
                ],
              },
            ),
          ),
        );

        final snapshot = await HttpDeviceInventoryRepository(fake).load();
        final endpoint = snapshot.devices.single.endpoints.single;

        expect(endpoint.capabilities, {'BRIGHTNESS', 'MODE'});
        expect(endpoint.capabilityDetails['BRIGHTNESS']!.range, [0.0, 100.0]);
        expect(endpoint.capabilityDetails['BRIGHTNESS']!.writable, isTrue);
        expect(endpoint.capabilityDetails['BRIGHTNESS']!.confidence, 0.9);
        expect(endpoint.capabilityDetails['MODE']!.enumValues, [
          'auto',
          'manual',
        ]);
        expect(endpoint.observedCapabilities, hasLength(2));
        expect(endpoint.observedCapabilities['BRIGHTNESS']!.value, 80);
        expect(
          endpoint.observedCapabilities['BRIGHTNESS']!.observedAt,
          '2026-09-11T13:00:00Z',
        );
        expect(endpoint.observedCapabilities['MODE']!.value, 'manual');
        expect(endpoint.observedCapabilities.containsKey('GHOST'), isFalse);
        expect(confirmedCapabilityValue(endpoint, 'BRIGHTNESS'), 80);
      },
    );

    test(
      'executeAction maps the typed outcome and per-capability observation',
      () async {
        final fake = FakeApiClient()
          ..endpointActionData = {
            'outcome': 'SUCCESS',
            'changed': true,
            'observed_state': {
              'power': true,
              'quality': 'confirmed',
              'observed_at': '2026-09-11T12:00:00Z',
              'capabilities': {
                'BRIGHTNESS': {
                  'value': 70,
                  'quality': 'confirmed',
                  'observed_at': '2026-09-11T12:01:00Z',
                },
              },
            },
            'error_code': null,
            'error_detail': null,
          };
        final repository = HttpDeviceInventoryRepository(fake);

        final result = await repository.executeAction(
          'device_1',
          'relay_1',
          action: 'set_brightness',
          value: 70,
        );

        expect(result.action, 'set_brightness');
        expect(result.capability, 'BRIGHTNESS');
        expect(result.outcome, 'SUCCESS');
        expect(result.changed, isTrue);
        expect(result.observedValue, 70);
        expect(result.observedQuality, 'confirmed');
        expect(result.observedAt, '2026-09-11T12:01:00Z');
        expect(result.errorCode, isNull);
        expect(result.errorDetail, isNull);
        expect(result.responseParsed, isTrue);
        expect(fake.actionCalls.single, {
          'device_id': 'device_1',
          'endpoint_id': 'relay_1',
          'action': 'set_brightness',
          'value': 70,
          'request_id': null,
        });
      },
    );

    test(
      'executeAction reports unconfirmed with the mapped capability when the '
      'body is null',
      () async {
        final fake = FakeApiClient();
        final repository = HttpDeviceInventoryRepository(fake);

        final result = await repository.executeAction(
          'device_1',
          'relay_1',
          action: 'set_mode',
          value: 'manual',
        );

        expect(result.capability, 'MODE');
        expect(result.outcome, 'unconfirmed');
        expect(result.responseParsed, isFalse);
        expect(result.changed, isNull);
        expect(result.observedValue, isNull);
        expect(result.observedQuality, isNull);
        expect(fake.actionCalls.single['value'], 'manual');
      },
    );

    test(
      'executeAction extracts the legacy top-level power observation',
      () async {
        final fake = FakeApiClient()
          ..endpointActionData = {
            'outcome': 'SUCCESS',
            'changed': true,
            'observed_state': {
              'power': true,
              'quality': 'confirmed',
              'observed_at': '2026-09-11T12:00:00Z',
            },
          };
        final repository = HttpDeviceInventoryRepository(fake);

        final result = await repository.executeAction(
          'device_1',
          'relay_1',
          action: 'set_power',
          value: true,
        );

        expect(result.capability, 'POWER');
        expect(result.observedValue, isTrue);
        expect(result.observedQuality, 'confirmed');
        expect(result.observedAt, '2026-09-11T12:00:00Z');
      },
    );

    test('executeAction propagates ApiException untouched', () async {
      final fake = FakeApiClient()
        ..endpointActionError = ApiException(422, {'detail': 'invalid_value'});
      final repository = HttpDeviceInventoryRepository(fake);

      await expectLater(
        repository.executeAction(
          'device_1',
          'relay_1',
          action: 'set_brightness',
          value: 150,
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'code', 422)
              .having(
                (error) => (error.body as Map)['detail'],
                'detail',
                'invalid_value',
              ),
        ),
      );
    });

    test('identifyDevice maps supported/reason from the API', () async {
      final fake = FakeApiClient()
        ..identifyData = {
          'supported': false,
          'reason': 'identify not supported by the simulated home',
        };
      final repository = HttpDeviceInventoryRepository(fake);

      final result = await repository.identifyDevice('device_1');

      expect(result.supported, isFalse);
      expect(result.reason, 'identify not supported by the simulated home');
      expect(fake.identifyCalls, ['device_1']);
    });

    test('bindEntity calls through and parses the returned device', () async {
      final fake = FakeApiClient();
      final repository = HttpDeviceInventoryRepository(fake);
      await repository.load();

      final device = await repository.bindEntity(
        'device_1',
        endpointId: 'relay_1',
        entityId: 'luz_sala',
        capability: 'POWER',
        controlledAreaId: 'sala',
      );

      expect(device.id, 'device_1');
      expect(fake.bindCalls.single, {
        'device_id': 'device_1',
        'endpoint_id': 'relay_1',
        'entity_id': 'luz_sala',
        'capability': 'POWER',
        'controlled_area_id': 'sala',
      });
      final endpoint = device.endpoints.firstWhere(
        (endpoint) => endpoint.id == 'relay_1',
      );
      expect(endpoint.bindings.single.targetEntityId, 'luz_sala');
    });

    test('unbindEntity calls through and clears the binding', () async {
      final fake = FakeApiClient();
      final repository = HttpDeviceInventoryRepository(fake);
      await repository.load();
      await repository.bindEntity(
        'device_1',
        endpointId: 'relay_1',
        entityId: 'luz_sala',
        capability: 'POWER',
      );

      final device = await repository.unbindEntity('device_1', 'b_luz_sala');

      expect(fake.unbindCalls.single, {
        'device_id': 'device_1',
        'binding_id': 'b_luz_sala',
      });
      final endpoint = device.endpoints.firstWhere(
        (endpoint) => endpoint.id == 'relay_1',
      );
      expect(endpoint.bindings, isEmpty);
    });

    test('refreshDevice returns the fresh DTO through the cache', () async {
      final fake = FakeApiClient(
        inventoryData: {
          'devices': [
            deviceMap(id: 'target_1'),
            deviceMap(
              id: 'child_x',
              fields: {'is_subdevice': true, 'parent_device_id': 'target_1'},
            ),
          ],
        },
      );
      final repository = HttpDeviceInventoryRepository(fake);
      await repository.load();

      // The refreshed DTO has no is_gateway flag; the cached child pointing to
      // target_1 must still route the mapping through the gateway partition.
      final dto = Map<String, dynamic>.from(
        (fake.inventoryData['devices'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((device) => device['device_id'] == 'target_1'),
      )..remove('is_gateway');
      fake.refreshedDeviceData = dto;

      final device = await repository.refreshDevice('target_1');

      expect(fake.refreshCalls, ['target_1']);
      expect(device.id, 'target_1');
      expect(device.kind, DeviceKind.gateway);
    });
  });
}

void f2cDeleteRepoTests() {
  group('deleteArea repository', () {
    test('performs repository DELETE and clears cache', () async {
      final fake = FakeApiClient();
      final repository = HttpDeviceInventoryRepository(fake);
      await repository.deleteArea('area_SALA');
      expect(fake.deletedAreas, ['area_SALA']);
    });

    test('propagates 409 conflict', () async {
      final fake = FakeApiClient()
        ..deleteError = ApiException(409, {'detail': 'área en uso'});
      final repository = HttpDeviceInventoryRepository(fake);
      expect(
        () => repository.deleteArea('area_SALA'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
