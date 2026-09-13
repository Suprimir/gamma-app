import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

/// Phase 4 (Pattern C): detail views are reorganized as Control -> Estado ->
/// collapsed Configuración. Channel controls live in the Control block (with
/// role icons) while rename/area/role stay in the collapsed configuration;
/// mobile mutations confirm through a SnackBar (QoL 4).
void main() {
  group('mobile standard detail blocks', () {
    testWidgets('renders Control first, then Estado, then collapsed config', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpMobile(tester, repo);

      expect(find.text('CONTROLES'), findsOneWidget);
      expect(find.text('ESTADO'), findsOneWidget);
      expect(find.text('Configuración'), findsOneWidget);

      final controlY = tester.getTopLeft(find.text('CONTROLES')).dy;
      final estadoY = tester.getTopLeft(find.text('ESTADO')).dy;
      final configY = tester.getTopLeft(find.text('Configuración')).dy;
      expect(controlY, lessThan(estadoY));
      expect(estadoY, lessThan(configY));

      // One row per power channel, in canonical order.
      expect(
        find.byKey(const ValueKey('channel-control-relay_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('channel-control-relay_2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('channel-control-relay_3')),
        findsOneWidget,
      );

      // Configuration is collapsed by default: its body is not built.
      expect(find.text('Qué controla'), findsNothing);
      expect(find.text('Usar también para todos los canales'), findsNothing);
    });

    testWidgets('control row switch commands only its channel and converges', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpMobile(tester, repo);

      final relay2 = find.byKey(const ValueKey('channel-control-relay_2'));
      final switchFinder = find.descendant(
        of: relay2,
        matching: find.byType(Switch),
      );
      // relay_2 has a confirmed off observation: the switch starts off.
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(repo.powerCalls, [('dev_blocks_01', 'relay_2', true)]);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(
        find.descendant(of: relay2, matching: find.text('Encendido')),
        findsOneWidget,
      );
      // Siblings keep their own state.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('channel-control-relay_1')),
          matching: find.text('Encendido'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('channel-control-relay_3')),
          matching: find.text('Sin datos'),
        ),
        findsOneWidget,
      );
      // The semantic role drives the row glyph (relay_3 is a fan).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('channel-control-relay_3')),
          matching: find.byIcon(Icons.air),
        ),
        findsOneWidget,
      );
    });

    testWidgets('config expands and endpoint rename still works + feedback', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpMobile(tester, repo);

      expect(find.text('Qué controla'), findsNothing);
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();

      expect(find.text('Qué controla'), findsNWidgets(3));
      expect(find.text('Usar también para todos los canales'), findsOneWidget);

      await tester.tap(find.byTooltip('Cambiar nombre del canal').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Luz pasillo',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(repo.renamedEndpoints, [
        ('dev_blocks_01', 'relay_1', 'Luz pasillo'),
      ]);
      expect(find.text('Nombre actualizado'), findsOneWidget);
    });

    testWidgets('physical area save confirms with Habitación actualizada', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpMobile(tester, repo);

      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('physical-area-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comedor').last);
      await tester.pumpAndSettle();

      expect(repo.physicalAreaWrites, [('dev_blocks_01', 'comedor')]);
      expect(find.text('Habitación actualizada'), findsOneWidget);
    });

    testWidgets('endpoint role save confirms with Control actualizado', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpMobile(tester, repo);

      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();

      final roleLabel = find.text('Qué controla').first;
      final roleColumn = find
          .ancestor(of: roleLabel, matching: find.byType(Column))
          .first;
      final dropdown = find.descendant(
        of: roleColumn,
        matching: find.byType(DropdownButtonFormField<String?>),
      );
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ventilador').last);
      await tester.pumpAndSettle();

      expect(repo.roleWrites, [('dev_blocks_01', 'relay_1', 'fan')]);
      expect(find.text('Control actualizado'), findsOneWidget);
    });

    testWidgets('Estado owns the credentials badge when pending_key', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(
        devices: [_tripleDevice.copyWith(pendingKey: true)],
      );
      await _pumpMobile(tester, repo, device: repo.devices.first);

      final estadoPanel = find
          .ancestor(
            of: find.text('ESTADO'),
            matching: find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_Panel',
            ),
          )
          .first;
      expect(
        find.descendant(
          of: estadoPanel,
          matching: find.text('Sin credenciales'),
        ),
        findsOneWidget,
      );

      final withKey = _BlocksFakeRepo(
        devices: [_tripleDevice.copyWith(pendingKey: false)],
      );
      await _pumpMobile(tester, withKey, device: withKey.devices.first);
      expect(find.text('Sin credenciales'), findsNothing);
    });
  });

  group('wall detail blocks', () {
    testWidgets('control rows command only their channel and reach 56dp', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpWall(tester, repo);

      await tester.tap(find.byKey(const ValueKey('wall-device-dev_blocks_01')));
      await tester.pumpAndSettle();

      expect(find.text('Controles'), findsOneWidget);
      final relay2 = find.byKey(const ValueKey('wall-channel-control-relay_2'));
      expect(relay2, findsOneWidget);
      expect(tester.getSize(relay2).height, greaterThanOrEqualTo(56));

      final switchFinder = find.descendant(
        of: relay2,
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(repo.powerCalls, [('dev_blocks_01', 'relay_2', true)]);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(
        find.descendant(of: relay2, matching: find.text('Encendido')),
        findsOneWidget,
      );
    });

    testWidgets('wall per-control configuration is collapsed by default', (
      tester,
    ) async {
      final repo = _BlocksFakeRepo(devices: const [_tripleDevice]);
      await _pumpWall(tester, repo);

      await tester.tap(find.byKey(const ValueKey('wall-device-dev_blocks_01')));
      await tester.pumpAndSettle();

      expect(find.text('Qué controla'), findsNothing);
      await tester.ensureVisible(find.text('Configuración'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();

      expect(find.text('Qué controla'), findsNWidgets(3));
      expect(find.text('Habitación que controla'), findsNWidgets(3));
    });
  });
}

Future<void> _pumpMobile(
  WidgetTester tester,
  _BlocksFakeRepo repo, {
  PhysicalDevice? device,
}) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DeviceDetailView(
          device: device ?? repo.devices.first,
          areas: repo.areas,
          gateways: const [],
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpWall(WidgetTester tester, _BlocksFakeRepo repo) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WallDevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}

const _tripleDevice = PhysicalDevice(
  id: 'dev_blocks_01',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: 'tuya-blocks',
  model: 'TS0013',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'relay_1',
      name: 'Canal 1',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'POWER'},
      observedPower: true,
      observedQuality: 'confirmed',
      observedAt: '2026-09-12T00:00:00Z',
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'comedor',
      capabilities: {'POWER'},
      observedPower: false,
      observedQuality: 'confirmed',
      observedAt: '2026-09-12T00:00:00Z',
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'POWER'},
      semanticRole: 'fan',
    ),
  ],
);

/// Command-capable fake with working rename/area/role mutations so the
/// collapsed configuration can be exercised end to end.
class _BlocksFakeRepo
    implements DeviceInventoryRepository, DeviceCommandRepository {
  _BlocksFakeRepo({List<PhysicalDevice>? devices, List<HomeArea>? areas})
    : devices = List.of(devices ?? const []),
      areas =
          areas ??
          const [
            HomeArea(id: 'sala', name: 'Sala'),
            HomeArea(id: 'comedor', name: 'Comedor'),
          ];

  List<PhysicalDevice> devices;
  List<HomeArea> areas;

  final powerCalls = <(String, String, bool)>[];
  final renamedEndpoints = <(String, String, String?)>[];
  final roleWrites = <(String, String, String?)>[];
  final physicalAreaWrites = <(String, String?)>[];

  int _indexOf(String deviceId) =>
      devices.indexWhere((device) => device.id == deviceId);

  PhysicalDevice _replace(String deviceId, PhysicalDevice updated) {
    devices[_indexOf(deviceId)] = updated;
    return updated;
  }

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: List.unmodifiable(areas),
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<DeviceInventorySnapshot> discover() async => load();

  @override
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  ) async {
    powerCalls.add((deviceId, endpointId, enabled));
    return EndpointPowerResult(
      outcome: 'SUCCESS',
      changed: true,
      observedPower: enabled,
      observedQuality: 'confirmed',
      observedAt: '2026-09-12T00:00:00Z',
    );
  }

  @override
  Future<CapabilityActionResult> executeAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  }) async => throw UnimplementedError();

  @override
  Future<IdentifyResult> identifyDevice(
    String deviceId, {
    String? endpointId,
  }) async => const IdentifyResult(supported: false);

  @override
  Future<PhysicalDevice> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  }) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> unbindEntity(
    String deviceId,
    String bindingId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> refreshDevice(String deviceId) async =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    physicalAreaWrites.add((deviceId, areaId));
    return _replace(
      deviceId,
      devices[_indexOf(deviceId)].copyWith(physicalAreaId: areaId),
    );
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    final current = devices[_indexOf(deviceId)];
    return _replace(
      deviceId,
      current.copyWith(
        endpoints: [
          for (final endpoint in current.endpoints)
            if (endpoint.id == endpointId)
              endpoint.copyWith(controlledAreaId: areaId)
            else
              endpoint,
        ],
      ),
    );
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    roleWrites.add((deviceId, endpointId, role));
    final current = devices[_indexOf(deviceId)];
    return _replace(
      deviceId,
      current.copyWith(
        endpoints: [
          for (final endpoint in current.endpoints)
            if (endpoint.id == endpointId)
              endpoint.copyWith(semanticRole: role)
            else
              endpoint,
        ],
      ),
    );
  }

  @override
  Future<PhysicalDevice> renameDevice(
    String deviceId,
    String? userName,
  ) async => _replace(
    deviceId,
    devices[_indexOf(deviceId)].copyWith(userName: userName),
  );

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    renamedEndpoints.add((deviceId, endpointId, userName));
    final current = devices[_indexOf(deviceId)];
    return _replace(
      deviceId,
      current.copyWith(
        endpoints: [
          for (final endpoint in current.endpoints)
            if (endpoint.id == endpointId)
              endpoint.copyWith(userName: userName)
            else
              endpoint,
        ],
      ),
    );
  }

  @override
  Future<List<HomeArea>> listAreas() async => List.unmodifiable(areas);

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async => throw UnimplementedError();

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteArea(String areaId) async => throw UnimplementedError();

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}
