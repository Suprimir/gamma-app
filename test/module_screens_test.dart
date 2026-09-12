import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/settings/cameras_module_screen.dart';
import 'package:gamma_app/features/settings/llm_module_screen.dart';
import 'package:gamma_app/features/settings/news_module_screen.dart';
import 'package:gamma_app/features/settings/spotify_module_screen.dart';
import 'package:gamma_app/features/settings/tuya_module_screen.dart';

class _FakeConfigApi extends ApiClient {
  _FakeConfigApi() : super(baseUrl: 'http://test');

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
    'tuya': {
      'cloud_enabled': {'value': 'true', 'source': 'store'},
      'region': {'value': 'us', 'source': 'store'},
      'access_id': {'value': 'aid-123', 'source': 'store'},
      'api_secret': {'configured': true, 'source': 'store', 'last4': '9f2a'},
      'device_id': {'value': 'dev-42', 'source': 'store'},
    },
  };

  @override
  Future<Map<String, dynamic>> configOverview() async {
    final error = configError;
    if (error != null) throw error;
    return configData;
  }

  @override
  Future<Map<String, dynamic>> spotifySettings() async => {
    'authenticated': false,
    'client_id_configured': true,
  };

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

  final tuyaConfigCalls = <Map<String, Object?>>[];
  Map<String, dynamic> tuyaConfigResponse = const {};
  Object? tuyaConfigError;

  @override
  Future<Map<String, dynamic>> updateTuyaConfig({
    bool? cloudEnabled,
    String? region,
    String? accessId,
    String? apiSecret,
    String? deviceId,
  }) async {
    tuyaConfigCalls.add({
      'cloud_enabled': ?cloudEnabled,
      'region': ?region,
      'access_id': ?accessId,
      'api_secret': ?apiSecret,
      'device_id': ?deviceId,
    });
    final error = tuyaConfigError;
    if (error != null) throw error;
    return tuyaConfigResponse;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(600, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  group('SpotifyModuleScreen', () {
    testWidgets('renders connection + credentials and saves changed fields', (
      tester,
    ) async {
      final api = _FakeConfigApi()
        ..spotifyConfigResponse = {
          'applies': 'hot',
          'reconnect_required': false,
          'message': 'Credenciales actualizadas',
        };
      await _pumpScreen(tester, SpotifyModuleScreen(api: api));

      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Conexión'), findsOneWidget);
      expect(find.text('Conectar con Spotify'), findsOneWidget);
      expect(find.text('Credenciales de la app'), findsOneWidget);

      expect(_fieldText(tester, 'config-spotify-client-id'), 'client-env');
      expect(find.text('definido en .env'), findsOneWidget);
      expect(_fieldText(tester, 'config-spotify-client-secret'), isEmpty);
      expect(find.text('Configurado · últimos 4: 3784'), findsOneWidget);

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
    });

    testWidgets('sends a new secret alone and clears the field', (
      tester,
    ) async {
      final api = _FakeConfigApi();
      await _pumpScreen(tester, SpotifyModuleScreen(api: api));

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
      expect(_fieldText(tester, 'config-spotify-client-secret'), isEmpty);
    });

    testWidgets('reconnect_required shows the warning and connect action', (
      tester,
    ) async {
      final api = _FakeConfigApi()
        ..spotifyConfigResponse = {
          'applies': 'hot',
          'reconnect_required': true,
          'message': 'Credenciales actualizadas',
        };
      await _pumpScreen(tester, SpotifyModuleScreen(api: api));

      await tester.enterText(
        find.byKey(const ValueKey('config-spotify-device-name')),
        'GAMMA-2',
      );
      await tester.tap(find.byKey(const ValueKey('config-spotify-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Reconectá tu cuenta para usar las credenciales nuevas'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spotify-reconnect')), findsOneWidget);
    });

    testWidgets('shows the backend 422 detail inline', (tester) async {
      final api = _FakeConfigApi()
        ..spotifyConfigError = ApiException(422, {
          'detail': 'El client_secret no puede estar vacío.',
        });
      await _pumpScreen(tester, SpotifyModuleScreen(api: api));

      await tester.enterText(
        find.byKey(const ValueKey('config-spotify-client-secret')),
        'secreto',
      );
      await tester.tap(find.byKey(const ValueKey('config-spotify-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('El client_secret no puede estar vacío.'),
        findsOneWidget,
      );
    });
  });

  group('NewsModuleScreen', () {
    testWidgets('saves the key, clears it and shows the backend message', (
      tester,
    ) async {
      final api = _FakeConfigApi()
        ..newsConfigResponse = {
          'applies': 'hot',
          'message': 'API key actualizada',
        };
      await _pumpScreen(tester, NewsModuleScreen(api: api));

      expect(find.text('Noticias'), findsOneWidget);
      expect(_fieldText(tester, 'config-news-api-key'), isEmpty);
      expect(find.text('Configurado · últimos 4: 0e2f'), findsOneWidget);

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

    testWidgets('shows the 422 validation detail inline', (tester) async {
      final api = _FakeConfigApi()
        ..newsConfigError = ApiException(422, {'detail': 'API key inválida.'});
      await _pumpScreen(tester, NewsModuleScreen(api: api));

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
  });

  group('LlmModuleScreen', () {
    testWidgets('saves the key and announces the restart', (tester) async {
      final api = _FakeConfigApi()
        ..llmConfigResponse = {
          'applies': 'restart_required',
          'message': 'Se aplicará al reiniciar el núcleo',
        };
      await _pumpScreen(tester, LlmModuleScreen(api: api));

      expect(find.text('Inteligencia artificial'), findsOneWidget);
      expect(find.text('Sin configurar'), findsOneWidget);

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
  });

  group('CamerasModuleScreen', () {
    testWidgets('sends only the changed fields', (tester) async {
      final api = _FakeConfigApi()
        ..camerasConfigResponse = {
          'applies': 'restart_required',
          'message': 'Configuración de cámaras actualizada',
        };
      await _pumpScreen(tester, CamerasModuleScreen(api: api));

      expect(find.text('Cámaras'), findsOneWidget);
      expect(_fieldText(tester, 'config-cameras-port'), '80');
      expect(_fieldText(tester, 'config-cameras-isapi-path'), '/ISAPI');

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

    testWidgets('rejects a non-numeric port', (tester) async {
      final api = _FakeConfigApi();
      await _pumpScreen(tester, CamerasModuleScreen(api: api));

      await tester.enterText(
        find.byKey(const ValueKey('config-cameras-port')),
        'ochenta',
      );
      await tester.tap(find.byKey(const ValueKey('config-cameras-save')));
      await tester.pump();

      expect(find.text('El puerto debe ser un número.'), findsOneWidget);
      expect(api.camerasConfigCalls, isEmpty);
    });
  });

  group('TuyaModuleScreen', () {
    testWidgets('hydrates the section and sends only changed fields', (
      tester,
    ) async {
      final api = _FakeConfigApi()
        ..tuyaConfigResponse = {
          'applies': 'hot',
          'message': 'Credenciales de Tuya actualizadas',
        };
      await _pumpScreen(tester, TuyaModuleScreen(api: api));

      expect(find.text('Tuya'), findsOneWidget);
      expect(find.text('Nube Tuya'), findsOneWidget);
      expect(_fieldText(tester, 'config-tuya-access-id'), 'aid-123');
      expect(_fieldText(tester, 'config-tuya-device-id'), 'dev-42');
      expect(_fieldText(tester, 'config-tuya-api-secret'), isEmpty);
      expect(find.text('Configurado · últimos 4: 9f2a'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('config-tuya-cloud-enabled')),
            )
            .value,
        true,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('config-tuya-region')),
            )
            .initialValue,
        'us',
      );

      await tester.tap(find.byKey(const ValueKey('config-tuya-region')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cn').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('config-tuya-device-id')),
        'dev-99',
      );
      await tester.tap(find.byKey(const ValueKey('config-tuya-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.tuyaConfigCalls, [
        {'region': 'cn', 'device_id': 'dev-99'},
      ]);
      expect(find.text('Credenciales de Tuya actualizadas'), findsOneWidget);
    });

    testWidgets('a new secret is sent alone and a blank one keeps stored', (
      tester,
    ) async {
      final api = _FakeConfigApi();
      await _pumpScreen(tester, TuyaModuleScreen(api: api));

      // Disabling the cloud must send the boolean; the untouched secret must
      // not travel (an omitted secret keeps the stored one).
      await tester.tap(find.byKey(const ValueKey('config-tuya-cloud-enabled')));
      await tester.tap(find.byKey(const ValueKey('config-tuya-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.tuyaConfigCalls, [
        {'cloud_enabled': false},
      ]);

      await tester.enterText(
        find.byKey(const ValueKey('config-tuya-api-secret')),
        's3creto',
      );
      await tester.tap(find.byKey(const ValueKey('config-tuya-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.tuyaConfigCalls.last, {'api_secret': 's3creto'});
      expect(_fieldText(tester, 'config-tuya-api-secret'), isEmpty);
    });

    testWidgets('shows the no-changes notice without calling the API', (
      tester,
    ) async {
      final api = _FakeConfigApi();
      await _pumpScreen(tester, TuyaModuleScreen(api: api));

      await tester.tap(find.byKey(const ValueKey('config-tuya-save')));
      await tester.pump();

      expect(find.text('No hay cambios para guardar.'), findsOneWidget);
      expect(api.tuyaConfigCalls, isEmpty);
    });

    testWidgets('shows the backend validation detail inline', (tester) async {
      final api = _FakeConfigApi()
        ..tuyaConfigError = ApiException(422, {
          'detail': 'La región no es válida.',
        });
      await _pumpScreen(tester, TuyaModuleScreen(api: api));

      await tester.enterText(
        find.byKey(const ValueKey('config-tuya-access-id')),
        'aid-999',
      );
      await tester.tap(find.byKey(const ValueKey('config-tuya-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('La región no es válida.'), findsOneWidget);
      expect(_fieldText(tester, 'config-tuya-access-id'), 'aid-999');
    });
  });

  group('failure isolation', () {
    testWidgets('a missing section shows the unavailable notice', (
      tester,
    ) async {
      final api = _FakeConfigApi()..configData = const {'spotify': {}};
      await _pumpScreen(tester, NewsModuleScreen(api: api));

      expect(find.text('Esta sección no está disponible.'), findsOneWidget);
      expect(find.byKey(const ValueKey('config-news-api-key')), findsNothing);
    });

    testWidgets('a failed read shows retry and recovers in place', (
      tester,
    ) async {
      final api = _FakeConfigApi()..configError = StateError('sin conexión');
      await _pumpScreen(tester, NewsModuleScreen(api: api));

      expect(
        find.text('No se pudo leer la configuración del núcleo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);

      api.configError = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('No se pudo leer la configuración del núcleo.'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('config-news-api-key')), findsOneWidget);
    });
  });
}
