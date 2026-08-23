import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/areas/desktop_areas_page.dart';
import 'package:gamma_app/data/device_inventory.dart';

import 'fixtures/areas_fake_repo.dart';

/// F3-C Fase 6: Areas desktop — maestro/detalle con selección por id opaco,
/// activación con teclado real, rename/create/delete honesto (409) y fallback
/// estrecho sin overflow.
void main() {
  testWidgets('selection by opaque id', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
      devices: const [salaDevice],
    );
    final controller = await pumpDesktopAreas(tester, repo);

    expect(
      find.byKey(const ValueKey('desktop-area-area_SALA')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-area-area_COCINA')),
      findsOneWidget,
    );
    // Subtítulo con el conteo real del snapshot canónico.
    expect(find.text('1 dispositivo'), findsOneWidget);
    expect(find.text('Selecciona un área'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
    await tester.pumpAndSettle();

    expect(controller.selectedAreaId, 'area_SALA');
    expect(find.text('Selecciona un área'), findsNothing);
    expect(_nameFieldText(tester), 'Sala');
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-area-area_COCINA')));
    await tester.pumpAndSettle();

    expect(controller.selectedAreaId, 'area_COCINA');
    expect(_nameFieldText(tester), 'Cocina');
    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(selected, findsOneWidget);
  });

  testWidgets('real keyboard Enter activates row', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
    );
    final controller = await pumpDesktopAreas(tester, repo);

    await _focusAreaRow(tester, 'area_SALA');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.selectedAreaId, 'area_SALA');
    expect(_nameFieldText(tester), 'Sala');
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
  });

  testWidgets('b Space activates row too', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
    );
    final controller = await pumpDesktopAreas(tester, repo);

    await _focusAreaRow(tester, 'area_SALA');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(controller.selectedAreaId, 'area_SALA');
    expect(_nameFieldText(tester), 'Sala');
  });

  testWidgets('rename keeps opaque id and converges', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    final controller = await pumpDesktopAreas(tester, repo);

    await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Sala principal');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(repo.updated, [('area_SALA', 'Sala principal')]);
    expect(repo.updatedAliases, [const <String>[]]);
    expect(controller.selectedAreaId, 'area_SALA');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('desktop-area-area_SALA')),
        matching: find.text('Sala principal'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('create via master button', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
    );
    await pumpDesktopAreas(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Nueva habitación'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Terraza');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pumpAndSettle();

    expect(repo.created.single.$1, 'Terraza');
    expect(repo.created.single.$2, isEmpty);
    expect(find.text('Terraza'), findsOneWidget);
  });

  testWidgets('delete confirmation + 409 truthfulness', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    final controller = await pumpDesktopAreas(tester, repo);

    await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
    await tester.pumpAndSettle();

    Future<void> openDelete() async {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Eliminar'));
      await tester.pumpAndSettle();
    }

    // Cancelar primero: nada se elimina.
    await openDelete();
    expect(find.text('Eliminar área'), findsOneWidget);
    expect(find.text('¿Eliminar "Sala"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.text('Sala'), findsWidgets);

    // Confirmar con 409: mensaje honesto, el área permanece y la selección
    // se conserva.
    repo.deleteError = ApiException(409, {'detail': 'área en uso'});
    await openDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se puede eliminar esta área porque todavía está asignada a uno o más dispositivos o canales.',
      ),
      findsOneWidget,
    );
    expect(controller.selectedAreaId, 'area_SALA');
    expect(
      find.byKey(const ValueKey('desktop-area-area_SALA')),
      findsOneWidget,
    );

    // Confirmar con éxito: se elimina y la selección obsoleta se limpia.
    repo.deleteError = null;
    await openDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['area_SALA']);
    expect(controller.selectedAreaId, isNull);
    expect(find.byKey(const ValueKey('desktop-area-area_SALA')), findsNothing);
    expect(find.text('Selecciona un área'), findsOneWidget);
  });

  testWidgets('narrow fallback no overflow', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    await pumpDesktopAreas(tester, repo, size: const Size(700, 900));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('desktop-area-area_SALA')),
      findsOneWidget,
    );
    expect(find.text('Selecciona un área'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
    expect(_nameFieldText(tester), 'Sala');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop-area-area_SALA')),
      findsOneWidget,
    );
  });
}

Future<AdaptiveFeatureController> pumpDesktopAreas(
  WidgetTester tester,
  DeviceInventoryRepository repo, {
  Size size = const Size(1440, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = AdaptiveFeatureController(repo)..loadAreas();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppAdaptiveScope(
          windowClass: AppWindowClass.expanded,
          effectiveSurface: EffectiveAppSurface.desktop,
          controller: AdaptiveSurfaceModeController(),
          child: DesktopAreasPage(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

String? _nameFieldText(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField).first);
  return field.controller?.text;
}

Future<void> _focusAreaRow(WidgetTester tester, String areaId) async {
  final focus = tester.widget<Focus>(
    find
        .descendant(
          of: find.byKey(ValueKey('desktop-area-$areaId')),
          matching: find.byType(Focus),
        )
        .first,
  );
  focus.focusNode!.requestFocus();
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, focus.focusNode);
}
