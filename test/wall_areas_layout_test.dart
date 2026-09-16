import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

import 'fixtures/areas_fake_repo.dart';

/// F3-C Phase 7: the wall Devices surface manages areas inline — the location
/// control opens the area list with edit/delete per area.
void main() {
  testWidgets('wall devices to areas navigation', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    await pumpWallDevices(tester, repo);

    // Areas are managed inline from the wall Devices surface: the location
    // control opens the area list with edit/delete per area.
    expect(find.text('Todas'), findsOneWidget);
    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();

    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.text('Sala'), findsWidgets);
    expect(find.text('Cocina'), findsWidgets);
    expect(find.byTooltip('Editar área'), findsNWidgets(2));
    expect(find.byTooltip('Eliminar área'), findsNWidgets(2));
  });
}

Future<void> pumpWallDevices(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
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
