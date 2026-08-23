import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

void main() {
  testWidgets(
    'devices skeleton exposes pending devices, spaces and infrastructure',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
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
      expect(find.text('3 dispositivos nuevos'), findsOneWidget);
      expect(find.text('ESPACIOS'), findsOneWidget);
      expect(find.byKey(const Key('gateways-row')), findsOneWidget);
      expect(find.byKey(const Key('offline-row')), findsOneWidget);
    },
  );

  testWidgets('pending triple switch opens endpoint provisioning UI', (
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

    await tester.tap(find.byKey(const Key('pending-devices-banner')));
    await tester.pumpAndSettle();
    expect(find.text('Nuevos dispositivos'), findsOneWidget);

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsOneWidget);
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
    expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);
  });
}
