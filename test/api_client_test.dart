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
}
