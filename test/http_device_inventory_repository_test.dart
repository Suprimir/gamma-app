import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/data/http_device_inventory_repository.dart';

import 'fixtures/deviceplatform_fixtures.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient({
    Map<String, dynamic>? inventoryData,
    Map<String, dynamic>? catalogData,
    Map<String, dynamic>? healthData,
    this.areasData,
    this.inventoryError,
    this.catalogError,
    this.healthError,
  }) : inventoryData = inventoryData ?? deviceplatformInventoryJson,
       catalogData = catalogData ?? deviceplatformCatalogJson,
       healthData = healthData ?? deviceplatformHealthJson,
       super(baseUrl: 'http://fake');

  Map<String, dynamic> inventoryData;
  Map<String, dynamic> catalogData;
  Map<String, dynamic> healthData;

  /// Explicit canonical `/api/v1/areas` payload. When null, the fake derives
  /// areas from the catalog so pre-existing tests keep their behavior.
  List<Map<String, dynamic>>? areasData;

  ApiException? inventoryError;
  ApiException? catalogError;
  ApiException? healthError;
  int discoveryCalls = 0;

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    if (inventoryError != null) throw inventoryError!;
    return inventoryData;
  }

  @override
  Future<Map<String, dynamic>> catalog() async {
    if (catalogError != null) throw catalogError!;
    return catalogData;
  }

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async {
    if (healthError != null) throw healthError!;
    return healthData;
  }

  @override
  Future<List<Map<String, dynamic>>> areas() async {
    final explicit = areasData;
    if (explicit != null) return explicit;
    final raw = catalogData['locations'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (location) => {
            'id': location['id'] ?? location['name'],
            'name': location['name'],
            'aliases': const <String>[],
          },
        )
        .toList();
  }

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

    test('areas come from the legacy catalog', () async {
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

    test('no fallback to mock when every call fails', () async {
      final fake = FakeApiClient(
        inventoryError: ApiException(500, {'detail': 'boom'}),
        catalogError: ApiException(500, {'detail': 'boom'}),
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
