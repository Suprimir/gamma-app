import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/dashboard/desktop_dashboard_page.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// Widget coverage for the Spotify playback wiring: the wall music card
/// issues real transport commands and the desktop playlist tap starts
/// playback instead of showing a hint. Polling stays off in every test
/// (both pages default to `Duration.zero`).
void main() {
  setUp(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('wall music card shows now-playing and commands pause/resume', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallPanelHomePage(api: api, idleTimeout: null)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Artista'), findsOneWidget);

    await tester.tap(find.byTooltip('Pausar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.commands, contains('pause'));

    // The fake flips is_playing on pause, so the card now offers resume.
    await tester.tap(find.byTooltip('Reproducir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.commands, contains('resume'));
  });

  testWidgets('wall music card renders progress and queue when available', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..upcomingQueue = [
        {'uri': 'spotify:track:2', 'name': 'Tema 2', 'artist': 'Artista 2'},
        {'uri': 'spotify:track:3', 'name': 'Tema 3', 'artist': 'Artista 3'},
      ];
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallPanelHomePage(api: api, idleTimeout: null)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Track progress_ms 1000 / duration_ms 3000 from the fake player.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('A continuación'), findsOneWidget);
    expect(find.text('Tema 2 · Artista 2'), findsOneWidget);
    expect(find.text('Tema 3 · Artista 3'), findsOneWidget);
  });

  testWidgets('wall transport follows the advertised actions list', (
    tester,
  ) async {
    // Playing with pause/next executable but skip_prev not advertised.
    final api = _SpotifyCardApi()..actions = ['pause', 'skip_next'];
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallPanelHomePage(api: api, idleTimeout: null)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final previous = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_previous_rounded),
    );
    expect(previous.onPressed, isNull);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_next_rounded),
    );
    expect(next.onPressed, isNotNull);
    final pause = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.pause_rounded),
    );
    expect(pause.onPressed, isNotNull);
  });

  testWidgets('desktop playlist tap issues playContext with the real uri', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DesktopDashboardPage(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));

    expect(find.text('Mi Playlist'), findsOneWidget);
    await tester.tap(find.text('Mi Playlist'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.lastPlayUri, 'spotify:playlist:42');
  });

  testWidgets(
    'desktop Spotify card renders progress and queue when available',
    (tester) async {
      final api = _SpotifyCardApi()
        ..upcomingQueue = [
          {'uri': 'spotify:track:2', 'name': 'Tema 2', 'artist': 'Artista 2'},
          {'uri': 'spotify:track:3', 'name': 'Tema 3', 'artist': 'Artista 3'},
        ];
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: DesktopDashboardPage(api: api)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));

      // Track progress_ms 1000 / duration_ms 3000 from the fake player.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('00:01'), findsOneWidget);
      expect(find.text('00:03'), findsOneWidget);
      expect(find.text('A continuación'), findsOneWidget);
      expect(find.text('Tema 2 · Artista 2'), findsOneWidget);
      expect(find.text('Tema 3 · Artista 3'), findsOneWidget);
    },
  );

  testWidgets('wall music card is honest with no device: transport disabled', (
    tester,
  ) async {
    final api = _SpotifyCardApi()..deviceAvailable = false;
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallPanelHomePage(api: api, idleTimeout: null)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sin dispositivo activo'), findsOneWidget);
    // is_playing is still true in the player, but with no device every
    // transport target must be disabled instead of failing with a 409.
    final playPause = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.pause_rounded),
    );
    expect(playPause.onPressed, isNull);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_next_rounded),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('wall music card converges when the player becomes available', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..authenticated = false
      ..spotifyReady = false
      ..accountName = '';
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WallPanelHomePage(
            api: api,
            idleTimeout: null,
            spotifyPollInterval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sin conectar'), findsOneWidget);
    expect(find.text('Conectar Spotify'), findsOneWidget);

    // Authorization completed from Settings/desktop while this card is open:
    // the next player poll must converge the card without a reload.
    api
      ..authenticated = true
      ..spotifyReady = true
      ..hasPlayback = false
      ..accountName = 'Luis';

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Sin reproducción'), findsOneWidget);
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    // Initial status read plus the one-shot refetch triggered by the player.
    expect(api.settingsCalls, 2);

    // Disconnect direction: a 401/503 player response restores the connect
    // affordance even though the settings flag stays true.
    api.spotifyReady = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Sin conectar'), findsOneWidget);
    expect(find.text('Conectar Spotify'), findsOneWidget);

    // Dispose the card so the periodic poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop Spotify card converges when the player is available', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..authenticated = false
      ..spotifyReady = false
      ..accountName = ''
      ..playlists = [];
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopDashboardPage(
          api: api,
          spotifyPollInterval: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));

    expect(find.text('Sin conectar'), findsOneWidget);
    expect(find.text('Conectar Spotify'), findsOneWidget);

    // Authorization completed from Settings while the dashboard is open: the
    // player poll converges the card and the one-shot refetch fills the
    // account name and playlists.
    api
      ..authenticated = true
      ..spotifyReady = true
      ..hasPlayback = false
      ..accountName = 'Luis'
      ..playlists = [
        {
          'type': 'playlist',
          'uri': 'spotify:playlist:42',
          'name': 'Mi Playlist',
          'subtitle': '30 canciones',
          'image_url': null,
        },
      ];

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Sin reproducción'), findsOneWidget);
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Mi Playlist'), findsOneWidget);
    // Initial home load plus the one-shot refetch triggered by the player.
    expect(api.settingsCalls, 2);
    expect(api.playlistsCalls, 2);

    // Disconnect direction: a 401/503 player response restores the connect
    // affordance even though the settings flag stays true.
    api.spotifyReady = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Sin conectar'), findsOneWidget);
    expect(find.text('Conectar Spotify'), findsOneWidget);

    // Dispose the page so the periodic poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}

class _SpotifyCardApi extends ApiClient {
  _SpotifyCardApi() : super(baseUrl: 'http://fake.test');

  bool _playing = true;
  bool deviceAvailable = true;
  final commands = <String>[];
  String? lastPlayUri;

  /// Settings/player switches: flip both together to simulate the account
  /// becoming authorized while a card is already mounted.
  bool authenticated = true;
  bool spotifyReady = true;
  bool hasPlayback = true;
  String accountName = 'Luis';
  List<Map<String, dynamic>> playlists = [
    {
      'type': 'playlist',
      'uri': 'spotify:playlist:42',
      'name': 'Mi Playlist',
      'subtitle': '30 canciones',
      'image_url': null,
    },
  ];
  int settingsCalls = 0;
  int playlistsCalls = 0;

  /// Queue listing returned by [spotifyPlaybackQueue].
  List<Map<String, dynamic>> upcomingQueue = [];

  /// When non-null, the player advertises this executable actions list.
  List<String>? actions;

  /// SSE stand-in: never emits nor completes, so polling tests stay offline
  /// and no resubscribe timer fires.
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> events() => _events.stream;

  @override
  Future<Map<String, dynamic>> spotifyPlaybackQueue({int limit = 20}) async => {
    'previous': [],
    'upcoming': upcomingQueue,
    'limited': false,
  };

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async =>
      {'devices': []};

  @override
  Future<Map<String, dynamic>> catalog() async => {
    'locations': [],
    'routines': [],
    'device_count': 0,
    'version': 1,
  };

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async => {
    'providers': [],
  };

  @override
  Future<List<Map<String, dynamic>>> areas() async => [];

  @override
  Future<({List<Map<String, dynamic>> cameras, bool enabled})>
  cameraModule() async =>
      (cameras: const <Map<String, dynamic>>[], enabled: false);

  @override
  Future<Map<String, dynamic>> cameraStatus() async => {'statuses': const []};

  @override
  Future<List<Map<String, dynamic>>> routines() async => const [];

  @override
  Future<Map<String, dynamic>> spotifySettings() async {
    settingsCalls++;
    return {
      'authenticated': authenticated,
      'client_id_configured': true,
      'account_name': accountName,
    };
  }

  @override
  Future<Map<String, dynamic>> spotifyPlaylists({int limit = 50}) async {
    playlistsCalls++;
    return {'playlists': playlists};
  }

  @override
  Future<Map<String, dynamic>> spotifyPlayer() async {
    if (!spotifyReady) {
      throw ApiException(503, 'Spotify no está autorizado.');
    }
    return {
      'has_playback': hasPlayback,
      'is_playing': hasPlayback && _playing,
      'track': hasPlayback
          ? {
              'name': 'Tema',
              'artist': 'Artista',
              'album': null,
              'image_url': null,
              'progress_ms': 1000,
              'duration_ms': 3000,
            }
          : null,
      'device': deviceAvailable
          ? {'id': 'dev_1', 'name': 'Parlante', 'volume_percent': 70}
          : null,
      'shuffle': false,
      'repeat': 'off',
      'volume_percent': 70,
      if (actions != null) 'actions': actions,
    };
  }

  @override
  Future<Map<String, dynamic>> spotifyDevices() async => {
    'devices': deviceAvailable
        ? [
            {
              'id': 'dev_1',
              'name': 'Parlante',
              'is_active': true,
              'is_default': true,
              'volume_percent': 70,
            },
          ]
        : [],
    'default_device_id': null,
  };

  @override
  Future<Map<String, dynamic>> spotifyPause({String? deviceId}) async {
    commands.add('pause');
    _playing = false;
    return {'ok': true, 'action': 'pause', 'device_id': deviceId};
  }

  @override
  Future<Map<String, dynamic>> spotifyResume({String? deviceId}) async {
    commands.add('resume');
    _playing = true;
    return {'ok': true, 'action': 'resume', 'device_id': deviceId};
  }

  @override
  Future<Map<String, dynamic>> spotifyNext({String? deviceId}) async {
    commands.add('next');
    return {'ok': true, 'action': 'next', 'device_id': deviceId};
  }

  @override
  Future<Map<String, dynamic>> spotifyPrevious({String? deviceId}) async {
    commands.add('previous');
    return {'ok': true, 'action': 'previous', 'device_id': deviceId};
  }

  @override
  Future<Map<String, dynamic>> spotifyPlay({
    String? uri,
    String? contextUri,
    String? query,
    String? deviceId,
    int? positionMs,
  }) async {
    commands.add('play');
    lastPlayUri = contextUri ?? uri ?? query;
    return {'ok': true, 'action': 'play', 'device_id': deviceId};
  }
}
