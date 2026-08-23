import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

import 'fixtures/deviceplatform_fixtures.dart';

class FakeDeviceApi extends ApiClient {
  FakeDeviceApi() : super(baseUrl: 'http://fake') {
    inventory = _deepCopy(deviceplatformInventoryJson);
    catalogData = _deepCopy(deviceplatformCatalogJson);
    healthData = _deepCopy(deviceplatformHealthJson);
  }

  late Map<String, dynamic> inventory;
  late Map<String, dynamic> catalogData;
  late Map<String, dynamic> healthData;
  int discoverCalls = 0;
  int inventoryCalls = 0;
  final physicalAreaWrites = <(String, String?)>[];
  final endpointAreaWrites = <(String, String, String?)>[];
  bool failLoads = false;
  bool failMutations = false;
  final failEndpoints = <String>{};

  List<Map<String, dynamic>> get _devices =>
      (inventory['devices'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> _deviceDto(String deviceId) {
    final source = _devices.firstWhere(
      (device) => device['device_id'] == deviceId,
    );
    final copy = Map<String, dynamic>.from(source);
    final endpoints = source['endpoints'];
    if (endpoints is List) {
      copy['endpoints'] = endpoints
          .map((endpoint) => Map<String, dynamic>.from(endpoint as Map))
          .toList();
    }
    return copy;
  }

  void _replaceDevice(Map<String, dynamic> updated) {
    final index = _devices.indexWhere(
      (device) => device['device_id'] == updated['device_id'],
    );
    _devices[index] = updated;
  }

  void seedPhysicalArea(String deviceId, String areaId) {
    _replaceDevice(_deviceDto(deviceId)..['physical_area_id'] = areaId);
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    final copy = Map<String, dynamic>.from(source);
    for (final key in copy.keys.toList()) {
      final value = copy[key];
      if (value is Map) {
        copy[key] = _deepCopy(value as Map<String, dynamic>);
      } else if (value is List) {
        copy[key] = value
            .map(
              (item) =>
                  item is Map ? _deepCopy(item as Map<String, dynamic>) : item,
            )
            .toList();
      }
    }
    return copy;
  }

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    inventoryCalls++;
    if (failLoads) throw ApiException(503, {'detail': 'backend down'});
    return inventory;
  }

  @override
  Future<Map<String, dynamic>> catalog() async {
    if (failLoads) throw ApiException(503, {'detail': 'backend down'});
    return catalogData;
  }

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async {
    if (failLoads) throw ApiException(503, {'detail': 'backend down'});
    return healthData;
  }

  @override
  Future<List<Map<String, dynamic>>> areas() async {
    if (failLoads) throw ApiException(503, {'detail': 'backend down'});
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

  @override
  Future<Map<String, dynamic>> discoverDevices() async {
    discoverCalls++;
    return deviceplatformDiscoveryJson;
  }

  @override
  Future<Map<String, dynamic>> updateDevicePhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    physicalAreaWrites.add((deviceId, areaId));
    if (failMutations) {
      throw ApiException(422, {'detail': 'area_id invalido'});
    }
    final updated = _deviceDto(deviceId)..['physical_area_id'] = areaId;
    _replaceDevice(updated);
    return updated;
  }

  @override
  Future<Map<String, dynamic>> updateEndpointControlledArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    endpointAreaWrites.add((deviceId, endpointId, areaId));
    if (failMutations) {
      throw ApiException(422, {'detail': 'area_id invalido'});
    }
    if (failEndpoints.contains(endpointId)) {
      throw ApiException(503, {'detail': 'persistencia temporal'});
    }
    final updated = _deviceDto(deviceId);
    final endpoints = (updated['endpoints'] as List)
        .cast<Map<String, dynamic>>();
    endpoints.firstWhere(
      (endpoint) => endpoint['endpoint_id'] == endpointId,
    )['controlled_area_id'] = areaId;
    updated['endpoints'] = endpoints;
    _replaceDevice(updated);
    return updated;
  }
}

void main() {
  void setTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpDevicesPage(WidgetTester tester, FakeDeviceApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicesPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDeviceDetail(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('pending-devices-banner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();
  }

  Future<void> assignPhysicalArea(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('physical-area-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pasillo').last);
    await tester.pumpAndSettle();
  }

  group('DevicesPage HTTP integration', () {
    testWidgets(
      'renders the sanitized fixture topology via the production repository',
      (tester) async {
        setTallViewport(tester);
        final api = FakeDeviceApi();
        await pumpDevicesPage(tester, api);

        expect(find.text('4 dispositivos nuevos'), findsOneWidget);
        expect(find.text('ESPACIOS'), findsOneWidget);
        expect(find.text('Gateways'), findsOneWidget);

        await tester.tap(find.byKey(const Key('gateways-row')));
        await tester.pumpAndSettle();
        expect(find.text('Gateway principal'), findsOneWidget);
        expect(find.textContaining('4 subdispositivos'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('gateway does not pollute the pending inbox', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);

      expect(find.text('4 dispositivos nuevos'), findsOneWidget);
      expect(find.text('5 dispositivos nuevos'), findsNothing);

      await tester.tap(find.byKey(const Key('pending-devices-banner')));
      await tester.pumpAndSettle();
      expect(find.text('Nuevos dispositivos'), findsOneWidget);
      expect(find.text('Interruptor triple'), findsOneWidget);
      expect(find.text('Gateway principal'), findsNothing);
    });

    testWidgets('ENRICHED devices count as pending and are listed', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);

      expect(find.text('4 dispositivos nuevos'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pending-devices-banner')));
      await tester.pumpAndSettle();
      expect(find.text('Interruptor triple'), findsOneWidget);
      expect(find.text('Luz 1'), findsOneWidget);
      expect(find.text('Luz 2'), findsOneWidget);
      expect(find.text('Relé cocina'), findsOneWidget);
    });

    testWidgets('3-gang device opens its three canonical endpoints', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      expect(find.text('Configurar dispositivo'), findsOneWidget);
      expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
      expect(find.text('Canal 1'), findsOneWidget);
      expect(find.text('Canal 2'), findsOneWidget);
      expect(find.text('Canal 3'), findsOneWidget);
      expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);
    });

    testWidgets('physical area update goes through the API and updates state', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      await assignPhysicalArea(tester);

      expect(api.physicalAreaWrites, contains(('device_1', 'pasillo')));
      expect(find.text('pasillo'), findsWidgets);
    });

    testWidgets('endpoint area update goes through the API', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      await assignPhysicalArea(tester);

      final dropdowns = find.byType(DropdownButtonFormField<String?>);
      // Physical area + per-endpoint (Área que controla + Qué controla):
      // 3 endpoints in the fixture -> 1 + 3*2 = 7.
      expect(dropdowns, findsNWidgets(7));
      await tester.ensureVisible(dropdowns.at(1));
      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cocina').last);
      await tester.pumpAndSettle();

      expect(
        api.endpointAreaWrites,
        contains(('device_1', 'relay_1', 'cocina')),
      );
    });

    testWidgets(
      'backend validation error is shown and prior state is preserved',
      (tester) async {
        setTallViewport(tester);
        final api = FakeDeviceApi();
        api.seedPhysicalArea('device_1', 'sala');
        await pumpDevicesPage(tester, api);
        await openDeviceDetail(tester);

        expect(find.text('sala'), findsOneWidget);

        api.failMutations = true;
        await tester.tap(find.byKey(const Key('physical-area-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('pasillo').last);
        await tester.pumpAndSettle();

        expect(find.text('area_id invalido'), findsOneWidget);
        expect(api.physicalAreaWrites, contains(('device_1', 'pasillo')));

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Interruptor triple'));
        await tester.pumpAndSettle();

        expect(find.text('sala'), findsOneWidget);
        expect(find.text('pasillo'), findsNothing);
      },
    );

    testWidgets('identify is unavailable in production', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      final unavailableText = find.text(
        'Disponible después de validar el control local.',
      );
      await tester.scrollUntilVisible(
        unavailableText,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(unavailableText, findsOneWidget);

      final identifyButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Identificar dispositivo'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(identifyButton.onPressed, isNull);

      expect(find.text('Identificar'), findsNothing);
    });

    testWidgets('no physical power toggle is rendered', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('no secret fields are rendered', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .toList();
      for (final forbidden in [
        'local_key',
        'api_secret',
        'token',
        'password',
        'gateway_key',
      ]) {
        expect(texts.where((text) => text.contains(forbidden)), isEmpty);
      }
    });

    testWidgets('initial backend failure shows an error with retry', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi()..failLoads = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DevicesPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudieron cargar los dispositivos'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);

      api.failLoads = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('4 dispositivos nuevos'), findsOneWidget);
    });

    testWidgets('refresh failure keeps the previous snapshot', (tester) async {
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      expect(find.text('4 dispositivos nuevos'), findsOneWidget);
      expect(api.inventoryCalls, 1);

      api.failLoads = true;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(api.inventoryCalls, 2);
      expect(find.text('4 dispositivos nuevos'), findsOneWidget);
      expect(find.textContaining('backend down'), findsNothing);
    });
  });

  group('final gate — honest health, area clear, bulk partial failure', () {
    testWidgets('all-unknown health wording for a Cloud-only inventory', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi()
        ..inventory = Map.from(deviceplatformInventoryCloudOnlyJson);
      await pumpDevicesPage(tester, api);

      expect(find.text('Estado local aún no validado'), findsOneWidget);
      expect(
        find.text('Todos los dispositivos están disponibles'),
        findsNothing,
      );
    });

    testWidgets('one offline device surfaces the review wording', (
      tester,
    ) async {
      setTallViewport(tester);
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: [
          for (var i = 0; i < 5; i++)
            stubUserDevice(
              'u$i',
              i == 0 ? DeviceHealthState.offline : DeviceHealthState.unknown,
            ),
        ],
        gateways: const [],
        lastDiscoveryLabel: '',
      );
      final api = FakeDeviceApi();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DevicesPage(
              api: api,
              repository: StubDeviceInventoryRepository(snapshot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 requieren revisión'), findsOneWidget);
    });

    testWidgets('all online devices show the available wording', (
      tester,
    ) async {
      setTallViewport(tester);
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: [
          for (var i = 0; i < 5; i++)
            stubUserDevice('u$i', DeviceHealthState.online),
        ],
        gateways: const [],
        lastDiscoveryLabel: '',
      );
      final api = FakeDeviceApi();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DevicesPage(
              api: api,
              repository: StubDeviceInventoryRepository(snapshot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Todos los dispositivos están disponibles'),
        findsOneWidget,
      );
    });

    testWidgets('physical area clear writes null through the API', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      api.seedPhysicalArea('device_1', 'pasillo');
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      expect(find.text('pasillo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('physical-area-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin asignar').last);
      await tester.pumpAndSettle();

      expect(api.physicalAreaWrites, contains(('device_1', null)));
      expect(find.text('pasillo'), findsNothing);
    });

    testWidgets(
      'bulk apply keeps canonical success and surfaces the failed channel',
      (tester) async {
        setTallViewport(tester);
        final api = FakeDeviceApi();
        await pumpDevicesPage(tester, api);
        await openDeviceDetail(tester);

        await assignPhysicalArea(tester);
        api.failEndpoints.add('relay_3');
        await tester.tap(find.text('Usar también para todos los canales'));
        await tester.pumpAndSettle();

        expect(
          api.endpointAreaWrites,
          containsAll([
            ('device_1', 'relay_1', 'pasillo'),
            ('device_1', 'relay_2', 'pasillo'),
            ('device_1', 'relay_3', 'pasillo'),
          ]),
        );
        expect(find.text('persistencia temporal'), findsOneWidget);
        expect(find.text('pasillo'), findsNWidgets(3));
        expect(find.text('Sin asignar'), findsOneWidget);
      },
    );

    testWidgets('binding placeholder is capability-based and disabled', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      expect(find.text('Vincular entidad'), findsNWidgets(3));
      expect(
        find.text(
          'Disponible cuando el backend publique el catálogo de entidades.',
        ),
        findsNWidgets(3),
      );

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Vincular entidad').first,
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('final gate — health aggregation states', () {
    const availableWording = 'Todos los dispositivos están disponibles';

    Future<void> pumpHealthSnapshot(
      WidgetTester tester,
      List<DeviceHealthState> healths,
    ) async {
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: [
          for (var i = 0; i < healths.length; i++)
            stubUserDevice('u$i', healths[i]),
        ],
        gateways: const [],
        lastDiscoveryLabel: '',
      );
      final api = FakeDeviceApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DevicesPage(
              api: api,
              repository: StubDeviceInventoryRepository(snapshot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('all online shows the available wording', (tester) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(
        tester,
        List.filled(5, DeviceHealthState.online),
      );

      expect(find.text(availableWording), findsOneWidget);
    });

    testWidgets('all unknown shows the unvalidated wording', (tester) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(
        tester,
        List.filled(5, DeviceHealthState.unknown),
      );

      expect(find.text('Estado local aún no validado'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets('one offline among unknown surfaces review wording', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.offline,
        DeviceHealthState.unknown,
        DeviceHealthState.unknown,
        DeviceHealthState.unknown,
        DeviceHealthState.unknown,
      ]);

      expect(find.text('1 requieren revisión'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets('one unreachable among online surfaces review wording', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.unreachable,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
      ]);

      expect(find.text('1 requieren revisión'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets('one authError among online surfaces review wording', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.authError,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
      ]);

      expect(find.text('1 requieren revisión'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets('all sleeping shows the resting wording', (tester) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(
        tester,
        List.filled(5, DeviceHealthState.sleeping),
      );

      expect(find.text('5 dispositivos en reposo'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets(
      'mixed online and unknown shows the partial validation wording',
      (tester) async {
        setTallViewport(tester);
        await pumpHealthSnapshot(tester, [
          DeviceHealthState.online,
          DeviceHealthState.online,
          DeviceHealthState.online,
          DeviceHealthState.unknown,
          DeviceHealthState.unknown,
        ]);

        expect(find.text('2 con estado local aún no validado'), findsOneWidget);
        expect(find.text(availableWording), findsNothing);
      },
    );

    testWidgets('mixed online and sleeping shows the rest/available wording', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.sleeping,
        DeviceHealthState.sleeping,
      ]);

      expect(find.text('2 en reposo · 3 disponibles'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets('mixed online and unreachable surfaces review wording', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.unreachable,
      ]);

      expect(find.text('1 requieren revisión'), findsOneWidget);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets(
      'gateway renders as unknown even when provider health is healthy',
      (tester) async {
        setTallViewport(tester);
        final api = FakeDeviceApi()
          ..inventory = Map.from(deviceplatformInventoryCloudOnlyJson);
        await pumpDevicesPage(tester, api);

        await tester.tap(find.byKey(const Key('gateways-row')));
        await tester.pumpAndSettle();

        expect(find.text('Gateway principal'), findsOneWidget);
        expect(find.text('Estado desconocido'), findsOneWidget);
        expect(find.text('Online'), findsNothing);
        expect(find.text('Sin conexión'), findsNothing);
      },
    );

    testWidgets('sleeping + unknown never counts unknown as available', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.sleeping,
        DeviceHealthState.sleeping,
        DeviceHealthState.unknown,
        DeviceHealthState.unknown,
        DeviceHealthState.unknown,
      ]);

      // Los 3 unknown NO son "disponibles": el resumen debe reflejar ambos
      // estados y no reportar 3 disponibles.
      expect(
        find.text('3 con estado local aún no validado · 2 en reposo'),
        findsOneWidget,
      );
      expect(find.textContaining('disponibles'), findsNothing);
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets('online + sleeping + unknown reports exactly onlineCount', (
      tester,
    ) async {
      setTallViewport(tester);
      await pumpHealthSnapshot(tester, [
        DeviceHealthState.online,
        DeviceHealthState.online,
        DeviceHealthState.sleeping,
        DeviceHealthState.unknown,
        DeviceHealthState.unknown,
      ]);

      // Disponibles == onlineCount (2), nunca userCount - sleeping (4).
      expect(
        find.text(
          '2 disponibles · 2 con estado local aún no validado · 1 en reposo',
        ),
        findsOneWidget,
      );
      expect(find.text('4 disponibles'), findsNothing);
      expect(find.text(availableWording), findsNothing);
    });
  });
}

class StubDeviceInventoryRepository implements DeviceInventoryRepository {
  StubDeviceInventoryRepository(this.snapshot);

  final DeviceInventorySnapshot snapshot;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async => snapshot;

  @override
  Future<DeviceInventorySnapshot> discover() async => snapshot;

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<HomeArea>> listAreas() async => snapshot.areas;

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteArea(String areaId) async {
    throw UnimplementedError();
  }
}

PhysicalDevice stubUserDevice(String id, DeviceHealthState health) {
  return PhysicalDevice(
    id: id,
    name: 'Device $id',
    kind: DeviceKind.unknown,
    provider: 'tuya',
    providerDeviceId: '',
    model: 'M',
    provisioningState: DeviceProvisioningState.configured,
    online: health == DeviceHealthState.online,
    health: health,
    endpoints: const [],
  );
}
