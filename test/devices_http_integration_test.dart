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

  /// No SSE in this fake: the production repository's live-update surface
  /// stays inert so widget tests remain timer-free (same contract as the
  /// other ApiClient fakes in this suite).
  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();

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

  /// Device management lives behind the landing's devices button now: the
  /// flat list is the entry point to the detail (the pending banner is gone).
  Future<void> openDevicesList(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-devices-list')));
    await tester.pumpAndSettle();
  }

  Future<void> openDeviceDetail(WidgetTester tester) async {
    await openDevicesList(tester);
    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();
  }

  /// The physical area selector and the endpoint editors are progressive
  /// disclosure inside the collapsed 'Configuración' block.
  Future<void> expandConfiguration(WidgetTester tester) async {
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
  }

  Future<void> tapChip(WidgetTester tester, String chipKey) async {
    await tester.tap(find.byKey(ValueKey(chipKey)));
    await tester.pumpAndSettle();
  }

  /// The landing's offline badge surfaces the devices that need review
  /// (offline + unreachable + authError); unknown/sleeping never inflate it.
  void expectReviewCount(String count) {
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open-offline-list')),
        matching: find.text(count),
      ),
      findsOneWidget,
    );
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

        // The controls-first landing renders the fixture channels as tiles.
        expect(find.text('Relé cocina'), findsOneWidget);
        expect(find.text('Canal 1'), findsOneWidget);

        // The sanitized topology lives in the flat list behind the devices
        // button: pending configuration and infrastructure have their own
        // filter chips (the old landing 'ESPACIOS' grid no longer exists).
        await openDevicesList(tester);
        await tapChip(tester, 'mobile-devices-chip-unconfigured');
        expect(find.text('Interruptor triple'), findsOneWidget);
        expect(find.text('Luz 1'), findsOneWidget);
        expect(find.text('Luz 2'), findsOneWidget);
        expect(find.text('Relé cocina'), findsOneWidget);
        // Already-configured devices never count as pending.
        expect(find.text('Luz sala'), findsNothing);

        expect(find.text('Gateways'), findsOneWidget);
        await tapChip(tester, 'mobile-devices-chip-gateways');
        expect(find.text('Gateway principal'), findsOneWidget);
        expect(find.textContaining('4 subdispositivos'), findsOneWidget);
      },
    );

    testWidgets('gateway does not pollute the pending inbox', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);

      // The pending inbox is the flat list's 'Sin configurar' filter; the
      // gateway is infrastructure, never a user device.
      await openDevicesList(tester);
      await tapChip(tester, 'mobile-devices-chip-unconfigured');
      expect(find.text('Interruptor triple'), findsOneWidget);
      expect(find.text('Gateway principal'), findsNothing);
      // The configured device never joins the pending inbox.
      expect(find.text('Luz sala'), findsNothing);
    });

    testWidgets('ENRICHED devices count as pending and are listed', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);

      // Every ENRICHED (or partially configured) device counts as pending and
      // stays listed under the 'Sin configurar' filter.
      await openDevicesList(tester);
      await tapChip(tester, 'mobile-devices-chip-unconfigured');
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
      // CONTROLES is the household surface: one row per canonical endpoint.
      expect(find.text('Canal 1'), findsOneWidget);
      expect(find.text('Canal 2'), findsOneWidget);
      expect(find.text('Canal 3'), findsOneWidget);
      // Endpoint editors (and the physical-area selector) live inside the
      // collapsed Configuración block; the old 'ENDPOINTS / CANALES' panel
      // header no longer exists.
      expect(find.text('Configuración'), findsOneWidget);
      await expandConfiguration(tester);
      expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    });

    testWidgets('physical area update goes through the API and updates state', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);
      await expandConfiguration(tester);

      await assignPhysicalArea(tester);

      expect(api.physicalAreaWrites, contains(('device_1', 'pasillo')));
      expect(find.text('pasillo'), findsWidgets);
    });

    testWidgets('endpoint area update goes through the API', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);
      await expandConfiguration(tester);

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
        await expandConfiguration(tester);

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
        await expandConfiguration(tester);

        expect(find.text('sala'), findsOneWidget);
        expect(find.text('pasillo'), findsNothing);
      },
    );

    testWidgets('identify is offered only when the repository can run it', (
      tester,
    ) async {
      setTallViewport(tester);

      // Production repository: identify runs through the command layer, so the
      // channel actions sheet offers it.
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await tester.longPress(
        find.byKey(const ValueKey('mobile-channel-child_3-relay_1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Identificar'), findsOneWidget);

      // Dispose the first tree so DevicesPage builds a fresh controller for
      // the next repository (its controller is a late final bound once).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // A repository supporting neither the legacy flag nor the command layer
      // must not offer identify at all.
      final snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: const [
          PhysicalDevice(
            id: 'no_identify',
            name: 'Interruptor sin identificar',
            kind: DeviceKind.switchController,
            provider: 'tuya',
            providerDeviceId: '',
            model: 'M',
            provisioningState: DeviceProvisioningState.configured,
            online: true,
            health: DeviceHealthState.online,
            endpoints: [
              DeviceEndpoint(
                id: 'relay_1',
                name: 'Canal 1',
                kind: DeviceKind.switchController,
                capabilities: {'POWER'},
              ),
            ],
          ),
        ],
        gateways: const [],
        lastDiscoveryLabel: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DevicesPage(
              api: FakeDeviceApi(),
              repository: StubDeviceInventoryRepository(snapshot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(const ValueKey('mobile-channel-no_identify-relay_1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Identificar'), findsNothing);
    });

    testWidgets('per-channel switches are the only power control', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);

      // One switch per power channel, scoped to that channel's control row:
      // there is no separate blanket/global power toggle.
      expect(find.byType(Switch), findsNWidgets(3));
      for (final endpointId in ['relay_1', 'relay_2', 'relay_3']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('channel-control-$endpointId')),
            matching: find.byType(Switch),
          ),
          findsOneWidget,
        );
      }
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('no secret fields are rendered', (tester) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);
      await expandConfiguration(tester);

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

      // The retry renders the controls-first landing with the fixture data.
      expect(find.byKey(const ValueKey('open-devices-list')), findsOneWidget);
      expect(find.text('Canal 1'), findsOneWidget);
    });

    testWidgets('refresh failure keeps the previous snapshot', (tester) async {
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      // First grouped control tile of the controls-first landing.
      expect(find.text('Relé cocina'), findsOneWidget);
      final callsBefore = api.inventoryCalls;

      api.failLoads = true;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      // The pull-to-refresh ran the canonical reload.
      expect(api.inventoryCalls, greaterThan(callsBefore));
      // The previous canonical snapshot survives a failed refresh.
      expect(find.text('Relé cocina'), findsOneWidget);
      expect(find.textContaining('backend down'), findsNothing);
    });
  });

  group('final gate — honest health, area clear, bulk partial failure', () {
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

      expectReviewCount('1');
    });

    testWidgets('physical area clear writes null through the API', (
      tester,
    ) async {
      setTallViewport(tester);
      final api = FakeDeviceApi();
      api.seedPhysicalArea('device_1', 'pasillo');
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);
      await expandConfiguration(tester);

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
        await expandConfiguration(tester);

        await assignPhysicalArea(tester);
        // Let the physical-area success notice expire so the bulk failure
        // notice is the SnackBar the assertion observes.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
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

    testWidgets('binding accepts a free-text entity id per channel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = FakeDeviceApi();
      await pumpDevicesPage(tester, api);
      await openDeviceDetail(tester);
      await expandConfiguration(tester);

      // One binding affordance per actionable channel (3 power endpoints).
      expect(find.text('Vincular entidad'), findsNWidgets(3));

      // The backend still publishes no selectable catalog, so binding is
      // reachable and takes a free-text entity identifier.
      await tester.ensureVisible(find.text('Vincular entidad').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular entidad').first);
      await tester.pumpAndSettle();
      // Free-text entity field, not a selectable catalog picker.
      expect(find.text('Entidad'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresá un identificador de entidad.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).last,
        'light.cocina_principal',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
      await tester.pumpAndSettle();
      // The typed identifier is accepted: the dialog closes.
      expect(find.text('Ingresá un identificador de entidad.'), findsNothing);
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

      expectReviewCount('1');
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

      expectReviewCount('1');
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

      expectReviewCount('1');
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

      expectReviewCount('1');
      expect(find.text(availableWording), findsNothing);
    });

    testWidgets(
      'gateway renders as unknown even when provider health is healthy',
      (tester) async {
        setTallViewport(tester);
        final api = FakeDeviceApi()
          ..inventory = Map.from(deviceplatformInventoryCloudOnlyJson);
        await pumpDevicesPage(tester, api);

        await openDevicesList(tester);
        await tapChip(tester, 'mobile-devices-chip-gateways');

        expect(find.text('Gateway principal'), findsOneWidget);
        expect(find.text('Estado desconocido'), findsOneWidget);
        expect(find.text('Online'), findsNothing);
        expect(find.text('Sin conexión'), findsNothing);
      },
    );
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
