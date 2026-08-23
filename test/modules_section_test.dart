import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/modules/modules_section.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://test');

  List<Map<String, dynamic>> moduleList = [
    {
      'name': 'domotics',
      'display_name': 'Domótica',
      'description': 'Controla luces, ventiladores y persianas de la casa.',
      'enabled': true,
      'required': true,
      'state': 'enabled',
    },
    {
      'name': 'spotify',
      'display_name': 'Spotify',
      'description': 'Reproduce música y playlists en tus dispositivos.',
      'enabled': false,
      'state': 'disabled',
    },
    {
      'name': 'news',
      'display_name': 'Noticias',
      'description': 'Lee las noticias del día cuando lo pidas.',
      'enabled': true,
      'state': 'enabled',
    },
  ];

  String? toggledName;
  bool? toggledEnabled;
  bool? responseEnabled;
  Object? toggleError;

  @override
  Future<List<Map<String, dynamic>>> modules() async => moduleList;

  @override
  Future<Map<String, dynamic>> setModule(String name, bool enabled) async {
    toggledName = name;
    toggledEnabled = enabled;
    if (toggleError != null) throw toggleError!;
    return {
      'name': name,
      'enabled': responseEnabled ?? enabled,
      'message': responseEnabled == null || responseEnabled == enabled
          ? 'ok'
          : 'El módulo no puede cambiar de estado.',
    };
  }

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

Widget _host(ApiClient api) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: ModulesSection(api: api)),
  ),
);

void _setPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('móvil: módulos aparecen como filas sin overflow', (
    tester,
  ) async {
    _setPhoneSize(tester);
    await tester.pumpWidget(_host(_FakeApiClient()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Domótica'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('Noticias'), findsOneWidget);
    expect(find.text('· necesario'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggle llama a setModule y confirma con el servidor', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final api = _FakeApiClient();
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('module-switch-spotify')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.toggledName, 'spotify');
    expect(api.toggledEnabled, isTrue);
    final switchWidget = tester.widget<Switch>(
      find.byKey(const ValueKey('module-switch-spotify')),
    );
    expect(switchWidget.value, isTrue);
  });

  testWidgets(
    'si el backend rechaza el estado, prevalece la verdad del servidor',
    (tester) async {
      _setPhoneSize(tester);
      final api = _FakeApiClient()..responseEnabled = false;
      await tester.pumpWidget(_host(api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('module-switch-spotify')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final switchWidget = tester.widget<Switch>(
        find.byKey(const ValueKey('module-switch-spotify')),
      );
      expect(switchWidget.value, isFalse);
      expect(
        find.text('El módulo no puede cambiar de estado.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('un error de red revierte el toggle optimista', (tester) async {
    _setPhoneSize(tester);
    final api = _FakeApiClient()..toggleError = StateError('sin conexión');
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('module-switch-spotify')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final switchWidget = tester.widget<Switch>(
      find.byKey(const ValueKey('module-switch-spotify')),
    );
    expect(switchWidget.value, isFalse);
    expect(find.textContaining('sin conexión'), findsOneWidget);
  });
}
