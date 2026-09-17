import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/routines/routines_editor_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://test');

  Map<String, dynamic>? createdPayload;

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    return {
      'devices': [
        {
          'device_id': 'dev_1',
          'display_name': 'Luz salón',
          'physical_area_id': 'area_salon',
          'endpoints': [
            {
              'endpoint_id': 'relay_1',
              'enabled': true,
              'exposed_to_resolver': true,
              'controlled_area_id': 'area_salon',
              'display_name_global': 'Salón · Luz',
              'capabilities': [
                {'capability': 'POWER', 'writable': true},
              ],
            },
          ],
        },
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> areas() async => [
    {'id': 'area_salon', 'name': 'Salón', 'aliases': <String>[]},
  ];

  @override
  Future<List<Map<String, dynamic>>> modules() async => [
    {'name': 'spotify', 'enabled': true},
    {'name': 'news', 'enabled': true},
    {'name': 'cameras', 'enabled': true},
  ];

  @override
  Future<Map<String, dynamic>> createRoutine(Map<String, dynamic> payload) async {
    createdPayload = payload;
    return {'routine': {...payload, 'id': 'r1'}, 'message': 'ok'};
  }
}

Widget _host(ApiClient api) => MaterialApp(
  home: Scaffold(body: RoutinesEditorPage(api: api, wallLayout: true)),
);

void main() {
  testWidgets('guarda una acción de dispositivo con device_id canónico', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApiClient();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    // 1. Abre la tarjeta de dispositivo y elige área, objetivo y acción.
    await tester.tap(find.text('Controla un dispositivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salón'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salón · Luz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar a la secuencia'));
    await tester.pumpAndSettle();

    // 2. Completa nombre y frase de activación.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Buenos días');
    await tester.enterText(fields.at(1), 'buenos dias');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 3. Guarda.
    await tester.tap(find.text('Guardar rutina'));
    await tester.pumpAndSettle();

    final acciones = api.createdPayload?['acciones'] as List?;
    expect(acciones, hasLength(1));
    final action = acciones!.single as Map<String, dynamic>;
    expect(action['scope'], 'SINGLE');
    expect(action['intent'], 'TURN_ON');
    expect(action['device_id'], 'dev_1:relay_1');
    expect(action['location'], 'area_salon');
    expect(action.containsKey('device'), isFalse);
  });
}
