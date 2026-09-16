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

      // Controls-first landing: rooms group the channel tiles (the old
      // 'ESPACIOS' grid became the per-room control groups) and both
      // management entries live in the header.
      expect(find.text('Cocina'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-devices-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-offline-list')), findsOneWidget);

      // Pending devices and infrastructure live behind the devices button.
      await tester.tap(find.byKey(const ValueKey('open-devices-list')));
      await tester.pumpAndSettle();
      expect(find.text('Dispositivos'), findsOneWidget); // AppBar
      await tester.tap(
        find.byKey(const ValueKey('mobile-devices-chip-unconfigured')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Interruptor triple'), findsOneWidget);
      expect(find.text('Foco Zigbee'), findsOneWidget);
      expect(find.text('Sensor de movimiento'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('mobile-devices-chip-gateways')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gateway Zigbee principal'), findsOneWidget);
    },
  );

  testWidgets('pending triple switch opens endpoint provisioning UI', (
    WidgetTester tester,
  ) async {
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

    // The pending inbox lives behind the landing's devices button now: the
    // flat list is the entry point to the detail.
    await tester.tap(find.byKey(const ValueKey('open-devices-list')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Interruptor triple'));
    await tester.pumpAndSettle();

    expect(find.text('Configurar dispositivo'), findsOneWidget);
    // CONTROLES is the household surface: one row per canonical endpoint.
    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
    // Endpoint editors + the physical-area selector live inside the collapsed
    // Configuración block (the old 'ENDPOINTS / CANALES' panel header is gone).
    expect(find.text('Configuración'), findsOneWidget);
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
  });
}
