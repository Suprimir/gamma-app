import 'dart:async';

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
  Object? queueError;
  Object? commandError;
  int playerCalls = 0;
  int deviceCalls = 0;
  int queueCalls = 0;
  int eventsCalls = 0;
  final commands = <String>[];
  final commandDeviceIds = <String?>[];
  final commandUris = <String?>[];

  /// When set, the next [spotifyPlayer] call awaits this before answering:
  /// used to hold an HTTP read in flight across an SSE event.
  Completer<Map<String, dynamic>>? playerCompleter;

  /// When set, the next [spotifyDevices] call awaits this before answering:
  /// used to hold the tail of a refresh in flight across an SSE event.
  Completer<Map<String, dynamic>>? devicesCompleter;

  /// When set, [spotifySeek] awaits this before answering: used to observe
  /// the optimistic preview while the seek request is in flight.
  Completer<Map<String, dynamic>>? seekCompleter;

  /// Queue listing returned by [spotifyPlaybackQueue].
  Map<String, dynamic> queue = {
    'previous': [],
    'upcoming': [],
    'limited': false,
  };

  /// SSE stand-in: the controller subscribes through [events] and tests push
  /// frames with [emitEvent]. Never closes on its own, so no resubscribe
  /// timers fire in tests.
  final eventsController = StreamController<Map<String, dynamic>>.broadcast();

  int _nextEventId = 0;

  /// Pushes the REAL production frame shape: [ApiClient.events] yields
  /// `{'event': <name>, 'data': <envelope>}`, where the decoded bus envelope
  /// is `{id, event, data, timestamp}` and the actual payload sits one level
  /// deeper.
  void emitEvent(String name, Map<String, dynamic> data) {
    _nextEventId++;
    emitEnvelope({
      'id': _nextEventId,
      'event': name,
      'data': data,
      'timestamp': _nextEventId,
    });
  }

  /// Pushes a raw bus envelope as the stream frame; the regression tests use
  /// it to pin the production nesting explicitly.
  void emitEnvelope(Map<String, dynamic> envelope) {
    eventsController.add({'event': envelope['event'], 'data': envelope});
  }

  Future<void> close() => eventsController.close();

  Map<String, dynamic> _command(String action, String? deviceId) {
    commands.add(action);
    commandDeviceIds.add(deviceId);
    if (commandError != null) throw commandError!;
    return {'ok': true, 'action': action, 'device_id': deviceId};
  }

  @override
  Stream<Map<String, dynamic>> events() {
    eventsCalls++;
    return eventsController.stream;
  }

  @override
  Future<Map<String, dynamic>> spotifyPlaybackQueue({int limit = 20}) async {
    queueCalls++;
    if (queueError != null) throw queueError!;
    return queue;
  }

  @override
  Future<Map<String, dynamic>> spotifyPlayer() async {
    playerCalls++;
    if (playerError != null) throw playerError!;
    final held = playerCompleter;
    if (held != null) return held.future;
    return player;
  }

  @override
  Future<Map<String, dynamic>> spotifyDevices() async {
    deviceCalls++;
    if (devicesError != null) throw devicesError!;
    final held = devicesCompleter;
    if (held != null) return held.future;
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
  Future<Map<String, dynamic>> spotifySeek(
    int positionMs, {
    String? deviceId,
  }) async {
    final held = seekCompleter;
    if (held != null) await held.future;
    return _command('seek:$positionMs', deviceId);
  }

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

  test('seek() clampa negativos, usa el device pick y refresca', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    await controller.refresh();
    final refreshesBefore = api.playerCalls;

    controller.selectDevice('dev_2');
    await controller.seek(45000);
    await controller.seek(-100);

    expect(api.commands, ['seek:45000', 'seek:0']);
    expect(api.commandDeviceIds, everyElement('dev_2'));
    expect(api.playerCalls, refreshesBefore + 2);
    controller.dispose();
  });

  test(
    'seek() muestra la posición optimista y avanza con el speed capturado',
    () async {
      var now = 1000000;
      final api = _FakeSpotifyApi();
      api.player = {
        ...api.player,
        'track': {
          'name': 'Tema',
          'artist': 'Artista',
          'image_url': null,
          'duration_ms': 30000,
        },
        'position': {'position_ms': 2000, 'timestamp_ms': 999000, 'speed': 2.0},
      };
      final controller = SpotifyPlayerController(api, nowMs: () => now);
      await controller.refresh();

      // Hold the seek request: the pending preview must be visible anyway.
      api.seekCompleter = Completer<Map<String, dynamic>>();
      final future = controller.seek(5000);
      expect(controller.progressMs, 5000);

      now += 400;
      expect(controller.progressMs, 5800);

      // Clamped to the canonical duration.
      now += 60000;
      expect(controller.progressMs, 30000);

      api.seekCompleter!.complete({'ok': true});
      await future;
      controller.dispose();
    },
  );

  test('seek() pausado deja el preview fijo en el objetivo', () async {
    var now = 1000000;
    final api = _FakeSpotifyApi();
    api.player = {
      ...api.player,
      'is_playing': false,
      'track': {
        'name': 'Tema',
        'artist': 'Artista',
        'image_url': null,
        'duration_ms': 30000,
      },
    };
    final controller = SpotifyPlayerController(api, nowMs: () => now);
    await controller.refresh();

    api.seekCompleter = Completer<Map<String, dynamic>>();
    final future = controller.seek(7000);
    expect(controller.progressMs, 7000);

    now += 5000;
    expect(controller.progressMs, 7000);

    api.seekCompleter!.complete({'ok': true});
    await future;
    controller.dispose();
  });

  test('un anchor canónico más nuevo limpia el pending del seek', () async {
    var now = 1000000;
    final api = _FakeSpotifyApi();
    api.player = {
      ...api.player,
      'track': {
        'name': 'Tema',
        'artist': 'Artista',
        'image_url': null,
        'duration_ms': 30000,
      },
    };
    final controller = SpotifyPlayerController(api, nowMs: () => now);
    await controller.refresh();

    // The next canonical read carries an anchor measured after the seek.
    api.player = {
      ...api.player,
      'position': {'position_ms': 5200, 'timestamp_ms': now + 1, 'speed': 1.0},
    };
    api.seekCompleter = Completer<Map<String, dynamic>>();
    final future = controller.seek(5000);
    expect(controller.progressMs, 5000);

    await controller.refresh();
    now = 1000301;
    // Acknowledged: interpolation from the canonical anchor (5200 + 300).
    expect(controller.progressMs, 5500);

    api.seekCompleter!.complete({'ok': true});
    await future;
    controller.dispose();
  });

  test('el pending del seek expira por seguridad a los ~10s', () async {
    var now = 1000000;
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api, nowMs: () => now);
    await controller.refresh();

    api.seekCompleter = Completer<Map<String, dynamic>>();
    final future = controller.seek(5000);
    expect(controller.progressMs, 5000);

    now += 10001;
    // Dropped: no canonical anchor in the fake player, so null.
    expect(controller.progressMs, isNull);

    api.seekCompleter!.complete({'ok': true});
    await future;
    controller.dispose();
  });

  test('un seek fallido limpia el pending y expone el error', () async {
    var now = 1000000;
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api, nowMs: () => now);
    await controller.refresh();

    api.commandError = ApiException(409, {'detail': 'Sin dispositivo activo.'});
    api.seekCompleter = Completer<Map<String, dynamic>>();
    final future = controller.seek(5000);
    expect(controller.progressMs, 5000);
    api.seekCompleter!.complete({'ok': true});
    await future;

    expect(controller.error, 'Sin dispositivo activo.');
    // Pending dropped: the fake player has no anchor/progress_ms.
    expect(controller.progressMs, isNull);
    controller.dispose();
  });

  test('un refresh con player viejo no pisa un estado SSE más nuevo', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    await controller.refresh();
    controller.startPolling(interval: const Duration(hours: 1));
    expect(api.eventsCalls, 1);

    // Hold the next HTTP player read.
    api.playerCompleter = Completer<Map<String, dynamic>>();
    final refreshFuture = controller.refresh();

    // A fresher SSE state lands while the HTTP read is in flight.
    api.emitEvent('spotify_state_changed', {
      'status': 'paused',
      'item': {
        'uri': 'spotify:track:9',
        'name': 'SSE Tema',
        'artist': 'SSE Artista',
        'album': null,
        'image_url': null,
      },
    });
    await pumpEventQueue();
    expect(controller.track?['name'], 'SSE Tema');

    // The stale HTTP body must not overwrite the SSE value.
    api.playerCompleter!.complete({
      'has_playback': true,
      'is_playing': true,
      'track': {
        'uri': 'spotify:track:1',
        'name': 'HTTP Tema',
        'artist': 'Artista',
        'album': null,
        'image_url': null,
      },
      'device': {'id': 'dev_1', 'name': 'Parlante', 'volume_percent': 70},
      'shuffle': false,
      'repeat': 'off',
      'volume_percent': 70,
    });
    await refreshFuture;

    expect(controller.track?['name'], 'SSE Tema');
    expect(controller.isPlaying, isFalse);
    controller.dispose();
    await api.close();
  });

  test(
    'un SSE durante devices tampoco deja pisar el estado con el player viejo',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);
      await controller.refresh();
      controller.startPolling(interval: const Duration(hours: 1));

      // The player read resolves first; devices is held while SSE lands.
      api.devicesCompleter = Completer<Map<String, dynamic>>();
      final refreshFuture = controller.refresh();
      await pumpEventQueue();

      api.emitEvent('spotify_state_changed', {
        'status': 'paused',
        'item': {
          'uri': 'spotify:track:9',
          'name': 'SSE Tema',
          'artist': 'SSE Artista',
          'album': null,
          'image_url': null,
        },
      });
      await pumpEventQueue();
      expect(controller.track?['name'], 'SSE Tema');

      // The refresh tail completes late: the stale player body must lose.
      api.devicesCompleter!.complete(api.devices);
      await refreshFuture;

      expect(controller.track?['name'], 'SSE Tema');
      expect(controller.isPlaying, isFalse);
      controller.dispose();
      await api.close();
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
    expect(api.queueCalls, 0);
    expect(api.eventsCalls, 0);
    controller.dispose();
  });

  test(
    'refresh() carga la cola y un fallo de cola conserva la conocida',
    () async {
      final api = _FakeSpotifyApi()
        ..queue = {
          'previous': [
            {'uri': 'spotify:track:1', 'name': 'Anterior', 'artist': 'A'},
          ],
          'upcoming': [
            {'uri': 'spotify:track:2', 'name': 'Siguiente', 'artist': 'B'},
          ],
          'limited': true,
        };
      final controller = SpotifyPlayerController(api);
      await controller.refresh();

      expect(controller.previousQueue, hasLength(1));
      expect(controller.upcomingQueue, hasLength(1));
      expect(controller.upcomingQueue.first['name'], 'Siguiente');
      expect(controller.queueLimited, isTrue);
      expect(api.queueCalls, 1);

      api.queueError = ApiException(500, {'detail': 'cola caída'});
      await controller.refresh();

      expect(controller.error, isNull);
      expect(controller.upcomingQueue.first['name'], 'Siguiente');
      controller.dispose();
    },
  );

  test('spotify_state_changed mergea el estado sin fabricar device', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    await controller.refresh();
    controller.startPolling(interval: const Duration(hours: 1));
    expect(api.eventsCalls, 1);

    api.emitEvent('spotify_state_changed', {
      'status': 'playing',
      'is_active': true,
      'volume': 42,
      'shuffle': true,
      'repeat': 'context',
      'item': {
        'uri': 'spotify:track:9',
        'name': 'Nueva',
        'artist': 'Otra',
        'album': null,
        'image_url': null,
        'duration_ms': 180000,
      },
      'position': {'position_ms': 5000, 'timestamp_ms': 1000000, 'speed': 1.0},
      'actions': ['play', 'pause', 'skip_next', 'skip_prev'],
    });
    await pumpEventQueue();

    expect(controller.player?['has_playback'], true);
    expect(controller.isPlaying, isTrue);
    expect(controller.track?['name'], 'Nueva');
    expect(controller.player?['volume_percent'], 42);
    expect(controller.player?['shuffle'], true);
    expect(controller.player?['repeat'], 'context');
    expect(controller.progressMs, isNotNull);
    expect(controller.actionEnabled('skip_next'), isTrue);
    expect(controller.actionEnabled('seek'), isFalse);
    // The event carries no device: the previous player's map is preserved.
    expect(controller.activeDevice?['name'], 'Parlante');

    // buffering counts as playing for the transport affordance.
    api.emitEvent('spotify_state_changed', {
      'status': 'buffering',
      'item': null,
      'position': {'position_ms': 0, 'timestamp_ms': 0, 'speed': 0.0},
    });
    await pumpEventQueue();
    expect(controller.isPlaying, isTrue);

    controller.dispose();
    await api.close();
  });

  test(
    'un frame con envelope actualiza track e isPlaying de inmediato',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);
      controller.startPolling(interval: const Duration(hours: 1));

      // Raw shape yielded by ApiClient.events(): the bus envelope nests the
      // real payload under `data`. The old handler applied the envelope
      // itself, so `status`/`item` were absent, `isPlaying` stayed stale and
      // the card only converged on the next fallback poll.
      api.emitEnvelope({
        'id': 1,
        'event': 'spotify_state_changed',
        'data': {
          'status': 'playing',
          'item': {
            'uri': 'spotify:track:9',
            'name': 'OJALA',
            'artist': 'Artista',
            'duration_ms': 180000,
          },
          'position': {'position_ms': 0, 'timestamp_ms': 0, 'speed': 1.0},
        },
        'timestamp': 1234,
      });
      await pumpEventQueue();

      expect(controller.track?['name'], 'OJALA');
      expect(controller.isPlaying, isTrue);
      controller.dispose();
      await api.close();
    },
  );

  test('spotify_queue_changed guarda previous/upcoming/limited', () async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    controller.startPolling(interval: const Duration(hours: 1));

    // Same production nesting as the state frame: envelope under `data`.
    api.emitEnvelope({
      'id': 2,
      'event': 'spotify_queue_changed',
      'data': {
        'previous': [
          {'uri': 'spotify:track:1', 'name': 'Antes', 'artist': 'A'},
        ],
        'upcoming': [
          {'uri': 'spotify:track:2', 'name': 'Después', 'artist': 'B'},
        ],
        'limited': true,
      },
      'timestamp': 5678,
    });
    await pumpEventQueue();

    expect(controller.previousQueue, hasLength(1));
    expect(controller.upcomingQueue.single['name'], 'Después');
    expect(controller.queueLimited, isTrue);
    controller.dispose();
    await api.close();
  });

  test(
    'actionEnabled respeta la lista del backend y el fallback vacío',
    () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);

      // No player yet: no advertised list means the legacy gating applies.
      expect(controller.actionEnabled('skip_next'), isTrue);
      await controller.refresh();
      expect(controller.actionEnabled('skip_next'), isTrue);

      api.player = {
        ...api.player,
        'actions': ['play', 'skip_next'],
      };
      await controller.refresh();

      expect(controller.actionEnabled('skip_next'), isTrue);
      expect(controller.actionEnabled('skip_prev'), isFalse);
      expect(controller.actionEnabled('pause'), isFalse);
      controller.dispose();
    },
  );

  group('interpolatedPositionMs', () {
    test('proyecta el ancla con speed', () {
      expect(
        interpolatedPositionMs({
          'track': {'duration_ms': 30000},
          'position': {'position_ms': 5000, 'timestamp_ms': 1000, 'speed': 2.0},
        }, nowMs: 2000),
        7000,
      );
    });

    test('clampa a [0, duration_ms]', () {
      expect(
        interpolatedPositionMs({
          'track': {'duration_ms': 10000},
          'position': {'position_ms': 9000, 'timestamp_ms': 0, 'speed': 1.0},
        }, nowMs: 5000),
        10000,
      );
      expect(
        interpolatedPositionMs({
          'track': {'duration_ms': 10000},
          'position': {'position_ms': 1000, 'timestamp_ms': 2000, 'speed': 1.0},
        }, nowMs: 0),
        0,
      );
    });

    test('speed <= 0 devuelve position_ms sin proyectar', () {
      expect(
        interpolatedPositionMs({
          'track': {'duration_ms': 10000},
          'position': {'position_ms': 2500, 'timestamp_ms': 0, 'speed': 0.0},
        }, nowMs: 9000),
        2500,
      );
    });

    test('sin ancla usa track.progress_ms', () {
      expect(
        interpolatedPositionMs({
          'track': {'progress_ms': 1234, 'duration_ms': 10000},
        }, nowMs: 9999),
        1234,
      );
    });

    test('sin datos devuelve null', () {
      expect(interpolatedPositionMs(null, nowMs: 0), isNull);
      expect(interpolatedPositionMs({}, nowMs: 0), isNull);
      expect(interpolatedPositionMs({'track': {}}, nowMs: 0), isNull);
    });
  });

  testWidgets('un error del stream refresca y reprograma la suscripción', (
    tester,
  ) async {
    final api = _FakeSpotifyApi();
    final controller = SpotifyPlayerController(api);
    await controller.refresh();
    final refreshesBefore = api.playerCalls;

    controller.startPolling(interval: const Duration(hours: 1));
    expect(api.eventsCalls, 1);

    api.eventsController.addError(StateError('stream caído'));
    await tester.pump();
    await tester.idle();

    // The drop triggers one immediate refresh without resubscribing yet.
    expect(api.playerCalls, greaterThan(refreshesBefore));
    expect(api.eventsCalls, 1);

    await tester.pump(const Duration(seconds: 5));
    expect(api.eventsCalls, 2);

    controller.dispose();
    await api.close();
  });

  testWidgets('el ticker notifica mientras suena y se detiene al pausar', (
    tester,
  ) async {
    final api = _FakeSpotifyApi();
    api.player = {
      ...api.player,
      'position': {'position_ms': 1000, 'timestamp_ms': 0, 'speed': 1.0},
    };
    final controller = SpotifyPlayerController(api);
    await controller.refresh();
    controller.startPolling(interval: const Duration(hours: 1));

    var notifications = 0;
    controller.addListener(() => notifications++);

    await tester.pump(const Duration(seconds: 1));
    expect(notifications, greaterThanOrEqualTo(1));

    // Paused via SSE: the ticker must stop advancing locally.
    api.emitEvent('spotify_state_changed', {'status': 'paused', 'item': null});
    await tester.pump();
    await tester.idle();
    final afterPause = notifications;
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, afterPause);

    controller.dispose();
    await api.close();
  });

  group('targetSupportsVolume', () {
    test('resolves by id and reflects listing updates after refresh', () async {
      final api = _FakeSpotifyApi();
      final controller = SpotifyPlayerController(api);
      await controller.refresh();

      // The listing carries no flag yet: unknown.
      expect(controller.activeDevice?['id'], 'dev_1');
      expect(controller.targetSupportsVolume, isNull);

      api.devices = {
        'devices': [
          {'id': 'dev_1', 'name': 'Parlante', 'supports_volume': false},
        ],
        'default_device_id': 'dev_1',
      };
      await controller.refresh();
      expect(controller.targetSupportsVolume, isFalse);

      api.devices = {
        'devices': [
          {'id': 'dev_1', 'name': 'Parlante', 'supports_volume': true},
        ],
        'default_device_id': 'dev_1',
      };
      await controller.refresh();
      expect(controller.targetSupportsVolume, isTrue);

      controller.dispose();
      await api.close();
    });

    test('falls back to matching by name for synthetic device ids', () async {
      final api = _FakeSpotifyApi();
      api.player = {
        ...api.player,
        'device': {'id': 'soloist', 'name': 'Soloist', 'volume_percent': 20},
      };
      api.devices = {
        'devices': [
          {'id': 'real-1', 'name': 'Soloist', 'supports_volume': false},
        ],
        'default_device_id': null,
      };
      final controller = SpotifyPlayerController(api);
      await controller.refresh();

      expect(controller.activeDevice?['id'], 'soloist');
      expect(controller.targetSupportsVolume, isFalse);

      controller.dispose();
      await api.close();
    });

    test('returns null when unresolvable or the flag is not a bool', () async {
      final api = _FakeSpotifyApi();
      api.player = {
        ...api.player,
        'device': {'id': 'ghost', 'name': 'Fantasma'},
      };
      api.devices = {'devices': [], 'default_device_id': null};
      final controller = SpotifyPlayerController(api);
      await controller.refresh();
      expect(controller.targetSupportsVolume, isNull);

      api.devices = {
        'devices': [
          {'id': 'ghost', 'name': 'Fantasma', 'supports_volume': 'yes'},
        ],
        'default_device_id': null,
      };
      await controller.refresh();
      expect(controller.targetSupportsVolume, isNull);

      controller.dispose();
      await api.close();
    });

    test('the explicit pick resolves its own capability', () async {
      final api = _FakeSpotifyApi();
      // No player-reported device: the explicit pick decides.
      api.player = {...api.player}..remove('device');
      api.devices = {
        'devices': [
          {'id': 'dev_1', 'name': 'Parlante', 'supports_volume': true},
          {'id': 'dev_2', 'name': 'Cocina', 'supports_volume': false},
        ],
        'default_device_id': 'dev_1',
      };
      final controller = SpotifyPlayerController(api);
      await controller.refresh();
      expect(controller.targetSupportsVolume, isTrue);

      controller.selectDevice('dev_2');
      expect(controller.activeDevice?['id'], 'dev_2');
      expect(controller.targetSupportsVolume, isFalse);

      controller.dispose();
      await api.close();
    });
  });
}
