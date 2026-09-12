import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';

void main() {
  test(
    'events() parsea SSE, reenvía Last-Event-ID y termina en system_closed',
    () async {
      var connections = 0;
      String? receivedLastEventId;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        connections++;
        expect(request.uri.path, '/api/v1/events');
        if (connections == 2) {
          receivedLastEventId = request.headers.value('Last-Event-ID');
        }
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(': keepalive\n');
        if (connections == 1) {
          request.response.write(
            'id: 7\nevent: status_updated\ndata: {"a":1}\n\n',
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await request.response.close();
        } else {
          request.response.write(
            'event: device_state_changed\ndata: {"b":2}\n\n',
          );
          request.response.write('event: system_closed\ndata: {}\n\n');
          await request.response.close();
        }
      });

      final events = <Map<String, dynamic>>[];
      await client.events().forEach(events.add);

      expect(connections, 2);
      expect(receivedLastEventId, '7');
      expect(events, hasLength(3));
      expect(events[0]['event'], 'status_updated');
      expect(events[1]['event'], 'device_state_changed');
      expect(events[2]['event'], 'system_closed');
      await server.close(force: true);
    },
  );

  test(
    'modules() parsea el listado y setModule() envía PUT con enabled',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? receivedBody;

      server.listen((request) async {
        if (request.uri.path == '/api/v1/modules') {
          request.response.write(
            '{"version":1,"modules":[{"name":"voice","display_name":"Voz",'
            '"description":"Asistente por voz","enabled":true,"required":true,'
            '"version":"2.1.0"},{"name":"spotify","display_name":"Spotify",'
            '"description":"Música","enabled":false,"required":false,'
            '"version":"1.0.0"}]}',
          );
        } else {
          expect(request.uri.path, '/api/v1/modules/spotify');
          expect(request.method, 'PUT');
          receivedBody = await utf8.decoder.bind(request).join();
          request.response.write(
            '{"name":"spotify","enabled":true,"version":1,"message":"ok"}',
          );
        }
        await request.response.close();
      });

      final modules = await client.modules();
      expect(modules, hasLength(2));
      expect(modules[0]['display_name'], 'Voz');
      expect(modules[0]['required'], true);

      final result = await client.setModule('spotify', true);
      expect(result['enabled'], true);
      expect(jsonDecode(receivedBody!), {'enabled': true});
      await server.close(force: true);
    },
  );

  test('cameras() parsea el listado y cameraStream() el descriptor', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

    server.listen((request) async {
      if (request.uri.path == '/api/v1/cameras') {
        request.response.write(
          '{"enabled":true,"cameras":[{"camera_id":"camara_1","name":"Salón",'
          '"location":"salon","channel":1,"stream_profile":"sub"}]}',
        );
      } else {
        expect(request.uri.path, '/api/v1/cameras/camara_1/stream');
        expect(request.uri.queryParameters['profile'], 'sub');
        request.response.write(
          '{"camera_id":"camara_1","channel":1,"profile":"sub",'
          '"protocol":"rtsp","url":"rtsp://x/1","gateway":"go2rtc",'
          '"gateway_available":true,"stream_id":"camara_1_sub",'
          '"webrtc_url":"/api/v1/cameras/camara_1/webrtc","hls_url":null}',
        );
      }
      await request.response.close();
    });

    final cameras = await client.cameras();
    expect(cameras, hasLength(1));
    expect(cameras[0]['camera_id'], 'camara_1');
    expect(cameras[0]['stream_profile'], 'sub');

    final descriptor = await client.cameraStream('camara_1');
    expect(descriptor['gateway_available'], true);
    expect(descriptor['stream_id'], 'camara_1_sub');
    await server.close(force: true);
  });

  test(
    'cameraStream(profile: main) pide el descriptor del stream main',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? requestedProfile;

      server.listen((request) async {
        requestedProfile = request.uri.queryParameters['profile'];
        request.response.write(
          '{"camera_id":"camara_1","channel":1,"profile":"main",'
          '"protocol":"rtsp","url":"rtsp://x/1","gateway":"go2rtc",'
          '"gateway_available":true,"stream_id":"camara_1_main",'
          '"webrtc_url":"/api/v1/cameras/camara_1/webrtc",'
          '"hls_url":"http://x:1984/api/stream.m3u8?src=camara_1_main&mp4="}',
        );
        await request.response.close();
      });

      final descriptor = await client.cameraStream('camara_1', profile: 'main');
      expect(requestedProfile, 'main');
      expect(descriptor['stream_id'], 'camara_1_main');
      expect(descriptor['hls_url'], contains('&mp4='));
      await server.close(force: true);
    },
  );

  test('webrtcAnswer() envía el SDP plano y devuelve el answer', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    String? receivedBody;
    String? contentType;

    server.listen((request) async {
      expect(request.uri.path, '/api/v1/cameras/camara_1/webrtc');
      expect(request.uri.queryParameters['profile'], 'sub');
      contentType = request.headers.contentType?.mimeType;
      receivedBody = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType('application', 'sdp');
      request.response.write('v=0\r\n');
      await request.response.close();
    });

    final answer = await client.webrtcAnswer('camara_1', 'v=0\r\no=x');
    expect(answer, 'v=0\r\n');
    expect(contentType, 'application/sdp');
    expect(receivedBody, 'v=0\r\no=x');
    await server.close(force: true);
  });

  test('voiceStatus/activate/stop usan los endpoints de voz', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    final methods = <String>[];
    String? stopSessionId;

    server.listen((request) async {
      methods.add('${request.method} ${request.uri.path}');
      stopSessionId = request.uri.queryParameters['session_id'];
      if (request.uri.path.endsWith('/status')) {
        request.response.write(
          '{"session_id":null,"state":"idle","wakeword_required":true}',
        );
      } else {
        request.response.write(
          '{"session_id":"abc","state":"listening","wakeword_required":false}',
        );
      }
      await request.response.close();
    });

    final status = await client.voiceStatus();
    expect(status['state'], 'idle');

    final activated = await client.activateVoice();
    expect(activated['session_id'], 'abc');
    expect(activated['wakeword_required'], false);

    await client.stopVoice(sessionId: 'abc');
    expect(stopSessionId, 'abc');
    expect(methods, [
      'GET /api/v1/voice/status',
      'POST /api/v1/voice/activate',
      'POST /api/v1/voice/stop',
    ]);
    await server.close(force: true);
  });

  test('voiceEvents() parsea SSE de voz y termina en voice_finished', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

    server.listen((request) async {
      expect(request.uri.path, '/api/v1/voice/events/abc');
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(': keepalive\n');
      request.response.write(
        'id: 1\nevent: voice_state\ndata: {"event":"voice_state","data":{"state":"listening","sequence":1}}\n\n',
      );
      request.response.write(
        'id: 2\nevent: voice_transcript\ndata: {"event":"voice_transcript","data":{"text":"apaga la luz","sequence":2}}\n\n',
      );
      request.response.write(
        'id: 3\nevent: voice_finished\ndata: {"event":"voice_finished","data":{"sequence":3}}\n\n',
      );
      await request.response.close();
    });

    final events = <Map<String, dynamic>>[];
    await client
        .voiceEvents('abc', isCancelled: () => false)
        .forEach(events.add);

    expect(events, hasLength(3));
    expect(events[0]['event'], 'voice_state');
    final inner = ((events[1]['data'] as Map)['data'] as Map);
    expect(inner['text'], 'apaga la luz');
    expect(events[2]['event'], 'voice_finished');
    await server.close(force: true);
  });

  test(
    'voiceEvents() corta sin reconectar si la sesión ya no existe',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      var connections = 0;

      server.listen((request) async {
        connections++;
        request.response.statusCode = 404;
        request.response.write('{"detail":"Sesión de voz no encontrada."}');
        await request.response.close();
      });

      final events = <Map<String, dynamic>>[];
      await client
          .voiceEvents('ghost', isCancelled: () => false)
          .forEach(events.add);

      expect(events, isEmpty);
      expect(connections, 1);
      await server.close(force: true);
    },
  );

  test('voiceEvents() reenvía Last-Event-ID al reconectar', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    var connections = 0;
    String? receivedLastEventId;

    server.listen((request) async {
      connections++;
      expect(request.uri.path, '/api/v1/voice/events/abc');
      if (connections == 2) {
        receivedLastEventId = request.headers.value('Last-Event-ID');
      }
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      if (connections == 1) {
        // First event carries an explicit `id:` line; the second only carries
        // the sequence inside the payload. The reconnect must use the newest
        // of the two.
        request.response.write(
          'id: 4\nevent: voice_state\ndata: {"event":"voice_state","data":{"state":"listening","sequence":4}}\n\n',
        );
        request.response.write(
          'event: voice_transcript\ndata: {"event":"voice_transcript","data":{"text":"hola","sequence":5}}\n\n',
        );
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await request.response.close();
      } else {
        request.response.write(
          'event: voice_finished\ndata: {"event":"voice_finished","data":{"sequence":6}}\n\n',
        );
        await request.response.close();
      }
    });

    final events = <Map<String, dynamic>>[];
    await client
        .voiceEvents('abc', isCancelled: () => false)
        .forEach(events.add);

    expect(connections, 2);
    expect(receivedLastEventId, '5');
    expect(events, hasLength(3));
    expect(events.last['event'], 'voice_finished');
    await server.close(force: true);
  });

  test('audioTurn() sube el WAV y devuelve transcript + respuesta', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    final wav = Uint8List.fromList([1, 2, 3, 4, 5]);
    String? contentType;
    Uint8List? received;

    server.listen((request) async {
      expect(request.uri.path, '/api/v1/voice/audio-turn');
      expect(request.method, 'POST');
      contentType = request.headers.contentType?.mimeType;
      received = Uint8List.fromList(
        await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        ),
      );
      request.response.write(
        '{"transcript":"apaga la luz","source":"LOCAL",'
        '"speech":"He apagado la luz de la sala.",'
        '"had_actions":true,"close_requested":false,"device_results":[]}',
      );
      await request.response.close();
    });

    final result = await client.audioTurn(wav);
    expect(contentType, 'audio/wav');
    expect(received, wav);
    expect(result['transcript'], 'apaga la luz');
    expect(result['speech'], contains('apagado'));
    await server.close(force: true);
  });

  test('audioTurn(sessionId:) agrega ?session_id= a la URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    String? receivedSessionId;
    Uint8List? received;

    server.listen((request) async {
      expect(request.uri.path, '/api/v1/voice/audio-turn');
      expect(request.method, 'POST');
      receivedSessionId = request.uri.queryParameters['session_id'];
      received = Uint8List.fromList(
        await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        ),
      );
      request.response.write(
        '{"transcript":"hola","source":"LOCAL","speech":null,'
        '"had_actions":false,"close_requested":false,"device_results":[]}',
      );
      await request.response.close();
    });

    final result = await client.audioTurn(
      Uint8List.fromList([1, 2]),
      sessionId: 'abc',
    );
    expect(receivedSessionId, 'abc');
    expect(received, Uint8List.fromList([1, 2]));
    expect(result['transcript'], 'hola');
    await server.close(force: true);
  });

  test(
    'rutinas CRUD y búsqueda de Spotify usan endpoints y verbos correctos',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final calls = <String>[];
      String? postedBody;
      String? queried;

      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        final path = request.uri.path;
        if (path == '/api/v1/routines') {
          if (request.method == 'GET') {
            request.response.write(
              '{"routines":[{"id":"buenos-dias","nombre":"Buenos días",'
              '"activadores":[],"acciones":[],"validation_errors":[]}]}',
            );
          } else {
            postedBody = await utf8.decoder.bind(request).join();
            request.response.write(
              '{"id":"buenos-dias","nombre":"Buenos días","activation":false}',
            );
          }
        } else if (path.startsWith('/api/v1/routines/')) {
          if (request.method == 'GET') {
            request.response.write(
              '{"id":"buenos-dias","nombre":"Buenos días","activadores":[],'
              '"acciones":[],"validation_errors":[]}',
            );
          } else if (request.method == 'PUT') {
            postedBody = await utf8.decoder.bind(request).join();
            request.response.write(
              '{"id":"buenos-dias","nombre":"Buenos días"}',
            );
          } else {
            request.response.statusCode = 204;
          }
        } else if (path == '/api/v1/spotify/search') {
          queried = request.uri.queryParameters['q'];
          expect(request.uri.queryParameters['types'], 'track,artist,playlist');
          request.response.write('{"tracks":[],"artists":[],"playlists":[]}');
        } else {
          request.response.write('{"playlists":[]}');
        }
        await request.response.close();
      });

      final routines = await client.routines();
      expect(routines, hasLength(1));
      expect(routines[0]['id'], 'buenos-dias');

      final one = await client.routine('buenos-dias');
      expect(one['nombre'], 'Buenos días');

      await client.createRoutine({'nombre': 'x'});
      expect(jsonDecode(postedBody!), {'nombre': 'x'});

      await client.updateRoutine('buenos-dias', {'nombre': 'y'});
      expect(jsonDecode(postedBody!), {'nombre': 'y'});

      expect(await client.deleteRoutine('buenos-dias'), isTrue);

      await client.spotifySearch('the wall');
      expect(queried, 'the wall');

      expect((await client.spotifyPlaylists())['playlists'], isEmpty);
      expect(calls, [
        'GET /api/v1/routines',
        'GET /api/v1/routines/buenos-dias',
        'POST /api/v1/routines',
        'PUT /api/v1/routines/buenos-dias',
        'DELETE /api/v1/routines/buenos-dias',
        'GET /api/v1/spotify/search',
        'GET /api/v1/spotify/playlists',
      ]);
      await server.close(force: true);
    },
  );

  group('deviceplatform endpoints', () {
    test('deviceInventory() lista y pending=true agrega el query', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final calls = <String>[];
      final pendings = <String?>[];

      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        pendings.add(request.uri.queryParameters['pending']);
        request.response.write(
          '{"devices":[{"device_id":"dev_1","name":"Relé 1",'
          '"provider_id":"mocked"}]}',
        );
        await request.response.close();
      });

      final inventory = await client.deviceInventory();
      expect(inventory['devices'], isA<List>());
      expect((inventory['devices'] as List).first['device_id'], 'dev_1');

      await client.deviceInventory(pending: true);
      expect(calls, ['GET /api/v1/devices', 'GET /api/v1/devices']);
      expect(pendings, [null, 'true']);
      await server.close(force: true);
    });

    test('deviceDetail() hace GET del dispositivo', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/v1/devices/dev_1');
        request.response.write(
          '{"device_id":"dev_1","provider_id":"mocked","name":"Relé 1"}',
        );
        await request.response.close();
      });

      final detail = await client.deviceDetail('dev_1');
      expect(detail['device_id'], 'dev_1');
      expect(detail['provider_id'], 'mocked');
      await server.close(force: true);
    });

    test(
      'deviceProviderHealth() consulta el health de los providers',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        server.listen((request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/v1/devices/health');
          request.response.write(
            '{"mocked":{"provider_id":"mocked","status":"ok"}}',
          );
          await request.response.close();
        });

        final health = await client.deviceProviderHealth();
        expect((health['mocked'] as Map)['status'], 'ok');
        await server.close(force: true);
      },
    );

    test('discoverDevices() hace POST sin body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? receivedBody;

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/devices/discovery');
        receivedBody = await utf8.decoder.bind(request).join();
        request.response.write(
          '{"mocked":{"provider_id":"mocked","new_devices":1}}',
        );
        await request.response.close();
      });

      final discovery = await client.discoverDevices();
      expect((discovery['mocked'] as Map)['new_devices'], 1);
      expect(receivedBody, isEmpty);
      await server.close(force: true);
    });

    test('updateDevicePhysicalArea() hace PUT con el area_id exacto', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? receivedBody;

      server.listen((request) async {
        expect(request.method, 'PUT');
        expect(request.uri.path, '/api/v1/devices/dev_1/physical-area');
        receivedBody = await utf8.decoder.bind(request).join();
        request.response.write(
          '{"device_id":"dev_1","area_id":"pasillo","updated":true}',
        );
        await request.response.close();
      });

      final result = await client.updateDevicePhysicalArea('dev_1', 'pasillo');
      expect(jsonDecode(receivedBody!), {'area_id': 'pasillo'});
      expect(result['updated'], true);
      await server.close(force: true);
    });

    test('updateEndpointControlledArea() hace PUT con y sin area', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final bodies = <String>[];

      server.listen((request) async {
        expect(request.method, 'PUT');
        expect(request.uri.path, '/api/v1/devices/dev_1/endpoints/relay_1');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write(
          '{"device_id":"dev_1","endpoint_id":"relay_1","updated":true}',
        );
        await request.response.close();
      });

      await client.updateEndpointControlledArea('dev_1', 'relay_1', 'cocina');
      await client.updateEndpointControlledArea('dev_1', 'relay_1', null);
      expect(jsonDecode(bodies[0]), {'controlled_area_id': 'cocina'});
      expect(jsonDecode(bodies[1]), {'controlled_area_id': null});
      await server.close(force: true);
    });

    test(
      'updateEndpointSemanticRole() PUT set y clear con body exacto',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        final bodies = <String>[];

        server.listen((request) async {
          expect(request.method, 'PUT');
          expect(
            request.uri.path,
            '/api/v1/devices/dev_1/endpoints/relay_1/semantic-role',
          );
          bodies.add(await utf8.decoder.bind(request).join());
          request.response.write('{"device_id":"dev_1","endpoints":[]}');
          await request.response.close();
        });

        await client.updateEndpointSemanticRole('dev_1', 'relay_1', 'light');
        await client.updateEndpointSemanticRole('dev_1', 'relay_1', null);
        expect(jsonDecode(bodies[0]), {'semantic_role': 'light'});
        expect(jsonDecode(bodies[1]), {'semantic_role': null});
        await server.close(force: true);
      },
    );

    test('renameDevice() PUT user_name set y clear', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final bodies = <String>[];

      server.listen((request) async {
        expect(request.method, 'PUT');
        expect(request.uri.path, '/api/v1/devices/dev_1/name');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write('{"device_id":"dev_1"}');
        await request.response.close();
      });

      await client.renameDevice('dev_1', 'Lámpara');
      await client.renameDevice('dev_1', null);
      expect(jsonDecode(bodies[0]), {'user_name': 'Lámpara'});
      expect(jsonDecode(bodies[1]), {'user_name': null});
      await server.close(force: true);
    });

    test('renameEndpoint() PUT user_name set y clear', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final bodies = <String>[];

      server.listen((request) async {
        expect(request.method, 'PUT');
        expect(
          request.uri.path,
          '/api/v1/devices/dev_1/endpoints/relay_1/name',
        );
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write('{"device_id":"dev_1","endpoints":[]}');
        await request.response.close();
      });

      await client.renameEndpoint('dev_1', 'relay_1', 'Espejo');
      await client.renameEndpoint('dev_1', 'relay_1', null);
      expect(jsonDecode(bodies[0]), {'user_name': 'Espejo'});
      expect(jsonDecode(bodies[1]), {'user_name': null});
      await server.close(force: true);
    });

    test('los ids se codifican en la URL', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? rawPath;

      server.listen((request) async {
        rawPath = request.uri.path;
        request.response.write('{"device_id":"dev 1/x"}');
        await request.response.close();
      });

      final detail = await client.deviceDetail('dev 1/x');
      expect(rawPath, contains('%20'));
      expect(rawPath, contains('%2F'));
      expect(detail['device_id'], 'dev 1/x');
      await server.close(force: true);
    });

    test('404 con detail se propaga como ApiException', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        request.response.statusCode = 404;
        request.response.write('{"detail":"Device not found"}');
        await request.response.close();
      });

      try {
        await client.deviceDetail('dev_1');
        fail('se esperaba ApiException 404');
      } on ApiException catch (e) {
        expect(e.statusCode, 404);
        expect((e.body as Map)['detail'], 'Device not found');
      }
      await server.close(force: true);
    });

    test('un 503 de persistencia se propaga como ApiException', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        request.response.statusCode = 503;
        request.response.write(
          '{"detail":"persistence unavailable","provider_id":"mocked"}',
        );
        await request.response.close();
      });

      try {
        await client.updateDevicePhysicalArea('dev_1', 'pasillo');
        fail('se esperaba ApiException 503');
      } on ApiException catch (e) {
        expect(e.statusCode, 503);
      }
      await server.close(force: true);
    });

    test(
      'un 422 de validación se propaga como ApiException por HttpServer',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        server.listen((request) async {
          expect(request.method, 'PUT');
          expect(request.uri.path, '/api/v1/devices/dev_1/physical-area');
          request.response.statusCode = 422;
          request.response.write(
            '{"detail":"area_id must be a non-empty string or null"}',
          );
          await request.response.close();
        });

        try {
          await client.updateDevicePhysicalArea('dev_1', '');
          fail('se esperaba ApiException 422');
        } on ApiException catch (e) {
          expect(e.statusCode, 422);
          expect(
            (e.body as Map)['detail'],
            'area_id must be a non-empty string or null',
          );
        }
        await server.close(force: true);
      },
    );
  });

  group('device commands', () {
    test(
      'endpointAction() devuelve el DTO tipado y envía action/value',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        String? receivedBody;

        server.listen((request) async {
          expect(request.method, 'POST');
          expect(
            request.uri.path,
            '/api/v1/devices/dev_1/endpoints/relay_1/actions',
          );
          receivedBody = await utf8.decoder.bind(request).join();
          request.response.write(
            jsonEncode({
              'request_id': 'req-1',
              'device_id': 'dev_1',
              'endpoint_id': 'relay_1',
              'action': 'set_power',
              'requested_value': true,
              'outcome': 'SUCCESS',
              'changed': true,
              'observed_state': {
                'power': true,
                'quality': 'confirmed',
                'observed_at': '2026-09-11T12:00:00Z',
              },
              'error_code': null,
              'error_detail': null,
              'latency_ms': 42,
            }),
          );
          await request.response.close();
        });

        final result = await client.endpointAction(
          'dev_1',
          'relay_1',
          action: 'set_power',
          value: true,
          requestId: 'req-1',
        );

        expect(jsonDecode(receivedBody!), {
          'action': 'set_power',
          'value': true,
          'request_id': 'req-1',
        });
        expect(result!['outcome'], 'SUCCESS');
        expect(result['changed'], true);
        expect((result['observed_state'] as Map)['quality'], 'confirmed');
        await server.close(force: true);
      },
    );

    test('endpointAction() tolera el body null actual (HTTP 200)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? receivedBody;

      server.listen((request) async {
        expect(request.method, 'POST');
        receivedBody = await utf8.decoder.bind(request).join();
        request.response.write('null');
        await request.response.close();
      });

      final result = await client.endpointAction(
        'dev_1',
        'relay_1',
        action: 'set_power',
        value: false,
      );

      expect(result, isNull);
      expect(jsonDecode(receivedBody!), {
        'action': 'set_power',
        'value': false,
      });
      await server.close(force: true);
    });

    test('endpointAction() mapea 422 al ApiException con detail', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        request.response.statusCode = 422;
        request.response.write('{"detail":"unknown_action"}');
        await request.response.close();
      });

      try {
        await client.endpointAction(
          'dev_1',
          'relay_1',
          action: 'bogus',
          value: true,
        );
        fail('se esperaba ApiException 422');
      } on ApiException catch (e) {
        expect(e.statusCode, 422);
        expect((e.body as Map)['detail'], 'unknown_action');
      }
      await server.close(force: true);
    });

    test(
      'endpointAction() mapea 404 unknown_endpoint con error_code',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        server.listen((request) async {
          request.response.statusCode = 404;
          request.response.write(
            '{"error_code":"unknown_endpoint","detail":"Endpoint not found",'
            '"request_id":"req-1"}',
          );
          await request.response.close();
        });

        try {
          await client.endpointAction(
            'dev_1',
            'ghost',
            action: 'set_power',
            value: true,
          );
          fail('se esperaba ApiException 404');
        } on ApiException catch (e) {
          expect(e.statusCode, 404);
          expect((e.body as Map)['error_code'], 'unknown_endpoint');
          expect((e.body as Map)['request_id'], 'req-1');
        }
        await server.close(force: true);
      },
    );

    test(
      'identifyDevice() hace POST sin body y devuelve supported/reason',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        String? receivedBody;

        server.listen((request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/api/v1/devices/dev_1/identify');
          receivedBody = await utf8.decoder.bind(request).join();
          request.response.write(
            '{"supported":false,"reason":"identify not supported"}',
          );
          await request.response.close();
        });

        final result = await client.identifyDevice('dev_1');

        expect(receivedBody, isEmpty);
        expect(result['supported'], false);
        expect(result['reason'], 'identify not supported');
        await server.close(force: true);
      },
    );

    test('refreshDevice() hace POST y devuelve el DeviceDTO', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/devices/dev_1/refresh');
        request.response.write(
          '{"device_id":"dev_1","display_name":"Refrescado","endpoints":[]}',
        );
        await request.response.close();
      });

      final dto = await client.refreshDevice('dev_1');

      expect(dto['device_id'], 'dev_1');
      expect(dto['display_name'], 'Refrescado');
      await server.close(force: true);
    });

    test('bindEntity()/unbindEntity() usan path y body canónicos', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final calls = <String>[];
      final bodies = <String>[];

      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        if (request.method == 'POST') {
          bodies.add(await utf8.decoder.bind(request).join());
        }
        request.response.write('{"device_id":"dev_1","endpoints":[]}');
        await request.response.close();
      });

      await client.bindEntity(
        'dev_1',
        endpointId: 'relay_1',
        entityId: 'luz_sala',
        capability: 'POWER',
        controlledAreaId: 'sala',
      );
      await client.bindEntity(
        'dev_1',
        endpointId: 'relay_1',
        entityId: 'luz_sala',
        capability: 'POWER',
      );
      await client.unbindEntity('dev_1', 'binding 1');

      expect(jsonDecode(bodies[0]), {
        'endpoint_id': 'relay_1',
        'entity_id': 'luz_sala',
        'capability': 'POWER',
        'controlled_area_id': 'sala',
      });
      expect(jsonDecode(bodies[1]), {
        'endpoint_id': 'relay_1',
        'entity_id': 'luz_sala',
        'capability': 'POWER',
      });
      expect(calls, [
        'POST /api/v1/devices/dev_1/bindings',
        'POST /api/v1/devices/dev_1/bindings',
        'DELETE /api/v1/devices/dev_1/bindings/binding%201',
      ]);
      await server.close(force: true);
    });

    test('ttsPreview() devuelve los bytes WAV y envía voice/text', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final wav = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3, 4]);
      String? receivedBody;

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/tts/preview');
        receivedBody = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.add(wav);
        await request.response.close();
      });

      final result = await client.ttsPreview('es-MX-JorgeNeural', 'Hola GAMMA');

      expect(result, wav);
      expect(jsonDecode(receivedBody!), {
        'voice': 'es-MX-JorgeNeural',
        'text': 'Hola GAMMA',
      });
      await server.close(force: true);
    });

    test('ttsPreview() mapea un 502 al ApiException con detail', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        request.response.statusCode = 502;
        request.response.write('{"detail":"Error al sintetizar la voz."}');
        await request.response.close();
      });

      try {
        await client.ttsPreview('voice', 'texto');
        fail('se esperaba ApiException 502');
      } on ApiException catch (e) {
        expect(e.statusCode, 502);
        expect((e.body as Map)['detail'], 'Error al sintetizar la voz.');
      }
      await server.close(force: true);
    });

    test('turn() envía session_id/client_id solo cuando no son null', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final bodies = <String>[];

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/turns');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write('{"speech":"ok"}');
        await request.response.close();
      });

      final plain = await client.turn('hola');
      await client.turn(
        'hola',
        sessionId: 'ses-1',
        clientId: 'cli-1',
        speakerName: 'Luis',
      );

      expect(plain['speech'], 'ok');
      expect(jsonDecode(bodies[0]), {'text': 'hola'});
      expect(jsonDecode(bodies[1]), {
        'text': 'hola',
        'session_id': 'ses-1',
        'client_id': 'cli-1',
        'speaker_name': 'Luis',
      });
      await server.close(force: true);
    });

    test('cameraStream()/webrtcAnswer() codifican el cameraId', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final paths = <String>[];

      server.listen((request) async {
        paths.add(request.uri.path);
        if (request.method == 'POST') {
          request.response.headers.contentType = ContentType(
            'application',
            'sdp',
          );
          request.response.write('v=0\r\n');
        } else {
          request.response.write(
            '{"camera_id":"cam 1/x","gateway_available":true}',
          );
        }
        await request.response.close();
      });

      await client.cameraStream('cam 1/x');
      await client.webrtcAnswer('cam 1/x', 'v=0\r\no=x');

      expect(paths, [
        '/api/v1/cameras/cam%201%2Fx/stream',
        '/api/v1/cameras/cam%201%2Fx/webrtc',
      ]);
      await server.close(force: true);
    });
  });

  group('spotify playback endpoints', () {
    test('spotifyPlayer()/spotifyDevices() leen el estado canónico', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final paths = <String>[];

      server.listen((request) async {
        paths.add('${request.method} ${request.uri.path}');
        if (request.uri.path.endsWith('/player')) {
          request.response.write(
            '{"has_playback":true,"is_playing":true,"track":{"name":"Tema",'
            '"artist":"Artista","album":null,"image_url":null,'
            '"progress_ms":1000,"duration_ms":3000},"device":{"id":"dev_1",'
            '"name":"Parlante","volume_percent":60},"shuffle":false,'
            '"repeat":"off","volume_percent":60}',
          );
        } else {
          request.response.write(
            '{"devices":[{"id":"dev_1","name":"Parlante","type":"speaker",'
            '"is_active":true,"is_private_session":false,'
            '"volume_percent":60,"is_default":true}],'
            '"default_device_name":"Parlante","default_device_id":"dev_1"}',
          );
        }
        await request.response.close();
      });

      final player = await client.spotifyPlayer();
      expect(player['is_playing'], true);
      expect((player['track'] as Map)['name'], 'Tema');

      final devices = await client.spotifyDevices();
      expect(devices['default_device_id'], 'dev_1');
      expect((devices['devices'] as List).first['is_active'], true);

      expect(paths, [
        'GET /api/v1/spotify/player',
        'GET /api/v1/spotify/devices',
      ]);
      await server.close(force: true);
    });

    test('spotifyPlaybackQueue() lee el listado con limit', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      String? method;
      String? limit;

      server.listen((request) async {
        method = request.method;
        limit = request.uri.queryParameters['limit'];
        request.response.write(
          '{"previous":[{"uri":"spotify:track:1","name":"A","artist":"X",'
          '"image_url":null,"source":"soloist"}],'
          '"upcoming":[{"uri":"spotify:track:2","name":"B","artist":"Y",'
          '"image_url":null,"source":"soloist"}],'
          '"source":"soloist","limited":false}',
        );
        await request.response.close();
      });

      final queue = await client.spotifyPlaybackQueue(limit: 5);

      expect(method, 'GET');
      expect(limit, '5');
      expect(queue['limited'], false);
      expect(queue['source'], 'soloist');
      expect((queue['previous'] as List), hasLength(1));
      expect((queue['upcoming'] as List), hasLength(1));
      await server.close(force: true);
    });

    test('spotifyPlay() envía exactamente un selector y omite nulos', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final bodies = <String>[];

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/spotify/play');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write('{"ok":true,"action":"play","device_id":null}');
        await request.response.close();
      });

      await client.spotifyPlay(uri: 'spotify:track:1');
      await client.spotifyPlay(
        contextUri: 'spotify:playlist:2',
        deviceId: 'dev 1',
        positionMs: 500,
      );
      await client.spotifyPlay(query: 'café');

      expect(jsonDecode(bodies[0]), {'uri': 'spotify:track:1'});
      expect(jsonDecode(bodies[1]), {
        'context_uri': 'spotify:playlist:2',
        'device_id': 'dev 1',
        'position_ms': 500,
      });
      expect(jsonDecode(bodies[2]), {'query': 'café'});

      // Exactly one selector is required by the backend contract.
      await expectLater(client.spotifyPlay(), throwsArgumentError);
      await expectLater(
        client.spotifyPlay(uri: 'spotify:track:1', query: 'x'),
        throwsArgumentError,
      );
      await server.close(force: true);
    });

    test('los comandos de transporte omiten el body sin device_id', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final calls = <String>[];
      final bodies = <String>[];

      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write('{"ok":true,"action":"x","device_id":null}');
        await request.response.close();
      });

      await client.spotifyPause();
      await client.spotifyResume();
      await client.spotifyNext();
      await client.spotifyPrevious();
      await client.spotifyPause(deviceId: 'dev 1');
      await client.spotifyResume(deviceId: 'dev 1');
      await client.spotifyNext(deviceId: 'dev 1');
      await client.spotifyPrevious(deviceId: 'dev 1');

      expect(calls, [
        'POST /api/v1/spotify/pause',
        'POST /api/v1/spotify/resume',
        'POST /api/v1/spotify/next',
        'POST /api/v1/spotify/previous',
        'POST /api/v1/spotify/pause',
        'POST /api/v1/spotify/resume',
        'POST /api/v1/spotify/next',
        'POST /api/v1/spotify/previous',
      ]);
      for (var i = 0; i < 4; i++) {
        expect(bodies[i], isEmpty);
      }
      for (var i = 4; i < 8; i++) {
        expect(jsonDecode(bodies[i]), {'device_id': 'dev 1'});
      }
      await server.close(force: true);
    });

    test(
      'volume/seek/transfer/shuffle/repeat/queue usan su verbo y body',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        final calls = <String>[];
        final bodies = <String>[];

        server.listen((request) async {
          calls.add('${request.method} ${request.uri.path}');
          bodies.add(await utf8.decoder.bind(request).join());
          request.response.write('{"ok":true,"action":"x","device_id":null}');
          await request.response.close();
        });

        await client.spotifySetVolume(42);
        await client.spotifySetVolume(42, deviceId: 'dev 1');
        await client.spotifySeek(1234, deviceId: 'dev 1');
        await client.spotifyTransfer('dev 2');
        await client.spotifyShuffle(true, deviceId: 'dev 1');
        await client.spotifyRepeat('context');
        await client.spotifyQueue('spotify:track:9', deviceId: 'dev 1');

        expect(calls, [
          'PUT /api/v1/spotify/volume',
          'PUT /api/v1/spotify/volume',
          'PUT /api/v1/spotify/seek',
          'PUT /api/v1/spotify/transfer',
          'PUT /api/v1/spotify/shuffle',
          'PUT /api/v1/spotify/repeat',
          'POST /api/v1/spotify/queue',
        ]);
        expect(jsonDecode(bodies[0]), {'volume_percent': 42});
        expect(jsonDecode(bodies[1]), {
          'volume_percent': 42,
          'device_id': 'dev 1',
        });
        expect(jsonDecode(bodies[2]), {
          'position_ms': 1234,
          'device_id': 'dev 1',
        });
        expect(jsonDecode(bodies[3]), {'device_id': 'dev 2'});
        expect(jsonDecode(bodies[4]), {'state': true, 'device_id': 'dev 1'});
        expect(jsonDecode(bodies[5]), {'state': 'context'});
        expect(jsonDecode(bodies[6]), {
          'uri': 'spotify:track:9',
          'device_id': 'dev 1',
        });
        await server.close(force: true);
      },
    );

    test(
      'los errores de reproducción mapean ApiException con detail',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        server.listen((request) async {
          if (request.uri.path.endsWith('/player')) {
            request.response.statusCode = 503;
            request.response.write(
              '{"detail":"Spotify no está autorizado. '
              'Conecta tu cuenta en Ajustes."}',
            );
          } else {
            request.response.statusCode = 409;
            request.response.write(
              '{"detail":"No hay dispositivo activo para reproducir."}',
            );
          }
          await request.response.close();
        });

        await expectLater(
          client.spotifyPlayer(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 503)
                .having(
                  (e) => (e.body as Map)['detail'],
                  'detail',
                  contains('no está autorizado'),
                ),
          ),
        );
        await expectLater(
          client.spotifyPause(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => (e.body as Map)['detail'],
                  'detail',
                  'No hay dispositivo activo para reproducir.',
                ),
          ),
        );
        await server.close(force: true);
      },
    );
  });

  group('core settings', () {
    test('configOverview() hace GET del agregado redactado', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/v1/settings');
        request.response.write(
          '{"spotify":{"client_id":{"value":"abc","source":"env"}},'
          '"news":{"api_key":{"configured":true,"source":"store",'
          '"last4":"0e2f"}}}',
        );
        await request.response.close();
      });

      final overview = await client.configOverview();

      expect((overview['spotify'] as Map)['client_id']['source'], 'env');
      expect((overview['news'] as Map)['api_key']['last4'], '0e2f');
      await server.close(force: true);
    });

    test('los GET por sección usan su path', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final paths = <String>[];

      server.listen((request) async {
        expect(request.method, 'GET');
        paths.add(request.uri.path);
        request.response.write('{"ok":true}');
        await request.response.close();
      });

      await client.spotifyConfig();
      await client.newsConfig();
      await client.llmConfig();
      await client.camerasConfig();

      expect(paths, [
        '/api/v1/settings/spotify',
        '/api/v1/settings/news',
        '/api/v1/settings/llm',
        '/api/v1/settings/cameras',
      ]);
      await server.close(force: true);
    });

    test('updateSpotifyConfig() envía solo los campos no nulos', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final bodies = <String>[];

      server.listen((request) async {
        expect(request.method, 'PUT');
        expect(request.uri.path, '/api/v1/settings/spotify');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write(
          '{"client_id":{"value":"nuevo","source":"store"},'
          '"applies":"hot","reconnect_required":true,"message":"ok"}',
        );
        await request.response.close();
      });

      final result = await client.updateSpotifyConfig(
        clientId: 'nuevo',
        clientSecret: 'secreto',
      );
      await client.updateSpotifyConfig(deviceName: 'GAMMA');

      expect(jsonDecode(bodies[0]), {
        'client_id': 'nuevo',
        'client_secret': 'secreto',
      });
      expect(jsonDecode(bodies[1]), {'device_name': 'GAMMA'});
      expect(result['reconnect_required'], true);
      expect(result['message'], 'ok');
      await server.close(force: true);
    });

    test('news y llm usan PUT con su body exacto', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final calls = <String>[];
      final bodies = <String>[];

      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.write('{"applies":"hot","message":"ok"}');
        await request.response.close();
      });

      await client.updateNewsConfig('news-key');
      await client.updateLlmConfig('gemini-key');

      expect(calls, ['PUT /api/v1/settings/news', 'PUT /api/v1/settings/llm']);
      expect(jsonDecode(bodies[0]), {'api_key': 'news-key'});
      expect(jsonDecode(bodies[1]), {'gemini_api_key': 'gemini-key'});
      await server.close(force: true);
    });

    test(
      'updateCamerasConfig() envía el puerto int y omite los nulos',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        final bodies = <String>[];

        server.listen((request) async {
          expect(request.method, 'PUT');
          expect(request.uri.path, '/api/v1/settings/cameras');
          bodies.add(await utf8.decoder.bind(request).join());
          request.response.write(
            '{"applies":"restart_required","message":"ok"}',
          );
          await request.response.close();
        });

        await client.updateCamerasConfig(nvrHost: '10.0.0.5', nvrPort: 8080);
        await client.updateCamerasConfig(nvrPass: 'secreto');

        expect(jsonDecode(bodies[0]), {
          'nvr_host': '10.0.0.5',
          'nvr_port': 8080,
        });
        expect(jsonDecode(bodies[1]), {'nvr_pass': 'secreto'});
        await server.close(force: true);
      },
    );

    test('tuyaConfig() hace GET de su sección redactada', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/v1/settings/tuya');
        request.response.write(
          '{"cloud_enabled":{"value":"true","source":"store"},'
          '"region":{"value":"us","source":"store"},'
          '"access_id":{"value":"aid","source":"store"},'
          '"api_secret":{"configured":true,"source":"store","last4":"9f2a"},'
          '"device_id":{"value":"dev","source":"store"}}',
        );
        await request.response.close();
      });

      final view = await client.tuyaConfig();

      expect((view['cloud_enabled'] as Map)['value'], 'true');
      expect((view['region'] as Map)['value'], 'us');
      expect((view['api_secret'] as Map)['last4'], '9f2a');
      await server.close(force: true);
    });

    test(
      'updateTuyaConfig() envía solo los campos no nulos, incluido false',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        final bodies = <String>[];

        server.listen((request) async {
          expect(request.method, 'PUT');
          expect(request.uri.path, '/api/v1/settings/tuya');
          bodies.add(await utf8.decoder.bind(request).join());
          request.response.write(
            '{"applies":"hot","message":"Credenciales guardadas"}',
          );
          await request.response.close();
        });

        final result = await client.updateTuyaConfig(
          cloudEnabled: false,
          region: '',
          accessId: 'aid',
          deviceId: 'dev',
        );
        await client.updateTuyaConfig(apiSecret: 'secreto');

        expect(jsonDecode(bodies[0]), {
          'cloud_enabled': false,
          'region': '',
          'access_id': 'aid',
          'device_id': 'dev',
        });
        expect(jsonDecode(bodies[1]), {'api_secret': 'secreto'});
        expect(result['applies'], 'hot');
        await server.close(force: true);
      },
    );

    test('un 422 de settings se propaga con el detail del backend', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        request.response.statusCode = 422;
        request.response.write('{"detail":"API key inválida."}');
        await request.response.close();
      });

      await expectLater(
        client.updateNewsConfig('mala'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => (e.body as Map)['detail'],
                'detail',
                'API key inválida.',
              ),
        ),
      );
      await server.close(force: true);
    });
  });
}
