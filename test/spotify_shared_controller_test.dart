import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/spotify/spotify_controller_owner.dart';
import 'package:gamma_app/features/spotify/spotify_player_controller.dart';
import 'package:gamma_app/features/spotify/spotify_scope.dart';

/// Minimal stand-in: the owner only needs the player/device/queue reads to
/// resolve without hitting the network.
class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://fake.test');

  int playerCalls = 0;
  int eventsCalls = 0;

  @override
  Future<Map<String, dynamic>> spotifyPlayer() async {
    playerCalls++;
    return {
      'has_playback': true,
      'is_playing': true,
      'track': {'name': 'Tema', 'artist': 'Artista'},
      'device': {'id': 'dev_1', 'name': 'Parlante'},
    };
  }

  @override
  Future<Map<String, dynamic>> spotifyDevices() async => {
        'devices': [
          {'id': 'dev_1', 'name': 'Parlante'},
        ],
        'default_device_id': 'dev_1',
      };

  @override
  Future<Map<String, dynamic>> spotifyPlaybackQueue({int limit = 20}) async =>
      {'previous': [], 'upcoming': [], 'limited': false};

  @override
  Stream<Map<String, dynamic>> events() {
    eventsCalls++;
    return const Stream<Map<String, dynamic>>.empty();
  }
}

void main() {
  testWidgets('con SpotifyScope el owner reutiliza el controlador compartido',
      (tester) async {
    final api = _FakeApi();
    final shared = SpotifyPlayerController(api);
    late SpotifyControllerOwner owner;

    await tester.pumpWidget(
      SpotifyScope(
        controller: shared,
        child: Builder(
          builder: (context) {
            owner = SpotifyControllerOwner(api: api, interval: Duration.zero);
            owner.attach(context);
            owner.start();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(owner.controller, same(shared));
    expect(owner.ownsController, isFalse);
    // No abrió un segundo stream: solo el compartido existe.
    expect(api.eventsCalls, 0);
    // La lectura inicial arranca aunque el controlador sea compartido.
    await tester.pump();
    expect(api.playerCalls, 1);

    // Soltar la superficie no debe matar el controlador de la app.
    owner.dispose();
    expect(shared.player, isNotNull);

    shared.dispose();
  });

  testWidgets('sin scope el owner crea un controlador local y lo posee',
      (tester) async {
    final api = _FakeApi();
    late SpotifyControllerOwner owner;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          owner = SpotifyControllerOwner(api: api, interval: Duration.zero);
          owner.attach(context);
          owner.start();
          return const SizedBox.shrink();
        },
      ),
    );

    expect(owner.ownsController, isTrue);
    await tester.pump();
    expect(api.playerCalls, 1);

    final controller = owner.controller;
    owner.dispose();
    owner.dispose(); // idempotente

    // Una superficie nueva crea su propia instancia en vez de reutilizar la
    // desechada.
    late SpotifyControllerOwner second;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          second = SpotifyControllerOwner(api: api, interval: Duration.zero);
          second.attach(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(second.controller, isNot(same(controller)));
    second.dispose();
  });
}
