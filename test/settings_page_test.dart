import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/modules/modules_section.dart';
import 'package:gamma_app/features/settings/settings_page.dart';

class _FakeSettingsApi extends ApiClient {
  _FakeSettingsApi() : super(baseUrl: 'http://test');

  @override
  Future<Map<String, dynamic>> ttsSettings() async => {
    'edge_voice': 'voice-that-no-longer-exists',
  };

  @override
  Future<Map<String, dynamic>> ttsVoices() async => {
    'edge': [
      {
        'id': 'es-MX-DaliaNeural',
        'name': 'Dalia',
        'locale': 'es-MX',
        'gender': 'Female',
      },
      {
        'id': 'en-US-JennyNeural',
        'name': 'Jenny',
        'locale': 'en-US',
        'gender': 'Female',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> spotifySettings() async => {
    'authenticated': false,
    'client_id_configured': true,
  };

  @override
  Future<List<Map<String, dynamic>>> modules() async => [
    {
      'name': 'spotify',
      'display_name': 'Spotify module',
      'description': 'Control multimedia.',
      'enabled': true,
      'required': false,
    },
  ];

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  testWidgets('Ajustes integra módulos y normaliza una voz obsoleta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(api: _FakeSettingsApi())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.byType(ModulesSection), findsOneWidget);
    expect(find.text('Módulos'), findsOneWidget);
    expect(find.text('Spotify module'), findsOneWidget);

    final voice = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('voice-select-es')),
    );
    expect(voice.initialValue, 'es-MX-DaliaNeural');
    expect(tester.takeException(), isNull);
  });
}
