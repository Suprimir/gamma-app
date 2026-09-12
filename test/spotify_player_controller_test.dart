
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/spotify/spotify_player_controller.dart';

/// In-memory stand-in for the 13 playback endpoints: records every command
/// and lets each test flip the canonical state the next refresh will read.
class _FakeSpotifyApi extends ApiClient {
  _FakeSpotifyApi() : super(baseUrl: 'http://fake.test');

  Map<String, dynamic> player = {
    'has_playback': true,
    'is_playing': true,
    'track': {'name': 'Tema', 'artist': 'Artista', 'image_url': null},
    'device': {'id': 'dev_1', 'name': 'Parlante', 'volume_percent': 70},
    'shuffle': false,
    'repeat': 'off',
    'volume_percent': 70,
  };

  Map<String, dynamic> devices = {
    'devices': [
      {
        'id': 'dev_1',
        'name': 'Parlante',
        'is_active': true,
        'is_default': true,
        'volume_percent': 70,
      },
      {
        'id': 'dev_2',
        'name': 'Cocina',
        'is_active': false,
        'is_default': false,
        'volume_percent': 30,
      },
    ],
    'default_device_id': 'dev_1',
  };

  Object? playerError;
  Object? devicesError;
  Object? commandError;
  int playerCalls = 0;
  int deviceCalls = 0;
  final commands = <String>[];
  final commandDeviceIds = <String?>[];
  final commandUris = <String?>[];

  Map<String, dynamic> _command(String action, String? deviceId) {
    commands.add(action);
    commandDeviceIds.add(deviceId);
    if (commandError != null) throw commandError!;
    return {'ok': true, 'action': action, 'device_id': deviceId};
  }

  @override
  Future<Map<String, dynamic>> spotifyPlayer() async {
    playerCalls++;
    if (playerError != null) throw playerError!;
    return player;
  }

  @override
  Future<Map<String, dynamic>> spotifyDevices() async {
    deviceCalls++;
    if (devicesError != null) throw devicesError!;
    return devices;
  }

  @override
  Future<Map<String, dynamic>> spotifyPause({String? deviceId}) async =>
      _command('pause', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyResume({String? deviceId}) async =>
      _command('resume', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyNext({String? deviceId}) async =>
      _command('next', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyPrevious({String? deviceId}) async =>
      _command('previous', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyPlay({
    String? uri,
    String? contextUri,
    String? query,
    String? deviceId,
    int? positionMs,
  }) async {
    commandUris.add(uri ?? contextUri ?? query);
    return _command(uri != null ? 'playUri' : 'playContext', deviceId);
  }

  @override
  Future<Map<String, dynamic>> spotifySetVolume(
    int volumePercent, {
    String? deviceId,
  }) async => _command('volume:$volumePercent', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyTransfer(String deviceId) async =>
      _command('transfer', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyShuffle(
    bool state, {
    String? deviceId,
  }) async => _command('shuffle:$state', deviceId);

  @override
  Future<Map<String, dynamic>> spotifyRepeat(
    String state, {
    String? deviceId,
  }) async => _command('repeat:$state', deviceId);
}

void main() {
  test('refresh() carga player y devices y expone helpers canónicos', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);

    await controller.refresh();

    expect(controller.player, isNotNull);
    expect(controller.devices, hasLength(2));
    expect(controller.defaultDeviceId, 'dev_1');
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.needsAuth, isFalse);
    expect(controller.isPlaying, isTrue);
    expect(controller.track?['name'], 'Tema');
    expect(controller.activeDevice?['name'], 'Parlante');
    expect(api.playerCalls, 1);
    expect(api.deviceCalls, 1);
    controller.dispose();
  });

  test(
    'refresh() con 503 marca needsAuth sin lanzar y sin inventar player',
    () async {
      final api = _FakeSpotifyApi()
        ..playerError = ApiException(503, {
          'detail': 'Spotify no está autorizado. Conecta tu cuenta en Ajustes.',
        });
      final controller = SpotifyPlayerController(api);

      await controller.refresh();

      expect(controller.needsAuth, isTrue);
      expect(controller.error, isNull);
      expect(controller.player, isNull);
      // Devices are an independent call: a 503 player must not erase them.
      expect(controller.devices, hasLength(2));
      controller.dispose();
    },
  );

  test('refresh() con 401 también marca needsAuth', () async {
    final api = _FakeSpotifyApi()
      ..playerError = ApiException(401, {'detail': 'Sesión expirada.'});
    final controller = SpotifyPlayerController(api);

    await controller.refresh();

    expect(controller.needsAuth, isTrue);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('el fallo de devices es no fatal y conserva los conocidos', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    await controller.refresh();

    api.devicesError = ApiException(500, {'detail': 'devices caídos'});
    await controller.refresh();

    expect(controller.error, isNull);
    expect(controller.devices, hasLength(2));
    expect(controller.devices.first['id'], 'dev_1');
    controller.dispose();
  });

  test(
    'un player con fallo no-auth expone el detail y limpia player',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);
      await controller.refresh();

      api.playerError = ApiException(409, {
        'detail': 'Sin dispositivo activo.',
      });
      await controller.refresh();

      expect(controller.needsAuth, isFalse);
      expect(controller.player, isNull);
      expect(controller.error, 'Sin dispositivo activo.');
      controller.dispose();
    },
  );

  test(
    'los comandos usan selectedDeviceId y refrescan tras ejecutar',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);
      await controller.refresh();
      final refreshesBefore = api.playerCalls;

      controller.selectDevice('dev_2');
      await controller.pause();
      await controller.play();
      await controller.next();
      await controller.previous();
      await controller.playContext('spotify:playlist:42');
      await controller.playUri('spotify:track:7');
      await controller.setVolume(35);
      await controller.shuffle(true);
      await controller.repeat('context');

      expect(api.commands, [
        'pause',
        'resume',
        'next',
        'previous',
        'playContext',
        'playUri',
        'volume:35',
        'shuffle:true',
        'repeat:context',
      ]);
      expect(api.commandDeviceIds, everyElement('dev_2'));
      expect(
        api.commandUris,
        containsAll(['spotify:playlist:42', 'spotify:track:7']),
      );
      expect(api.playerCalls, refreshesBefore + 9);
      controller.dispose();
    },
  );

  test('sin selección explícita el backend resuelve el dispositivo', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    await controller.refresh();

    await controller.pause();
    await controller.playContext('spotify:playlist:1');

    expect(api.commandDeviceIds, everyElement(isNull));
    controller.dispose();
  });

  test(
    'transferTo() selecciona y transfiere; selectDevice(null) limpia',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);
      await controller.refresh();

      await controller.transferTo('dev_2');
      expect(controller.selectedDeviceId, 'dev_2');
      expect(api.commands, ['transfer']);
      expect(api.commandDeviceIds, ['dev_2']);
      // The player response still reports dev_1 (the fake does not mutate):
      // activeDevice stays canonical and never fabricates the transfer.
      expect(controller.activeDevice?['id'], 'dev_1');

      controller.selectDevice(null);
      expect(controller.selectedDeviceId, isNull);
      expect(controller.activeDevice?['id'], 'dev_1');
      controller.dispose();
    },
  );

  test('los errores de comando se exponen sin lanzarse al llamador', () async {
    final api = _FakeSpotifyApi()
      ..commandError = ApiException(409, {
        'detail': 'No hay dispositivo activo para reproducir.',
      });
    final controller = SpotifyPlayerController(api);
    await controller.refresh();

    await controller.pause();

    expect(controller.error, 'No hay dispositivo activo para reproducir.');
    expect(controller.needsAuth, isFalse);
    controller.dispose();
  });

  test(
    'startPolling refresca periódicamente y stopPolling lo cancela',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);

      controller.startPolling(interval: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final polled = api.playerCalls;
      expect(polled, greaterThanOrEqualTo(2));

      controller.stopPolling();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.playerCalls, polled);
      controller.dispose();
    },
  );

  test('startPolling con Duration.zero no programa ningún timer', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);

    controller.startPolling(interval: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(api.playerCalls, 0);
    controller.dispose();
  });
}
