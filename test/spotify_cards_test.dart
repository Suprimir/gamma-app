import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/dashboard/desktop_dashboard_page.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// Widget coverage for the progressively disclosed Spotify cards: the player
/// state shows hero + progress + one up-next line with the queue/volume/device
/// behind triggers, and the launcher state owns the playlists. Polling stays
/// off unless a test opts in, so no timer outlives the widget tree.
void main() {
  setUp(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  /// Fixed pumps instead of pumpAndSettle: the assistant orb animates forever
  /// on both home surfaces, so settle would never complete on the card itself.
  Future<void> settleSurface(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> pumpWall(
    WidgetTester tester,
    _SpotifyCardApi api, {
    Duration pollInterval = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WallPanelHomePage(
            api: api,
            idleTimeout: null,
            spotifyPollInterval: pollInterval,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> pumpDesktop(
    WidgetTester tester,
    _SpotifyCardApi api, {
    Duration pollInterval = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopDashboardPage(api: api, spotifyPollInterval: pollInterval),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));
  }

  testWidgets('wall player shows the hero and commands pause/resume', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpWall(tester, api);

    expect(find.text('Tema'), findsOneWidget);
    // Artist and device share one subtitle line.
    expect(find.text('Artista · Parlante'), findsOneWidget);

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

  testWidgets('wall player shows progress and opens the queue sheet', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..upcomingQueue = [
        {'uri': 'spotify:track:2', 'name': 'Tema 2', 'artist': 'Artista 2'},
        {'uri': 'spotify:track:3', 'name': 'Tema 3', 'artist': 'Artista 3'},
      ];
    await pumpWall(tester, api);

    // Track progress_ms 1000 / duration_ms 3000 from the fake player.
    expect(find.byKey(const ValueKey('wall-spotify-progress')), findsOneWidget);
    expect(find.text('00:01 / 00:03'), findsOneWidget);

    // One up-next line only; the rows live behind the sheet.
    expect(
      find.textContaining('A continuación · Tema 2 — Artista 2'),
      findsOneWidget,
    );
    expect(find.text('Tema 2 · Artista 2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('wall-spotify-up-next')));
    await settleSurface(tester);

    expect(find.text('A continuación'), findsOneWidget);
    expect(find.text('Tema 2 · Artista 2'), findsOneWidget);
    expect(find.text('Tema 3 · Artista 3'), findsOneWidget);
  });

  testWidgets('wall progress slider previews during drag and seeks on end', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpWall(tester, api);

    final slider = find.byKey(const ValueKey('wall-spotify-progress'));
    expect(slider, findsOneWidget);
    expect(find.text('00:01 / 00:03'), findsOneWidget);

    // Hold the drag: the label previews the finger position and nothing is
    // pushed to the backend yet.
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(api.seekPositions, isEmpty);
    expect(find.text('00:01 / 00:03'), findsNothing);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.seekPositions, hasLength(1));
    expect(api.seekPositions.single, greaterThan(1000));
    expect(api.seekPositions.single, lessThanOrEqualTo(3000));
  });

  testWidgets('wall seek is disabled when the backend does not advertise it', (
    tester,
  ) async {
    final api = _SpotifyCardApi()..actions = ['pause', 'skip_next'];
    await pumpWall(tester, api);

    expect(find.byKey(const ValueKey('wall-spotify-progress')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('wall progress disappears without a duration', (tester) async {
    final api = _SpotifyCardApi()..durationMs = null;
    await pumpWall(tester, api);

    expect(find.byKey(const ValueKey('wall-spotify-progress')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('wall transport follows the advertised actions list', (
    tester,
  ) async {
    // Playing with pause/next executable but skip_prev not advertised.
    final api = _SpotifyCardApi()..actions = ['pause', 'skip_next'];
    await pumpWall(tester, api);

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

  testWidgets('wall volume lives behind its trigger and commits on drag', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpWall(tester, api);

    // The progress scrubber is already a Slider; the volume one only exists
    // inside its sheet.
    expect(
      find.byKey(const ValueKey('wall-spotify-volume-slider')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Volumen'));
    await settleSurface(tester);

    expect(find.text('Volumen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wall-spotify-volume-slider')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('wall-spotify-volume-slider')),
      const Offset(-120, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      api.commands.any((command) => command.startsWith('volume:')),
      isTrue,
    );
  });

  testWidgets('wall queue sheet adds the previous section when available', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..upcomingQueue = [
        {'uri': 'spotify:track:9', 'name': 'Después', 'artist': 'B'},
      ]
      ..previousQueue = [
        {'uri': 'spotify:track:1', 'name': 'Antes', 'artist': 'A'},
      ];
    await pumpWall(tester, api);

    await tester.tap(find.byTooltip('Ver cola'));
    await settleSurface(tester);

    expect(find.text('Anteriores'), findsOneWidget);
    expect(find.text('Antes · A'), findsOneWidget);
    expect(find.text('Después · B'), findsOneWidget);
  });

  testWidgets('wall device picker opens from the icon with Automático', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpWall(tester, api);

    await tester.tap(find.byTooltip('Elegir dispositivo'));
    await settleSurface(tester);

    expect(find.text('Reproducir en'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('Parlante'), findsOneWidget);
  });

  testWidgets('wall player is honest with no device: transport disabled', (
    tester,
  ) async {
    final api = _SpotifyCardApi()..deviceAvailable = false;
    await pumpWall(tester, api);

    // The icon-only row keeps the honest state on the device trigger.
    expect(find.byTooltip('Sin dispositivo activo'), findsOneWidget);
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

  testWidgets('wall launcher shows header + hint only', (tester) async {
    final api = _SpotifyCardApi()..hasPlayback = false;
    await pumpWall(tester, api);

    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Sin reproducción'), findsOneWidget);
    // No account line, playlists or player stack in the wall launcher.
    expect(find.text('Luis'), findsNothing);
    expect(find.byTooltip('Volumen'), findsNothing);
    expect(find.byTooltip('Reproducir'), findsNothing);
  });

  testWidgets('wall music card converges when the player becomes available', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..authenticated = false
      ..spotifyReady = false;
    await pumpWall(tester, api, pollInterval: const Duration(seconds: 1));

    expect(find.text('Sin conectar'), findsOneWidget);
    expect(find.text('Conectar Spotify'), findsOneWidget);

    // Authorization completed from Settings/desktop while this card is open:
    // the next player poll must converge the card without a reload.
    api
      ..authenticated = true
      ..spotifyReady = true
      ..hasPlayback = false;

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Sin reproducción'), findsOneWidget);
    // Header + hint only: the settings read stays one-shot.
    expect(api.settingsCalls, 1);

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

  testWidgets('desktop player shows progress and opens the queue sheet', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..upcomingQueue = [
        {'uri': 'spotify:track:2', 'name': 'Tema 2', 'artist': 'Artista 2'},
        {'uri': 'spotify:track:3', 'name': 'Tema 3', 'artist': 'Artista 3'},
      ];
    await pumpDesktop(tester, api);

    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Artista · Parlante'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-spotify-progress')),
      findsOneWidget,
    );
    expect(find.text('00:01 / 00:03'), findsOneWidget);

    // One up-next line only; the rows live behind the sheet.
    expect(
      find.textContaining('A continuación · Tema 2 — Artista 2'),
      findsOneWidget,
    );
    expect(find.text('Tema 2 · Artista 2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop-spotify-up-next')));
    await settleSurface(tester);

    expect(find.text('A continuación'), findsOneWidget);
    expect(find.text('Tema 2 · Artista 2'), findsOneWidget);
    expect(find.text('Tema 3 · Artista 3'), findsOneWidget);
  });

  testWidgets('desktop scrubber previews, commits and seeks on tap', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpDesktop(tester, api);

    final slider = find.byKey(const ValueKey('desktop-spotify-progress'));
    expect(slider, findsOneWidget);
    expect(find.text('00:01 / 00:03'), findsOneWidget);

    // Hold the drag: the label previews the finger position and nothing is
    // pushed to the backend yet.
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(api.seekPositions, isEmpty);
    expect(find.text('00:01 / 00:03'), findsNothing);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.seekPositions, hasLength(1));
    expect(api.seekPositions.single, greaterThan(1000));
    expect(api.seekPositions.single, lessThanOrEqualTo(3000));

    // Tap-to-seek also commits a clamped position.
    await tester.tapAt(tester.getCenter(slider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.seekPositions, hasLength(2));
    expect(api.seekPositions.last, lessThanOrEqualTo(3000));
  });

  testWidgets('desktop progress falls back to the bar with no active device', (
    tester,
  ) async {
    final api = _SpotifyCardApi()..deviceAvailable = false;
    await pumpDesktop(tester, api);

    expect(
      find.byKey(const ValueKey('desktop-spotify-progress')),
      findsNothing,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('desktop volume lives behind its trigger', (tester) async {
    final api = _SpotifyCardApi();
    await pumpDesktop(tester, api);

    // The progress scrubber is already a Slider; the volume one only exists
    // inside its sheet.
    expect(
      find.byKey(const ValueKey('desktop-spotify-volume-slider')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Volumen'));
    await settleSurface(tester);

    expect(find.text('Volumen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-spotify-volume-slider')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('desktop-spotify-volume-slider')),
      const Offset(-40, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      api.commands.any((command) => command.startsWith('volume:')),
      isTrue,
    );
  });

  testWidgets('desktop transport follows the advertised actions list', (
    tester,
  ) async {
    final api = _SpotifyCardApi()..actions = ['pause', 'skip_next'];
    await pumpDesktop(tester, api);

    final previous = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_previous_rounded),
    );
    expect(previous.onPressed, isNull);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.skip_next_rounded),
    );
    expect(next.onPressed, isNotNull);
  });

  testWidgets('desktop playlists stay hidden until "Ver playlists" is tapped', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpDesktop(tester, api);

    // Player state: hero + progress, no library stack.
    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Mi Playlist'), findsNothing);
    expect(find.text('Abrir ajustes de Spotify'), findsNothing);

    await tester.tap(find.byTooltip('Más opciones'));
    await settleSurface(tester);
    expect(find.text('Abrir ajustes de Spotify'), findsOneWidget);

    await tester.tap(find.text('Ver playlists'));
    await settleSurface(tester);

    // Launcher pinned over active playback with a way back.
    expect(find.text('Mi Playlist'), findsOneWidget);
    expect(find.text('Volver al reproductor'), findsOneWidget);

    await tester.tap(find.text('Volver al reproductor'));
    await settleSurface(tester);
    expect(find.text('Mi Playlist'), findsNothing);
    expect(find.text('Tema'), findsOneWidget);
  });

  testWidgets('desktop new track returns from the pinned launcher to player', (
    tester,
  ) async {
    final api = _SpotifyCardApi();
    await pumpDesktop(tester, api, pollInterval: const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Más opciones'));
    await settleSurface(tester);
    await tester.tap(find.text('Ver playlists'));
    await settleSurface(tester);
    expect(find.text('Volver al reproductor'), findsOneWidget);

    // A new track starts: the pin resets without fighting the toggle.
    api.trackUri = 'spotify:track:99';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Volver al reproductor'), findsNothing);
    expect(find.text('Tema'), findsOneWidget);

    // Dispose the page so the periodic poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop player fits a narrow tile with a long title', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..trackName =
          'Un título extremadamente largo que no debe desbordar la tarjeta';
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DesktopDashboardPage(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));

    // The hero row ellipsizes instead of overflowing (a RenderFlex overflow
    // would surface as a test exception).
    expect(
      find.textContaining('Un título extremadamente largo'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-spotify-progress')),
      findsOneWidget,
    );
  });

  testWidgets('desktop launcher playlist tap issues playContext with the uri', (
    tester,
  ) async {
    final api = _SpotifyCardApi()..hasPlayback = false;
    await pumpDesktop(tester, api);

    expect(find.text('Mi Playlist'), findsOneWidget);
    await tester.tap(find.text('Mi Playlist'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.lastPlayUri, 'spotify:playlist:42');
  });

  testWidgets('desktop Spotify card converges when the player is available', (
    tester,
  ) async {
    final api = _SpotifyCardApi()
      ..authenticated = false
      ..spotifyReady = false
      ..accountName = ''
      ..playlists = [];
    await pumpDesktop(tester, api, pollInterval: const Duration(seconds: 1));

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
    expect(find.text('Conectado como Luis'), findsOneWidget);
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
  String trackUri = 'spotify:track:1';
  String trackName = 'Tema';

  /// Track duration reported by the fake player; null hides the progress row.
  int? durationMs = 3000;

  /// Seek positions received by [spotifySeek], in call order.
  final seekPositions = <int>[];
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
  List<Map<String, dynamic>> previousQueue = [];

  /// When non-null, the player advertises this executable actions list.
  List<String>? actions;

  /// SSE stand-in: never emits nor completes, so polling tests stay offline
  /// and no resubscribe timer fires.
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> events() => _events.stream;

  @override
  Future<Map<String, dynamic>> spotifyPlaybackQueue({int limit = 20}) async => {
    'previous': previousQueue,
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
              'uri': trackUri,
              'name': trackName,
              'artist': 'Artista',
              'album': null,
              'image_url': null,
              'progress_ms': 1000,
              'duration_ms': durationMs,
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
  Future<Map<String, dynamic>> spotifySetVolume(
    int volumePercent, {
    String? deviceId,
  }) async {
    commands.add('volume:$volumePercent');
    return {'ok': true, 'action': 'volume', 'device_id': deviceId};
  }

  @override
  Future<Map<String, dynamic>> spotifySeek(
    int positionMs, {
    String? deviceId,
  }) async {
    seekPositions.add(positionMs);
    commands.add('seek:$positionMs');
    return {'ok': true, 'action': 'seek', 'device_id': deviceId};
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
