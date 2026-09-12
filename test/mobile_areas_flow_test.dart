import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

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
    expect(find.text('Plafón cocina'), findsOneWidget);
    expect(find.text('Enchufe TV'), findsNothing);

    // Pulsar la tarjeta ejecuta la acción principal sin otra pantalla:
    // Plafón cocina está online -> apaga y muestra el aviso.
    await tester.tap(find.text('Plafón cocina'));
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

    await tester.longPress(find.text('Plafón cocina'));
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
}
