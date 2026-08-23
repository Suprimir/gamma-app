import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/areas/areas_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

void main() {
  testWidgets('F3C-MOBILE compact list to device detail remains sequential', (
    WidgetTester tester,
  ) async {
    // Compact phone geometry: no split pane, plain push navigation.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    expect(find.text('Dispositivos'), findsOneWidget);

    // Sequential flow: pending banner -> device list -> detail.
    await tester.tap(find.byKey(const Key('pending-devices-banner')));
    await tester.pumpAndSettle();
    expect(find.text('Nuevos dispositivos'), findsOneWidget);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsOneWidget);
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);
    expect(find.text('Canal 1'), findsOneWidget);

    // Back returns to the list, not to a master/detail layout.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Nuevos dispositivos'), findsOneWidget);
  });

  testWidgets('F3C-MOBILE compact area list to editor remains sequential', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = MockDeviceInventoryRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AreasPage(repository: repository)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Áreas'), findsOneWidget);

    // Tap an existing area -> editor dialog opens on top (compact pattern).
    await tester.tap(find.text('Sala'));
    await tester.pumpAndSettle();
    expect(find.text('Editar área'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });
}
