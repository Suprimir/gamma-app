import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

import 'fixtures/command_device_fake_repo.dart';

/// Mobile devices tab: CONTROLES is the landing (grouped channel tiles) and
/// device management lives behind the header icon buttons (flat devices list
/// and offline list). Discovery and manual add moved to the devices list.
void main() {
  testWidgets('landing shows grouped controls and both header buttons', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);

    // The area grid, EXPLORAR rows and the Controles nav row are gone.
    expect(find.text('Tus ubicaciones'), findsNothing);
    expect(find.text('EXPLORAR'), findsNothing);
    expect(find.byKey(const ValueKey('controls-row')), findsNothing);

    // Both device-management entries live in the header.
    expect(find.byKey(const ValueKey('open-devices-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-offline-list')), findsOneWidget);
    // The offline button carries the real count as a badge.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open-offline-list')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    // Grouped control tiles: Plafón cocina commands Cocina (first group).
    expect(
      find.byKey(const ValueKey('mobile-channel-dev_plafon_cocina-light')),
      findsOneWidget,
    );
    expect(find.text('Cocina'), findsOneWidget);
    // Sensors never become controls.
    expect(find.text('Sensor de movimiento'), findsNothing);
  });

  testWidgets('controls landing keeps the empty state honest', (
    WidgetTester tester,
  ) async {
    final repository = CommandDeviceFakeRepo(devices: const [_sensorOnly]);
    await pumpMobile(tester, repository);

    expect(find.text('Todavía no hay controles.'), findsOneWidget);
    expect(
      find.text('Abrí Dispositivos para buscar y configurar tus equipos.'),
      findsOneWidget,
    );
    // Device management stays reachable from the header.
    expect(find.byKey(const ValueKey('open-devices-list')), findsOneWidget);
  });

  testWidgets('open-devices-list opens the flat devices list', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);

    await openDevicesList(tester);

    expect(find.text('Dispositivos'), findsOneWidget); // AppBar
    // Flat list includes offline devices; gateways are not devices.
    expect(find.text('Plafón cocina'), findsOneWidget);
    expect(find.text('Enchufe TV'), findsOneWidget);
    expect(find.text('Interruptor triple'), findsOneWidget);
    expect(find.text('Gateway Zigbee principal'), findsNothing);
    // Chips and the moved management actions.
    expect(
      find.byKey(const ValueKey('mobile-devices-chip-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-devices-chip-unconfigured')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-devices-chip-unassigned')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-devices-chip-gateways')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-devices-discover')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-devices-add')), findsOneWidget);
  });

  testWidgets('chips filter the list (unconfigured / unassigned / gateways)', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);
    await openDevicesList(tester);

    await tapChip(tester, 'mobile-devices-chip-unconfigured');
    expect(find.text('Interruptor triple'), findsOneWidget);
    expect(find.text('Foco Zigbee'), findsOneWidget);
    expect(find.text('Sensor de movimiento'), findsOneWidget);
    expect(find.text('Plafón cocina'), findsNothing);

    await tapChip(tester, 'mobile-devices-chip-unassigned');
    expect(find.text('Interruptor triple'), findsOneWidget);
    expect(find.text('Plafón cocina'), findsNothing);

    await tapChip(tester, 'mobile-devices-chip-gateways');
    expect(find.text('Gateway Zigbee principal'), findsOneWidget);
    expect(find.text('Interruptor triple'), findsNothing);
    expect(find.text('Plafón cocina'), findsNothing);

    await tapChip(tester, 'mobile-devices-chip-all');
    expect(find.text('Plafón cocina'), findsOneWidget);
    expect(find.text('Enchufe TV'), findsOneWidget);
    expect(find.text('Gateway Zigbee principal'), findsNothing);
  });

  testWidgets('a pending device appears under Sin configurar', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);
    await openDevicesList(tester);

    await tapChip(tester, 'mobile-devices-chip-unconfigured');

    expect(find.text('Interruptor triple'), findsOneWidget);
    expect(find.textContaining('· Sin configurar'), findsWidgets);
    expect(find.text('Plafón cocina'), findsNothing);
  });

  testWidgets('search filters by device and channel names', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);
    await openDevicesList(tester);

    await tester.enterText(
      find.byKey(const Key('mobile-devices-search')),
      'plafón',
    );
    await tester.pump();
    expect(find.text('Plafón cocina'), findsOneWidget);
    expect(find.text('Enchufe TV'), findsNothing);

    // Channel names are searchable too (relay 'Luz cocina' of the triple
    // wall controller).
    await tester.enterText(
      find.byKey(const Key('mobile-devices-search')),
      'luz cocina',
    );
    await tester.pump();
    expect(find.text('Control de áreas'), findsOneWidget);
    expect(find.text('Plafón cocina'), findsNothing);
  });

  testWidgets('discovery button runs discover on the repository', (
    WidgetTester tester,
  ) async {
    final repository = CommandDeviceFakeRepo(devices: const [_pendingLight]);
    await pumpMobile(tester, repository);
    await openDevicesList(tester);

    expect(repository.discoverCount, 0);
    await tester.tap(find.byKey(const ValueKey('mobile-devices-discover')));
    await tester.pump();

    expect(repository.discoverCount, 1);
    await tester.pumpAndSettle();
    expect(
      find.text('1 dispositivos pendientes de configurar.'),
      findsOneWidget,
    );
  });

  testWidgets('offline button opens the offline list with honest state', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);

    await tester.tap(find.byKey(const ValueKey('open-offline-list')));
    await tester.pumpAndSettle();

    expect(find.text('Desconectados'), findsOneWidget);
    expect(find.text('Enchufe TV'), findsOneWidget);
    // Offline cards never fake a confident state.
    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.text('Apagado'), findsNothing);

    await tester.tap(find.text('Enchufe TV'));
    await tester.pump();
    expect(find.text('Enchufe TV — Sin conexión'), findsOneWidget);
    expect(find.text('Enchufe TV — Encendido'), findsNothing);
  });

  testWidgets('tapping a tile toggles exactly its endpoint and converges', (
    WidgetTester tester,
  ) async {
    final repository = CommandDeviceFakeRepo(
      devices: const [_controlsTriple],
      areas: _controlsAreas,
    );
    await pumpMobile(tester, repository);

    final relay2 = find.byKey(
      const ValueKey('mobile-channel-dev_controls_triple-relay_2'),
    );
    await tester.ensureVisible(relay2);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: relay2, matching: find.text('Apagado')),
      findsOneWidget,
    );

    await tester.tap(relay2);
    await tester.pump();
    expect(repository.powerCalls, [('dev_controls_triple', 'relay_2', true)]);
    expect(find.text('Luz comedor — Encendido'), findsOneWidget);

    await tester.pumpAndSettle();
    // Confirmed observation converges into the tile; siblings stay.
    expect(
      find.descendant(of: relay2, matching: find.text('Encendido')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile-channel-dev_controls_triple-relay_1'),
        ),
        matching: find.text('Encendido'),
      ),
      findsOneWidget,
    );

    final relay1 = find.byKey(
      const ValueKey('mobile-channel-dev_controls_triple-relay_1'),
    );
    await tester.tap(relay1);
    await tester.pump();
    expect(repository.powerCalls.last, (
      'dev_controls_triple',
      'relay_1',
      false,
    ));
  });

  testWidgets('writes-disabled keeps the tile state honest', (
    WidgetTester tester,
  ) async {
    final repository = CommandDeviceFakeRepo(
      devices: const [_controlsTriple],
      areas: _controlsAreas,
      powerResult: const EndpointPowerResult(
        outcome: 'EXECUTION_DISABLED',
        changed: false,
      ),
    );
    await pumpMobile(tester, repository);

    final relay2 = find.byKey(
      const ValueKey('mobile-channel-dev_controls_triple-relay_2'),
    );
    await tester.tap(relay2);
    await tester.pump();

    expect(repository.powerCalls, [('dev_controls_triple', 'relay_2', true)]);
    expect(
      find.textContaining('Escritura deshabilitada en el modo actual'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    // No confirmed observation: never a fabricated on.
    expect(
      find.descendant(of: relay2, matching: find.text('Apagado')),
      findsOneWidget,
    );
  });

  testWidgets('long-press offers channel actions and opens the device', (
    WidgetTester tester,
  ) async {
    final repository = CommandDeviceFakeRepo(
      devices: const [_controlsTriple],
      areas: _controlsAreas,
    );
    await pumpMobile(tester, repository);

    await tester.longPress(
      find.byKey(const ValueKey('mobile-channel-dev_controls_triple-relay_1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ver dispositivo'), findsOneWidget);
    expect(find.text('Renombrar canal'), findsOneWidget);
    expect(find.text('Identificar'), findsOneWidget);

    await tester.tap(find.text('Ver dispositivo'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);
  });

  testWidgets('rename channel from the sheet converges into the tile', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();
    await pumpMobile(tester, repository);

    final tile = find.byKey(
      const ValueKey('mobile-channel-dev_plafon_cocina-light'),
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.longPress(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renombrar canal'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz principal',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Guardar'),
      ),
    );
    await tester.pumpAndSettle();

    // The tile converges to the new user name through the shared controller.
    expect(find.text('Luz principal'), findsOneWidget);
  });

  testWidgets('controls landing groups keep the area order', (
    WidgetTester tester,
  ) async {
    final repository = CommandDeviceFakeRepo(
      devices: const [_controlsTriple],
      areas: _controlsAreas,
    );
    await pumpMobile(tester, repository);

    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Comedor'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Sala')).dy,
      lessThan(tester.getTopLeft(find.text('Comedor')).dy),
    );
  });
}

Future<void> openDevicesList(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-devices-list')));
  await tester.pumpAndSettle();
}

Future<void> tapChip(WidgetTester tester, String key) async {
  final chip = find.byKey(ValueKey(key));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Mobile pump at 520 dp (the pre-existing home header overflow at 390 dp is
/// unrelated to this flow).
Future<void> pumpMobile(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(520, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}

const _controlsAreas = [
  HomeArea(id: 'sala', name: 'Sala'),
  HomeArea(id: 'comedor', name: 'Comedor'),
  HomeArea(id: 'patio', name: 'Patio'),
];

/// Multi-gang with two named channels and confirmed observations.
const _controlsTriple = PhysicalDevice(
  id: 'dev_controls_triple',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: '',
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
      capabilities: {'on_off'},
      userName: 'Luz terraza',
      observedPower: true,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'comedor',
      capabilities: {'on_off'},
      userName: 'Luz comedor',
      observedPower: false,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'patio',
      capabilities: {'on_off'},
      observedQuality: 'unknown',
    ),
  ],
);

/// Discovered device: `needsConfiguration` and without an assigned area.
const _pendingLight = PhysicalDevice(
  id: 'dev_pending_01',
  name: 'Luz pendiente',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.discovered,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);

/// Sensor without any power channel: never rendered as a control.
const _sensorOnly = PhysicalDevice(
  id: 'dev_sensor_01',
  name: 'Sensor de movimiento',
  kind: DeviceKind.sensor,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZP01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'motion',
      name: 'Movimiento',
      kind: DeviceKind.sensor,
      capabilities: {'motion'},
    ),
  ],
);
