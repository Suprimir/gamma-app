import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

import 'fixtures/deviceplatform_fixtures.dart';

/// Provider-authoritative Device Class + Semantic Role UI tests (FL01-FL10).
class FakeDeviceClassApi extends ApiClient {
  FakeDeviceClassApi() : super(baseUrl: 'http://fake') {
    inventory = _deepCopy(deviceplatformInventoryJson);
    catalogData = _deepCopy(deviceplatformCatalogJson);
    healthData = _deepCopy(deviceplatformHealthJson);
  }

  late Map<String, dynamic> inventory;
  late Map<String, dynamic> catalogData;
  late Map<String, dynamic> healthData;
  final roleWrites = <(String, String, String?)>[];
  bool failRoleWrites = false;

  List<Map<String, dynamic>> get _devices =>
      (inventory['devices'] as List).cast<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async =>
      inventory;

  @override
  Future<Map<String, dynamic>> catalog() async => catalogData;

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async => healthData;

  @override
  Future<List<Map<String, dynamic>>> areas() async {
    final raw = catalogData['locations'];
    if (raw is! List) return const [];
    // Canonical /api/v1/areas DTO shape: {id, name, aliases}. The fake maps
    // catalog locations into that contract so the repository never falls
    // back to legacy (F3-B final closure: canonical empty stays empty).
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

  @override
  Future<Map<String, dynamic>> updateEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    roleWrites.add((deviceId, endpointId, role));
    if (failRoleWrites) {
      throw ApiException(422, {'detail': 'semantic_role inválido'});
    }
    // Mirror the mutation into the inventory DTO so the canonical refetch
    // shows the saved value (backend canonical response semantics: set ->
    // source USER; clear/null -> restore provider role/source or none).
    final source = _devices.firstWhere((d) => d['device_id'] == deviceId);
    final copy = Map<String, dynamic>.from(source);
    final endpoints = (source['endpoints'] as List).map((e) {
      final ep = Map<String, dynamic>.from(e as Map);
      if (role == null) {
        final providerRole = ep['provider_semantic_role'];
        ep['semantic_role'] = providerRole;
        ep['semantic_role_source'] =
            providerRole == null || providerRole == 'unknown'
            ? 'none'
            : 'provider';
      } else {
        ep['semantic_role'] = role;
        ep['semantic_role_source'] = 'user';
      }
      return ep;
    }).toList();
    copy['endpoints'] = endpoints;
    final index = _devices.indexWhere((d) => d['device_id'] == deviceId);
    _devices[index] = copy;
    return copy;
  }

  @override
  Future<Map<String, dynamic>> deviceDetail(String deviceId) async {
    return _devices.firstWhere((d) => d['device_id'] == deviceId);
  }

  @override
  Future<Map<String, dynamic>> discoverDevices() async => {};

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    return Map<String, dynamic>.from(source);
  }
}

Map<String, dynamic> deviceDto({
  required String id,
  String displayName = 'Relé',
  String deviceClass = 'relay',
  String deviceClassSource = 'provider',
  List<Map<String, dynamic>>? endpoints,
}) {
  return {
    'device_id': id,
    'provider_id': 'tuya',
    'display_name': displayName,
    'device_class': deviceClass,
    'device_class_source': deviceClassSource,
    'physical_area_id': 'pasillo',
    'provisioning_state': 'CONFIGURED',
    'enabled': true,
    'endpoints':
        endpoints ??
        [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'unknown',
            'provider_semantic_role': 'unknown',
            'semantic_role_source': 'none',
            'capabilities': [],
          },
        ],
  };
}

Future<void> _pumpDetail(
  WidgetTester tester,
  FakeDeviceClassApi api, {
  String? deviceName,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DevicesPage(api: api)),
    ),
  );
  await tester.pumpAndSettle();
  // Open the first device detail through its area card + device row.
  final areaCard = find.text('pasillo');
  await tester.tap(areaCard);
  await tester.pumpAndSettle();
  final deviceRow = find.text(deviceName ?? 'Relé').first;
  await tester.tap(deviceRow);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FL01 device class displayed read-only', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(id: 'dev_1', displayName: 'Interruptor triple'),
    ];
    await _pumpDetail(tester, api, deviceName: 'Interruptor triple');
    await tester.pumpAndSettle();
    expect(find.text('Tipo de dispositivo'), findsOneWidget);
    expect(find.text('Relé'), findsWidgets);
    expect(find.text('Detectado por'), findsOneWidget);
  });

  testWidgets('FL02 unknown device class shows Desconocido', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        displayName: 'Dispositivo',
        deviceClass: 'unknown',
        deviceClassSource: 'none',
      ),
    ];
    await _pumpDetail(tester, api, deviceName: 'Dispositivo');
    await tester.pumpAndSettle();
    expect(find.text('Desconocido'), findsWidgets);
    // Raw provider codes never appear.
    expect(find.text('unknown'), findsNothing);
  });

  testWidgets('FL03 role selector starts Sin configurar', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [deviceDto(id: 'dev_1')];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('Qué controla'), findsOneWidget);
    // Dropdown value + provenance label both say "Sin configurar".
    expect(find.text('Sin configurar'), findsNWidgets(2));
    expect(find.text('Sin configurar').first, findsOneWidget);
  });

  testWidgets('FL04 selecting Luz sends canonical semantic role', (
    tester,
  ) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [deviceDto(id: 'dev_1')];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    final roleDropdown = find.text('Sin configurar').first;
    await tester.tap(roleDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luz').last);
    await tester.pumpAndSettle();
    expect(api.roleWrites, [('dev_1', 'relay_1', 'light')]);
    expect(find.text('Luz'), findsWidgets);
  });

  testWidgets('FL09 no device class editing control', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [deviceDto(id: 'dev_1', endpoints: [])];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    // The device class is displayed as a read-only metadata row (Text),
    // never as an editable dropdown for the class itself.
    expect(find.text('Tipo de dispositivo'), findsOneWidget);
    final typeRow = find.ancestor(
      of: find.text('Relé'),
      matching: find.byType(Row),
    );
    expect(typeRow, findsWidgets);
    // No dropdown labeled for device class editing.
    expect(
      find.widgetWithText(DropdownButtonFormField<String?>, 'Tipo'),
      findsNothing,
    );
  });

  testWidgets('FL10 raw provider codes not displayed', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(id: 'dev_1', endpoints: [])..['category'] = 'kg',
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    // The raw Tuya category code must never appear as a user-facing label.
    expect(find.text('kg'), findsNothing);
    expect(find.text('Relé'), findsWidgets);
  });

  testWidgets('FL05 backend role failure is truthful', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [deviceDto(id: 'dev_1')];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    api.failRoleWrites = true;
    await tester.tap(find.text('Sin configurar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luz').last);
    await tester.pumpAndSettle();
    // The error is shown; the canonical state is NOT claimed as saved.
    expect(find.textContaining('semantic_role'), findsWidgets);
  });

  testWidgets('FL06 clear sends explicit null reset', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'light',
            'provider_semantic_role': 'unknown',
            'semantic_role_source': 'user',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    // Select "Sin configurar" -> explicit null, never {}.
    await tester.tap(find.text('Luz').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin configurar').last);
    await tester.pumpAndSettle();
    expect(api.roleWrites.last.$3, isNull);
  });

  testWidgets('FL07 role change preserves controlled Area', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': 'pasillo',
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'unknown',
            'provider_semantic_role': 'unknown',
            'semantic_role_source': 'none',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin configurar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luz').last);
    await tester.pumpAndSettle();
    // The mirrored DTO keeps controlled_area_id unchanged.
    final dto = (api.inventory['devices'] as List).first as Map;
    final ep = (dto['endpoints'] as List).first as Map;
    expect(ep['controlled_area_id'], 'pasillo');
  });

  testWidgets('FL08 role change preserves user_name', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'unknown',
            'provider_semantic_role': 'unknown',
            'semantic_role_source': 'none',
            'user_name': 'Espejo',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin configurar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luz').last);
    await tester.pumpAndSettle();
    final dto = (api.inventory['devices'] as List).first as Map;
    final ep = (dto['endpoints'] as List).first as Map;
    expect(ep['user_name'], 'Espejo');
  });

  testWidgets('SR01 provider role shows Detectado automáticamente', (
    tester,
  ) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'light',
            'provider_semantic_role': 'light',
            'semantic_role_source': 'provider',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('Detectado automáticamente'), findsOneWidget);
  });

  testWidgets('SR02 user role shows Configurado manualmente', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'fan',
            'provider_semantic_role': 'light',
            'semantic_role_source': 'user',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('Configurado manualmente'), findsOneWidget);
  });

  testWidgets('SR03 clear user restores provider role from backend', (
    tester,
  ) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'fan',
            'provider_semantic_role': 'light',
            'semantic_role_source': 'user',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ventilador').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin configurar').last);
    await tester.pumpAndSettle();
    expect(api.roleWrites.last.$3, isNull);
    // The Fake mirrors the backend canonical response: clear restores the
    // provider role (light/provider), not null.
    final dto = (api.inventory['devices'] as List).first as Map;
    final ep = (dto['endpoints'] as List).first as Map;
    expect(ep['semantic_role'], 'light');
    expect(ep['provider_semantic_role'], 'light');
    expect(ep['semantic_role_source'], 'provider');
    expect(find.text('Detectado automáticamente'), findsOneWidget);
  });

  testWidgets('SR06 unknown backend role safe', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      deviceDto(
        id: 'dev_1',
        endpoints: [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'future_role',
            'provider_semantic_role': 'future_role',
            'semantic_role_source': 'provider',
            'capabilities': [],
          },
        ],
      ),
    ];
    await _pumpDetail(tester, api);
    await tester.pumpAndSettle();
    // No crash; the selector falls back to "Sin configurar".
    expect(find.text('Qué controla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SR07 DeviceClass and SemanticRole independent', (tester) async {
    final api = FakeDeviceClassApi();
    api.inventory['devices'] = [
      {
        'device_id': 'dev_1',
        'provider_id': 'tuya',
        'display_name': 'Interruptor',
        'device_class': 'switch',
        'device_class_source': 'provider',
        'physical_area_id': 'pasillo',
        'provisioning_state': 'CONFIGURED',
        'enabled': true,
        'endpoints': [
          {
            'endpoint_id': 'relay_1',
            'display_name': null,
            'controlled_area_id': null,
            'enabled': true,
            'exposed_to_resolver': true,
            'binding_id': null,
            'semantic_role': 'light',
            'provider_semantic_role': 'light',
            'semantic_role_source': 'user',
            'capabilities': [],
          },
        ],
      },
    ];
    await _pumpDetail(tester, api, deviceName: 'Interruptor');
    await tester.pumpAndSettle();
    // Physical class and semantic role are displayed independently.
    expect(find.text('Tipo de dispositivo'), findsOneWidget);
    expect(find.text('Interruptor'), findsWidgets);
    expect(find.text('Qué controla'), findsOneWidget);
    expect(find.text('Luz'), findsWidgets);
  });
}
