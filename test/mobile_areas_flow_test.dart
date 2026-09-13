import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

import 'fixtures/command_device_fake_repo.dart';

void main() {
  testWidgets('mobile devices home is area-first', (WidgetTester tester) async {
    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesPage(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    // Principal enfocada en ubicaciones, no en todos los dispositivos.
    expect(find.text('Tus ubicaciones'), findsOneWidget);
    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Cocina'), findsOneWidget);
    // Los dispositivos no se listan en la raíz.
    expect(find.text('Plafón cocina'), findsNothing);
    expect(find.text('Enchufe TV'), findsNothing);
  });

  testWidgets('area search filters locations', (WidgetTester tester) async {
    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesPage(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.enterText(
      find.byKey(const Key('mobile-device-search')),
      'coci',
    );
    await tester.pump();

    expect(find.text('Cocina'), findsOneWidget);
    expect(find.text('Sala'), findsNothing);
  });

  testWidgets('selecting an area shows its devices with quick action', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesPage(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.text('Cocina'));
    await tester.pumpAndSettle();

    // Dispositivos de Cocina en tarjetas grandes.
    expect(mobileDeviceCard('Plafón cocina'), findsOneWidget);
    expect(find.text('Enchufe TV'), findsNothing);

    // Pulsar la tarjeta ejecuta la acción principal sin otra pantalla:
    // Plafón cocina está online -> apaga y muestra el aviso. La sección
    // 'Controles' puede empujar la tarjeta fuera del viewport: asegurarla.
    final plafonCard = mobileDeviceCard('Plafón cocina');
    await tester.ensureVisible(plafonCard);
    await tester.pumpAndSettle();
    await tester.tap(plafonCard);
    await tester.pump();
    expect(find.text('Plafón cocina — Apagado'), findsOneWidget);
    expect(find.text('Apagado'), findsWidgets);

    // La interacción secundaria (botón ···) abre controles avanzados.
    await tester.tap(find.byTooltip('Más opciones').first);
    await tester.pumpAndSettle();
    expect(find.text('Identificar dispositivo'), findsOneWidget);

    // El botón configurar abre el detalle técnico.
    await tester.tap(find.text('Configurar dispositivo'));
    await tester.pumpAndSettle();
    expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);
  });

  testWidgets('offline device leaves the area grid and reports no-connection '
      'under Desconectados', (WidgetTester tester) async {
    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesPage(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    // Enchufe TV está offline: la grilla del área solo muestra dispositivos
    // activos, así que queda fuera de Sala.
    await tester.tap(find.text('Sala'));
    await tester.pumpAndSettle();
    expect(find.text('Enchufe TV'), findsNothing);
    expect(find.text('No hay dispositivos asignados a Sala.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // La fila Desconectados lo lista con el conteo real (1 dispositivo).
    await tester.scrollUntilVisible(
      find.text('Desconectados'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final desconectadosRow = find
        .ancestor(of: find.text('Desconectados'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: desconectadosRow, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Desconectados'));
    await tester.pumpAndSettle();

    // Enchufe TV está offline: se muestra sin conexión, nunca como apagado.
    expect(find.text('Enchufe TV'), findsOneWidget);
    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.text('Apagado'), findsNothing);

    // Pulsar la tarjeta informa el estado real en vez de alternar.
    await tester.tap(find.text('Enchufe TV'));
    await tester.pump();
    expect(find.text('Enchufe TV — Sin conexión'), findsOneWidget);
    expect(find.text('Enchufe TV — Apagado'), findsNothing);
    expect(find.text('Enchufe TV — Encendido'), findsNothing);
  });

  testWidgets('long-press opens secondary actions with identify', (
    WidgetTester tester,
  ) async {
    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesPage(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.text('Cocina'));
    await tester.pumpAndSettle();

    final plafonCard = mobileDeviceCard('Plafón cocina');
    await tester.ensureVisible(plafonCard);
    await tester.pumpAndSettle();
    await tester.longPress(plafonCard);
    await tester.pumpAndSettle();
    expect(find.text('Identificar dispositivo'), findsOneWidget);
    expect(find.text('Configurar dispositivo'), findsOneWidget);

    await tester.tap(find.text('Identificar dispositivo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Se envió la orden de identificación al dispositivo.'),
      findsOneWidget,
    );
  });

  testWidgets('explore rows open full inventory', (WidgetTester tester) async {
    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesPage(
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.scrollUntilVisible(
      find.text('Todos los dispositivos'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos los dispositivos'));
    await tester.pumpAndSettle();

    expect(find.text('Plafón cocina'), findsOneWidget);
    // Enchufe TV está offline: fuera del inventario completo, vive en
    // Desconectados.
    expect(find.text('Enchufe TV'), findsNothing);

    // Sin on_off (sensor online) el tap abre el detalle directamente.
    await tester.scrollUntilVisible(
      find.text('Sensor de movimiento'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sensor de movimiento'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);
  });

  group('mobile controles', () {
    testWidgets('controls row shows the channel count and opens the page', (
      WidgetTester tester,
    ) async {
      final repository = CommandDeviceFakeRepo(
        devices: const [_controlsTriple, _controlsSingleNamed],
        areas: _controlsAreas,
      );
      await pumpMobileControls(tester, repository);

      final row = find.byKey(const ValueKey('controls-row'));
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text('Controles')),
        findsOneWidget,
      );
      // 3 channels of the triple + 1 of the single light.
      expect(
        find.descendant(of: row, matching: find.text('4')),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('Controles'), findsOneWidget); // AppBar
      expect(
        find.byKey(
          const ValueKey('mobile-channel-dev_controls_triple-relay_1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-channel-dev_single_named-light')),
        findsOneWidget,
      );
      // Groups keep the area-grid order.
      expect(
        tester.getTopLeft(find.text('Sala')).dy,
        lessThan(tester.getTopLeft(find.text('Comedor')).dy),
      );
    });

    testWidgets('tapping a tile toggles exactly its endpoint and converges', (
      WidgetTester tester,
    ) async {
      final repository = CommandDeviceFakeRepo(
        devices: const [_controlsTriple],
        areas: _controlsAreas,
      );
      await pumpMobileControls(tester, repository);
      await openMobileControls(tester);

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
      await pumpMobileControls(tester, repository);
      await openMobileControls(tester);

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
      await pumpMobileControls(tester, repository);
      await openMobileControls(tester);

      await tester.longPress(
        find.byKey(
          const ValueKey('mobile-channel-dev_controls_triple-relay_1'),
        ),
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
      await pumpMobileControls(tester, repository);
      await openMobileControls(tester);

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

    testWidgets('area view adds a Controles section for its own channels', (
      WidgetTester tester,
    ) async {
      final repository = CommandDeviceFakeRepo(
        devices: const [_controlsTriple],
        areas: _controlsAreas,
      );
      await pumpMobileControls(tester, repository);

      await tester.tap(find.text('Sala'));
      await tester.pumpAndSettle();

      expect(find.text('Controles'), findsOneWidget);
      // relay_1 commands Sala; relay_2/3 belong to Comedor/Patio.
      expect(
        find.byKey(
          const ValueKey('mobile-channel-dev_controls_triple-relay_1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('mobile-channel-dev_controls_triple-relay_2'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('mobile-channel-dev_controls_triple-relay_3'),
        ),
        findsNothing,
      );
      // Additive: the device card stays the identity surface.
      expect(mobileDeviceCard('Interruptor triple'), findsOneWidget);
    });

    testWidgets('device cards show named channels without noise', (
      WidgetTester tester,
    ) async {
      final repository = CommandDeviceFakeRepo(
        devices: const [
          _controlsTriple,
          _controlsTripleNamed3,
          _controlsUnnamedTriple,
          _controlsSingleNamed,
        ],
        areas: _controlsAreas,
      );
      await pumpMobileControls(tester, repository);

      await tester.tap(find.text('Sala'));
      await tester.pumpAndSettle();

      // Two named channels: both names, no '+N'.
      await ensureMobileCardVisible(tester, 'Interruptor triple');
      expect(
        find.descendant(
          of: mobileDeviceCard('Interruptor triple'),
          matching: find.text('Luz terraza · Luz comedor'),
        ),
        findsOneWidget,
      );
      // Three named channels: two shown plus '+1'.
      await ensureMobileCardVisible(tester, 'Interruptor tres nombres');
      expect(
        find.descendant(
          of: mobileDeviceCard('Interruptor tres nombres'),
          matching: find.text('Luz terraza · Luz comedor +1'),
        ),
        findsOneWidget,
      );
      // Unnamed channels keep the generic copy: no 'Canal N' noise.
      await ensureMobileCardVisible(tester, 'Interruptor sin nombres');
      expect(
        find.descendant(
          of: mobileDeviceCard('Interruptor sin nombres'),
          matching: find.textContaining('Canal'),
        ),
        findsNothing,
      );
      // Single-channel cards stay untouched even with a user name.
      await ensureMobileCardVisible(tester, 'Luz escritorio');
      expect(
        find.descendant(
          of: mobileDeviceCard('Luz escritorio'),
          matching: find.text('Luz principal'),
        ),
        findsNothing,
      );
    });
  });
}

/// The mobile device card (identity surface) that owns [name].
Finder mobileDeviceCard(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_DashboardDeviceCard',
  ),
);

Future<void> ensureMobileCardVisible(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    mobileDeviceCard(name),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Mobile-area-first pump at 520 dp (same reason as the multigang suite: the
/// pre-existing home header overflow at 390 dp is unrelated to this flow).
Future<void> pumpMobileControls(
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

Future<void> openMobileControls(WidgetTester tester) async {
  final row = find.byKey(const ValueKey('controls-row'));
  await tester.scrollUntilVisible(
    row,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
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

/// Multi-gang with three named channels (card summary shows ' +1').
const _controlsTripleNamed3 = PhysicalDevice(
  id: 'dev_named_triple',
  name: 'Interruptor tres nombres',
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
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
      userName: 'Luz comedor',
      observedPower: false,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
      userName: 'Luz patio',
      observedQuality: 'unknown',
    ),
  ],
);

/// Multi-gang without user names: cards keep the aggregate copy.
const _controlsUnnamedTriple = PhysicalDevice(
  id: 'dev_unnamed_triple',
  name: 'Interruptor sin nombres',
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
      observedPower: true,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
      observedPower: false,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
      observedQuality: 'unknown',
    ),
  ],
);

/// Single power channel with a user name: card stays single-line.
const _controlsSingleNamed = PhysicalDevice(
  id: 'dev_single_named',
  name: 'Luz escritorio',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      controlledAreaId: 'sala',
      capabilities: {'POWER'},
      userName: 'Luz principal',
      observedPower: true,
      observedQuality: 'confirmed',
    ),
  ],
);
