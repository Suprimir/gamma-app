import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/routines/routines_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({List<Map<String, dynamic>>? routines})
    : routinesResult = routines ?? const [],
      super(baseUrl: 'http://test');

  List<Map<String, dynamic>> routinesResult;
  bool deleted = false;
  String? deletedId;
  String? updatedId;
  Map<String, dynamic>? updatedPayload;

  @override
  Future<List<Map<String, dynamic>>> routines() async => routinesResult;

  @override
  Future<Map<String, dynamic>> updateRoutine(
    String id,
    Map<String, dynamic> payload,
  ) async {
    updatedId = id;
    updatedPayload = payload;
    final i = routinesResult.indexWhere((r) => r['id'] == id);
    if (i != -1) {
      routinesResult[i] = {...routinesResult[i], 'enabled': payload['enabled']};
    }
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> catalog() async => {'locations': []};

  @override
  Future<List<Map<String, dynamic>>> modules() async => [
    {'name': 'spotify', 'enabled': true},
    {'name': 'news', 'enabled': true},
    {'name': 'cameras', 'enabled': true},
  ];

  @override
  Future<bool> deleteRoutine(String id) async {
    deleted = true;
    deletedId = id;
    routinesResult = [];
    return true;
  }

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

Map<String, dynamic> _routine(String id, String nombre, {int acciones = 1}) {
  return {
    'id': id,
    'nombre': nombre,
    'descripcion': 'Descripción de $nombre',
    'activadores': ['hola gamma', 'rutina'],
    'acciones': List.generate(acciones, (_) => {'intent': 'TURN_ON'}),
    'validation_errors': <String>[],
  };
}

Widget _host(ApiClient api) => MaterialApp(
  home: Scaffold(body: RoutinesPage(api: api)),
);

void main() {
  testWidgets('lista las rutinas y navega al editor', (tester) async {
    final api = _FakeApiClient(
      routines: [_routine('r1', 'Buenos días', acciones: 2)],
    );
    await tester.pumpWidget(_host(api));
    await tester.pump();

    expect(find.text('Rutinas'), findsOneWidget);
    expect(find.text('Nueva rutina'), findsOneWidget);
    expect(find.text('Buenos días'), findsOneWidget);
    expect(find.text('«hola gamma» · 2 acciones'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);

    await tester.tap(find.text('Nueva rutina'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 Acciones'), findsOneWidget);
    expect(find.text('Tu secuencia'), findsOneWidget);
  });

  testWidgets('vacío muestra el estado de primer arranque', (tester) async {
    final api = _FakeApiClient();
    await tester.pumpWidget(_host(api));
    await tester.pump();

    expect(
      find.text(
        'No hay rutinas configuradas. Crea la primera con «Nueva rutina».',
      ),
      findsOneWidget,
    );
  });

  testWidgets('eliminar rutina pide confirmación desde el menú ⋯', (
    tester,
  ) async {
    final api = _FakeApiClient(routines: [_routine('r1', 'Buenos días')]);
    await tester.pumpWidget(_host(api));
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pump();
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);

    await tester.tap(find.text('Eliminar'));
    await tester.pump();

    expect(find.text('Eliminar rutina'), findsOneWidget);
    expect(
      find.text('¿Eliminar "Buenos días"? Esta acción no se puede deshacer.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Eliminar').last);
    await tester.pump();
    await tester.pump();

    expect(api.deleted, isTrue);
    expect(api.deletedId, 'r1');
    expect(find.text('Buenos días'), findsNothing);
    expect(find.text('Rutina eliminada.'), findsOneWidget);
  });

  testWidgets('switch apaga y enciende la rutina', (tester) async {
    final api = _FakeApiClient(routines: [_routine('r1', 'Buenos días')]);
    await tester.pumpWidget(_host(api));
    await tester.pump();

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();

    expect(api.updatedId, 'r1');
    expect(api.updatedPayload?['enabled'], isFalse);
    expect(find.text('Rutina desactivada.'), findsOneWidget);
    expect(find.text('«hola gamma» · 1 acción · desactivada'), findsOneWidget);
  });

  testWidgets('rutina con errores de validación muestra aviso', (tester) async {
    final flawed = _routine('r2', 'Roto');
    flawed['validation_errors'] = ['falta acción'];
    final api = _FakeApiClient(routines: [flawed]);
    await tester.pumpWidget(_host(api));
    await tester.pump();

    expect(find.text('Requiere revisión'), findsOneWidget);
  });
}
