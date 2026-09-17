import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/routines/routines_editor_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://test');

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async =>
      {'devices': []};

  @override
  Future<List<Map<String, dynamic>>> modules() async => [
    {'name': 'spotify', 'enabled': true},
    {'name': 'news', 'enabled': true},
    {'name': 'cameras', 'enabled': true},
  ];
}

Widget _host(ApiClient api) => MaterialApp(
  home: Scaffold(body: RoutinesEditorPage(api: api, wallLayout: true)),
);

void main() {
  testWidgets('wall layout muestra el acomodo del boceto', (tester) async {
    await tester.pumpWidget(_host(_FakeApiClient()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Nueva rutina'), findsOneWidget);
    expect(find.text('Guardar rutina'), findsOneWidget);
    expect(find.text('Tu rutina'), findsOneWidget);
    expect(find.text('¿Qué quieres agregar?'), findsOneWidget);
    expect(find.text('Controla un dispositivo'), findsOneWidget);
    expect(find.text('Una ubicación'), findsOneWidget);
    expect(find.text('Reproduce en Spotify'), findsOneWidget);
    expect(find.text('Lee las noticias'), findsOneWidget);
    expect(find.text('Para activarla, di'), findsOneWidget);
    expect(find.text('Tu rutina hará'), findsOneWidget);
  });

  testWidgets('hover y tap con mouse no rompen el tracker', (tester) async {
    await tester.pumpWidget(_host(_FakeApiClient()));
    await tester.pump();
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await tester.pump();
    // Paseo sobre las tarjetas táctiles y el botón de guardar.
    await mouse.moveTo(tester.getCenter(find.text('Guardar rutina')));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Controla un dispositivo')));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Reproduce en Spotify')));
    await tester.pump();
    await mouse.moveTo(const Offset(10, 10));
    await tester.pump();

    expect(find.text('Nueva rutina'), findsOneWidget);
    expect(find.text('Guardar rutina'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('wall layout en ancho real usa dos columnas sin romper layout', (
    tester,
  ) async {
    // El viewport default de test (800px) cae en el acomodo angosto;
    // 1400px ejerce el de dos columnas, que es el que corre en la PC real.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(_FakeApiClient()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Nueva rutina'), findsOneWidget);
    expect(find.text('Guardar rutina'), findsOneWidget);
    expect(find.text('Tu rutina'), findsOneWidget);
    expect(find.text('¿Qué quieres agregar?'), findsOneWidget);
    expect(find.text('Controla un dispositivo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('push animado + mouse durante la transición', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoutinesEditorPage(
                      api: _FakeApiClient(),
                      wallLayout: true,
                    ),
                  ),
                ),
                child: const Text('Abrir editor'),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 100));
    await tester.pump();
    // Tap que inicia el push y mouse moviéndose a mitad de la animación.
    await tester.tap(find.text('Abrir editor'));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(const Offset(600, 400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Guardar rutina'), findsOneWidget);
    expect(find.text('Tu rutina'), findsOneWidget);
    await mouse.removePointer();
  });
}
