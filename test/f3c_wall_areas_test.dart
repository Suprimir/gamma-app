import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_areas_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

import 'fixtures/areas_fake_repo.dart';

/// F3-C Fase 7: Areas wall — tarjetas grandes sin overflow, detalle con
/// formulario grande compartido, creación por diálogo, eliminación secundaria
/// con confirmación y navegación desde Dispositivos.
void main() {
  testWidgets('F3C-AREAS-WALL-01 large area cards no overflow', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
      devices: const [salaDevice],
    );
    await pumpWallAreas(tester, repo);

    expect(tester.takeException(), isNull);
    final sala = find.byKey(const ValueKey('wall-area-area_SALA'));
    expect(sala, findsOneWidget);
    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('1 dispositivo'), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-area_COCINA')), findsOneWidget);
    expect(find.text('Cocina'), findsOneWidget);
    expect(find.text('Nueva habitación'), findsOneWidget);

    final size = tester.getSize(sala);
    expect(size.height, greaterThanOrEqualTo(72));
    final create = find.byKey(const ValueKey('wall-new-area'));
    expect(create, findsOneWidget);
    final createSize = tester.getSize(create);
    expect(createSize.height, greaterThanOrEqualTo(72));
  });

  testWidgets('F3C-AREAS-WALL-02 open detail and rename via large form', (
    tester,
  ) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    await pumpWallAreas(tester, repo);

    await tester.tap(find.byKey(const ValueKey('wall-area-area_SALA')));
    await tester.pumpAndSettle();

    expect(_nameFieldText(tester), 'Sala');
    await tester.enterText(find.byType(TextField).first, 'Sala principal');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(repo.updated, [('area_SALA', 'Sala principal')]);
    expect(repo.updatedAliases, [const <String>[]]);
    // Tras guardar se vuelve a la lista con el nombre actualizado.
    expect(find.text('Sala principal'), findsOneWidget);
  });

  testWidgets('F3C-AREAS-WALL-03 create area via dialog', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
    );
    await pumpWallAreas(tester, repo);

    await tester.tap(find.text('Nueva habitación'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva área'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Patio');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pumpAndSettle();

    expect(repo.created.single.$1, 'Patio');
    expect(repo.created.single.$2, isEmpty);
    expect(find.text('Patio'), findsOneWidget);
  });

  testWidgets('F3C-AREAS-WALL-04 delete secondary + confirmed', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    await pumpWallAreas(tester, repo);

    await tester.tap(find.byKey(const ValueKey('wall-area-area_SALA')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Eliminar habitación'),
    );
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar "Sala"?'), findsOneWidget);

    // 409: mensaje honesto y el detalle permanece.
    repo.deleteError = ApiException(409, {'detail': 'área en uso'});
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se puede eliminar esta área porque todavía está asignada a uno o más dispositivos o canales.',
      ),
      findsOneWidget,
    );
    expect(find.text('Eliminar habitación'), findsOneWidget);

    // Éxito: se elimina y se vuelve a la lista.
    repo.deleteError = null;
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Eliminar habitación'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['area_SALA']);
    expect(find.byKey(const ValueKey('wall-area-area_SALA')), findsNothing);
    expect(find.byKey(const ValueKey('wall-area-area_COCINA')), findsOneWidget);
  });

  testWidgets('F3C-AREAS-WALL-05 wall devices to areas navigation', (
    tester,
  ) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    await pumpWallDevices(tester, repo);

    expect(find.text('Habitaciones'), findsOneWidget);
    await tester.tap(find.text('Habitaciones'));
    await tester.pumpAndSettle();

    expect(find.byType(WallAreasPage), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-area_SALA')), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-area_COCINA')), findsOneWidget);
  });
}

Future<void> pumpWallAreas(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WallAreasPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
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

String? _nameFieldText(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField).first);
  return field.controller?.text;
}
