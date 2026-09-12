import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/modules/modules_section.dart';
import 'package:gamma_app/features/settings/cameras_module_screen.dart';
import 'package:gamma_app/features/settings/llm_module_screen.dart';
import 'package:gamma_app/features/settings/news_module_screen.dart';
import 'package:gamma_app/features/settings/settings_page.dart';
import 'package:gamma_app/features/settings/spotify_module_screen.dart';
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

  /// Minimal redacted view so the pushed module screens render their fields.
  @override
  Future<Map<String, dynamic>> configOverview() async => {
    'spotify': {
      'client_id': {'value': 'client-env', 'source': 'env'},
      'client_secret': {'configured': true, 'source': 'store', 'last4': '3784'},
      'device_name': {'value': 'GAMMA', 'source': 'store'},
      'market': {'value': 'MX', 'source': 'store'},
    },
    'llm': {
      'gemini_api_key': {'configured': false, 'source': 'unset', 'last4': null},
    },
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
    {
      'name': 'news',
      'display_name': 'Noticias module',
      'description': 'Titulares del día.',
      'enabled': true,
      'required': false,
    },
    {
      'name': 'cameras',
      'display_name': 'Cámaras module',
      'description': 'Snapshots del NVR.',
      'enabled': true,
      'required': false,
    },
    {
      'name': 'domotics',
      'display_name': 'Domótica module',
      'description': 'Control de dispositivos.',
      'enabled': true,
      'required': true,
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

  testWidgets('la página principal es solo de sistema, sin config de módulos', (
    tester,
  ) async {
    await _pumpSettings(tester, _FakeSettingsApi());

    expect(find.text('Voz del asistente'), findsOneWidget);
    expect(find.text('Modo de interfaz'), findsOneWidget);
    expect(find.text('Módulos'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);

    // Module-scoped configuration moved to its own screens.
    expect(find.text('Configuración de Spotify'), findsNothing);
    expect(find.text('Credenciales de la app'), findsNothing);
    expect(find.text('Gemini API key'), findsNothing);
    expect(find.text('Host del NVR'), findsNothing);
  });

  testWidgets('el engranaje abre la pantalla del módulo y domótica no tiene', (
    tester,
  ) async {
    await _pumpSettings(tester, _FakeSettingsApi());

    // Domotics has no configuration screen: never a gear.
    expect(
      find.byKey(const ValueKey('module-configure-domotics')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('module-configure-spotify')));
    await tester.pumpAndSettle();
    expect(find.byType(SpotifyModuleScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('module-configure-news')));
    await tester.pumpAndSettle();
    expect(find.byType(NewsModuleScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('module-configure-cameras')));
    await tester.pumpAndSettle();
    expect(find.byType(CamerasModuleScreen), findsOneWidget);
  });

  testWidgets('la tarjeta de IA abre la pantalla de la clave de Gemini', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      _FakeSettingsApi(),
      size: const Size(600, 1800),
    );

    expect(find.text('Inteligencia artificial'), findsOneWidget);
    expect(find.text('Clave de Gemini y ajustes del modelo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-ai-config')));
    await tester.pumpAndSettle();

    expect(find.byType(LlmModuleScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('config-llm-api-key')), findsOneWidget);
    expect(find.byKey(const ValueKey('config-llm-save')), findsOneWidget);
  });
}
