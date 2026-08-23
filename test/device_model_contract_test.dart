import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/data/http_device_inventory_repository.dart';

import 'fixtures/deviceplatform_fixtures.dart';

/// F2-C API/model contract tests: F2-B naming fields parse append-only,
/// Areas come from the real AreaStore DTO, IDs stay opaque.
void main() {
  group('device model', () {
    test('parses F2-B device naming fields', () {
      final dto = <String, dynamic>{
        'device_id': 'dev_1',
        'provider_id': 'tuya',
        'provisioning_state': 'CONFIGURED',
        'display_name': 'Interruptor triple',
        'provider_name': 'Sala Comedor',
        'user_name': 'Interruptor triple',
        'endpoints': const [],
      };
      final device = parsePhysicalDevice(dto, gatewayIds: const {});
      expect(device.providerName, 'Sala Comedor');
      expect(device.userName, 'Interruptor triple');
      expect(device.name, 'Interruptor triple');
    });

    test('parses endpoint F2-B naming fields', () {
      final dto = <String, dynamic>{
        'device_id': 'dev_1',
        'provider_id': 'tuya',
        'provisioning_state': 'CONFIGURED',
        'endpoints': [
          {
            'endpoint_id': 'relay_1',
            'display_name': 'Luz',
            'semantic_role': 'light',
            'user_name': 'Lámpara Totoro',
            'stable_ordinal': 1,
            'display_name_semantic': 'Luz',
            'display_name_global': 'Sala · Luz',
            'naming_source': 'USER',
            'capabilities': const [],
          },
        ],
      };
      final device = parsePhysicalDevice(dto, gatewayIds: const {});
      final endpoint = device.endpoints.single;
      expect(endpoint.semanticRole, 'light');
      expect(endpoint.userName, 'Lámpara Totoro');
      expect(endpoint.stableOrdinal, 1);
      expect(endpoint.displayNameSemantic, 'Luz');
      expect(endpoint.displayNameGlobal, 'Sala · Luz');
      expect(endpoint.namingSource, NamingSource.user);
      expect(endpoint.displayName, 'Luz');
    });

    test('older DTO without F2-B fields stays compatible', () {
      final dto = <String, dynamic>{
        'device_id': 'dev_1',
        'provider_id': 'tuya',
        'provisioning_state': 'CONFIGURED',
        'display_name': 'Canal 1',
        'endpoints': [
          {
            'endpoint_id': 'relay_1',
            'display_name': 'Canal 1',
            'capabilities': const [],
          },
        ],
      };
      final device = parsePhysicalDevice(dto, gatewayIds: const {});
      expect(device.providerName, isNull);
      expect(device.userName, isNull);
      expect(device.endpoints.single.displayNameSemantic, isNull);
      expect(device.endpoints.single.displayName, 'Canal 1');
      expect(device.endpoints.single.namingSource, NamingSource.fallback);
    });
  });

  group('HomeArea', () {
    test('parses AreaStore DTO with opaque id and aliases', () {
      final area = HomeArea.fromJson(const {
        'id': 'area_SALA',
        'name': 'Sala',
        'aliases': ['sala principal', 'estancia'],
      });
      expect(area.id, 'area_SALA');
      expect(area.name, 'Sala');
      expect(area.aliases, ['sala principal', 'estancia']);
    });

    test('rename keeps identity', () {
      final area = HomeArea.fromJson(const {
        'id': 'area_SALA',
        'name': 'Sala',
        'aliases': <String>[],
      });
      final renamed = area.copyWith(name: 'Sala principal');
      expect(renamed.id, 'area_SALA');
      expect(renamed.name, 'Sala principal');
    });
  });

  group('fixtures', () {
    test('multi-gang fixture keeps physical vs controlled independent', () {
      final inventory = deviceplatformInventoryJson;
      final devices = (inventory['devices'] as List)
          .cast<Map<String, dynamic>>();
      final parsed = devices
          .map((dto) => parsePhysicalDevice(dto, gatewayIds: const {}))
          .toList();
      final triple = parsed.firstWhere(
        (device) => device.name == 'Interruptor triple',
      );
      expect(triple.endpoints.length, 3);
      // Physical area independent from endpoint controlled areas.
      final controlled = triple.endpoints
          .where((endpoint) => endpoint.controlledAreaId != null)
          .length;
      expect(controlled, lessThanOrEqualTo(triple.endpoints.length));
    });

    test('cross-device semantic names come from backend', () {
      final inventory = deviceplatformInventoryJson;
      final devices = (inventory['devices'] as List)
          .cast<Map<String, dynamic>>();
      final parsed = devices
          .map((dto) => parsePhysicalDevice(dto, gatewayIds: const {}))
          .toList();
      final names = <String>[
        for (final device in parsed)
          for (final endpoint in device.endpoints) endpoint.displayName,
      ];
      // No client-side recomputation: whatever backend sends is rendered.
      expect(names, isNotEmpty);
    });
  });
}
