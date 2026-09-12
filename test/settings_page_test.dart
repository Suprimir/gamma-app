import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/modules/modules_section.dart';
import 'package:gamma_app/features/settings/settings_page.dart';
import 'package:gamma_app/features/settings/tts_preview_player.dart';

class _FakeSettingsApi extends ApiClient {
  _FakeSettingsApi({this.healthError, this.previewError})
    : super(baseUrl: 'http://test');

  Object? healthError;
  Object? previewError;
  String? previewVoice;
  String? previewText;

  @override
  Future<Map<String, dynamic>> health() async {
    final error = healthError;
    if (error != null) throw error;
    return {
      'status': 'ok',
      'device_mode': 'local',
      'writes_enabled': true,
      'uptime_seconds': 3725,
      'active_modules': ['voice', 'spotify', 'cameras'],
    };
  }

  @override
  Future<Uint8List> ttsPreview(String voice, String text) async {
    previewVoice = voice;
    previewText = text;
    final error = previewError;
    if (error != null) throw error;
    return Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0]);
  }

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

  // --- Configuración del núcleo -------------------------------------------

  Object? configError;
  Map<String, dynamic> configData = {
    'spotify': {
      'client_id': {'value': 'client-env', 'source': 'env'},
      'client_secret': {'configured': true, 'source': 'store', 'last4': '3784'},
      'device_name': {'value': 'GAMMA', 'source': 'store'},
      'market': {'value': 'MX', 'source': 'store'},
    },
    'news': {
      'api_key': {'configured': true, 'source': 'store', 'last4': '0e2f'},
    },
    'llm': {
      'gemini_api_key': {'configured': false, 'source': 'unset', 'last4': null},
    },
    'cameras': {
      'nvr_host': {'value': '', 'source': 'unset'},
      'nvr_port': {'value': '80', 'source': 'store'},
      'nvr_isapi_path': {'value': '/ISAPI', 'source': 'store'},
      'nvr_user': {'value': '', 'source': 'unset'},
      'nvr_pass': {'configured': false, 'source': 'unset', 'last4': null},
    },
  };

  @override
  Future<Map<String, dynamic>> configOverview() async {
    final error = configError;
    if (error != null) throw error;
    return configData;
  }

  final spotifyConfigCalls = <Map<String, Object?>>[];
  Map<String, dynamic> spotifyConfigResponse = const {};
  Object? spotifyConfigError;

  @override
  Future<Map<String, dynamic>> updateSpotifyConfig({
    String? clientId,
    String? clientSecret,
    String? deviceName,
    String? market,
  }) async {
    spotifyConfigCalls.add({
      'client_id': ?clientId,
      'client_secret': ?clientSecret,
      'device_name': ?deviceName,
      'market': ?market,
    });
    final error = spotifyConfigError;
    if (error != null) throw error;
    return spotifyConfigResponse;
  }

  final newsConfigCalls = <String>[];
  Map<String, dynamic> newsConfigResponse = const {};
  Object? newsConfigError;

  @override
  Future<Map<String, dynamic>> updateNewsConfig(String apiKey) async {
    newsConfigCalls.add(apiKey);
    final error = newsConfigError;
    if (error != null) throw error;
    return newsConfigResponse;
  }

  final llmConfigCalls = <String>[];
  Map<String, dynamic> llmConfigResponse = const {};
  Object? llmConfigError;

  @override
  Future<Map<String, dynamic>> updateLlmConfig(String apiKey) async {
    llmConfigCalls.add(apiKey);
    final error = llmConfigError;
    if (error != null) throw error;
    return llmConfigResponse;
  }

  final camerasConfigCalls = <Map<String, Object?>>[];
  Map<String, dynamic> camerasConfigResponse = const {};
  Object? camerasConfigError;

  @override
  Future<Map<String, dynamic>> updateCamerasConfig({
    String? nvrHost,
    int? nvrPort,
    String? nvrIsapiPath,
    String? nvrUser,
    String? nvrPass,
  }) async {
    camerasConfigCalls.add({
      'nvr_host': ?nvrHost,
      'nvr_port': ?nvrPort,
      'nvr_isapi_path': ?nvrIsapiPath,
      'nvr_user': ?nvrUser,
      'nvr_pass': ?nvrPass,
    });
    final error = camerasConfigError;
    if (error != null) throw error;
    return camerasConfigResponse;
  }

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

class _FakeTtsPlayer implements TtsPreviewPlayer {
  Uint8List? played;
  bool disposed = false;

  @override
  Future<void> play(Uint8List wavBytes) async => played = wavBytes;

  @override
  void dispose() => disposed = true;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  _FakeSettingsApi api, {
  _FakeTtsPlayer? player,
  Size size = const Size(600, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsPage(api: api, ttsPreviewPlayer: player),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('Ajustes integra módulos y normaliza una voz obsoleta', (
    tester,
  ) async {
    await _pumpSettings(tester, _FakeSettingsApi());

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

  testWidgets('Sistema muestra modo, escritura y uptime reales', (
    tester,
  ) async {
    await _pumpSettings(tester, _FakeSettingsApi());

    expect(find.text('Sistema'), findsOneWidget);
    expect(find.text('Control local'), findsOneWidget);
    expect(find.text('Escritura habilitada'), findsOneWidget);
    expect(find.text('1 h 2 min'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Sistema falla sin valores falsos y reintenta en el lugar', (
    tester,
  ) async {
    final api = _FakeSettingsApi(healthError: StateError('sin conexión'));
    await _pumpSettings(tester, api);

    expect(find.text('No se pudo leer el estado del sistema.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Escritura habilitada'), findsNothing);

    api.healthError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Escritura habilitada'), findsOneWidget);
    expect(find.text('No se pudo leer el estado del sistema.'), findsNothing);
  });

  testWidgets('Probar voz sintetiza con la voz elegida y la reproduce', (
    tester,
  ) async {
    final api = _FakeSettingsApi();
    final player = _FakeTtsPlayer();
    await _pumpSettings(tester, api, player: player);

    await tester.tap(find.text('Probar voz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.previewVoice, 'es-MX-DaliaNeural');
    expect(api.previewText, 'Hola, soy GAMMA. Así suena mi voz.');
    expect(player.played, [82, 73, 70, 70, 0, 0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Probar voz muestra el error real del backend', (tester) async {
    final api = _FakeSettingsApi(
      previewError: ApiException(502, {
        'detail': 'Error al sintetizar la voz.',
      }),
    );
    final player = _FakeTtsPlayer();
    await _pumpSettings(tester, api, player: player);

    await tester.tap(find.text('Probar voz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error al sintetizar la voz.'), findsOneWidget);
    expect(player.played, isNull);
  });

  testWidgets('Configuración muestra valores y nunca renderiza secretos', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      _FakeSettingsApi(),
      size: const Size(700, 3600),
    );

    expect(find.text('Configuración de Spotify'), findsOneWidget);
    expect(find.text('Noticias'), findsOneWidget);
    expect(find.text('Inteligencia artificial'), findsOneWidget);
    expect(find.text('Cámaras'), findsOneWidget);

    expect(_fieldText(tester, 'config-spotify-client-id'), 'client-env');
    expect(find.text('definido en .env'), findsOneWidget);
    expect(_fieldText(tester, 'config-spotify-client-secret'), isEmpty);
    expect(find.text('Configurado · últimos 4: 3784'), findsOneWidget);
    expect(_fieldText(tester, 'config-news-api-key'), isEmpty);
    expect(find.text('Configurado · últimos 4: 0e2f'), findsOneWidget);
    expect(_fieldText(tester, 'config-llm-api-key'), isEmpty);
    expect(find.text('Sin configurar'), findsWidgets);
    expect(_fieldText(tester, 'config-cameras-port'), '80');
    expect(_fieldText(tester, 'config-cameras-isapi-path'), '/ISAPI');
  });

  testWidgets('Spotify guarda solo lo modificado y avisa la reconexión', (
    tester,
  ) async {
    final api = _FakeSettingsApi()
      ..spotifyConfigResponse = {
        'applies': 'hot',
        'reconnect_required': true,
        'message': 'Credenciales actualizadas',
      };
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-spotify-device-name')),
      'GAMMA-2',
    );
    await tester.tap(find.byKey(const ValueKey('config-spotify-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.spotifyConfigCalls, [
      {'device_name': 'GAMMA-2'},
    ]);
    expect(find.text('Credenciales actualizadas'), findsOneWidget);
    expect(
      find.text('Reconectá tu cuenta para usar las credenciales nuevas'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('spotify-reconnect')), findsOneWidget);
  });

  testWidgets('Spotify muestra el mensaje 422 del backend', (tester) async {
    final api = _FakeSettingsApi()
      ..spotifyConfigError = ApiException(422, {
        'detail': 'El client_secret no puede estar vacío.',
      });
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-spotify-client-secret')),
      'secreto',
    );
    await tester.tap(find.byKey(const ValueKey('config-spotify-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.spotifyConfigCalls, [
      {'client_secret': 'secreto'},
    ]);
    expect(find.text('El client_secret no puede estar vacío.'), findsOneWidget);
  });

  testWidgets('Noticias guarda la API key, la limpia y muestra el mensaje', (
    tester,
  ) async {
    final api = _FakeSettingsApi()
      ..newsConfigResponse = {
        'applies': 'hot',
        'message': 'API key actualizada',
      };
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-news-api-key')),
      'clave-123',
    );
    await tester.tap(find.byKey(const ValueKey('config-news-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.newsConfigCalls, ['clave-123']);
    expect(find.text('API key actualizada'), findsOneWidget);
    expect(_fieldText(tester, 'config-news-api-key'), isEmpty);
  });

  testWidgets('Noticias muestra el 422 de validación', (tester) async {
    final api = _FakeSettingsApi()
      ..newsConfigError = ApiException(422, {'detail': 'API key inválida.'});
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-news-api-key')),
      'mala',
    );
    await tester.tap(find.byKey(const ValueKey('config-news-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('API key inválida.'), findsOneWidget);
    expect(_fieldText(tester, 'config-news-api-key'), 'mala');
  });

  testWidgets('IA guarda la clave y anuncia el reinicio del núcleo', (
    tester,
  ) async {
    final api = _FakeSettingsApi()
      ..llmConfigResponse = {
        'applies': 'restart_required',
        'message': 'Se aplicará al reiniciar el núcleo',
      };
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-llm-api-key')),
      'gemini-key',
    );
    await tester.tap(find.byKey(const ValueKey('config-llm-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.llmConfigCalls, ['gemini-key']);
    expect(find.text('Se aplicará al reiniciar el núcleo'), findsOneWidget);
    expect(_fieldText(tester, 'config-llm-api-key'), isEmpty);
  });

  testWidgets('Cámaras envía solo los campos modificados', (tester) async {
    final api = _FakeSettingsApi()
      ..camerasConfigResponse = {
        'applies': 'restart_required',
        'message': 'Configuración de cámaras actualizada',
      };
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-cameras-host')),
      '192.168.1.50',
    );
    await tester.enterText(
      find.byKey(const ValueKey('config-cameras-port')),
      '8080',
    );
    await tester.tap(find.byKey(const ValueKey('config-cameras-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.camerasConfigCalls, [
      {'nvr_host': '192.168.1.50', 'nvr_port': 8080},
    ]);
    expect(find.text('Configuración de cámaras actualizada'), findsOneWidget);
  });

  testWidgets('Cámaras rechaza un puerto no numérico', (tester) async {
    final api = _FakeSettingsApi();
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    await tester.enterText(
      find.byKey(const ValueKey('config-cameras-port')),
      'ochenta',
    );
    await tester.tap(find.byKey(const ValueKey('config-cameras-save')));
    await tester.pump();

    expect(find.text('El puerto debe ser un número.'), findsOneWidget);
    expect(api.camerasConfigCalls, isEmpty);
  });

  testWidgets('Configuración falla sin blanquear la página y reintenta', (
    tester,
  ) async {
    final api = _FakeSettingsApi()..configError = StateError('sin conexión');
    await _pumpSettings(tester, api, size: const Size(700, 3600));

    expect(
      find.text('No se pudo leer la configuración del núcleo.'),
      findsWidgets,
    );
    expect(find.text('Voz del asistente'), findsOneWidget);
    expect(find.text('Módulos'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);

    api.configError = null;
    await tester.tap(find.text('Reintentar').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Configuración de Spotify'), findsOneWidget);
    expect(_fieldText(tester, 'config-spotify-client-id'), 'client-env');
  });
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
