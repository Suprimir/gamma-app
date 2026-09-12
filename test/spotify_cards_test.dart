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
}

class _SpotifyCardApi extends ApiClient {
  _SpotifyCardApi() : super(baseUrl: 'http://fake.test');

  bool _playing = true;
  bool deviceAvailable = true;
  final commands = <String>[];
  String? lastPlayUri;

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
  Future<Map<String, dynamic>> spotifySettings() async => {
    'authenticated': true,
    'client_id_configured': true,
    'account_name': 'Luis',
  };

  @override
  Future<Map<String, dynamic>> spotifyPlaylists({int limit = 50}) async => {
    'playlists': [
      {
        'type': 'playlist',
        'uri': 'spotify:playlist:42',
        'name': 'Mi Playlist',
        'subtitle': '30 canciones',
        'image_url': null,
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> spotifyPlayer() async => {
    'has_playback': true,
    'is_playing': _playing,
    'track': {
      'name': 'Tema',
      'artist': 'Artista',
      'album': null,
      'image_url': null,
      'progress_ms': 1000,
      'duration_ms': 3000,
    },
    'device': deviceAvailable
        ? {'id': 'dev_1', 'name': 'Parlante', 'volume_percent': 70}
        : null,
    'shuffle': false,
    'repeat': 'off',
    'volume_percent': 70,
  };

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
