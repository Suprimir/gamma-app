import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';

/// F2-D pause — Flutter connectivity regression.
///
/// Freezes the CURRENT canonical device/area routes so a stale
/// `/details`-style request (the original 404 report) can never return.
/// The ApiClient must speak the exact routes AssistantGamma's production
/// composition mounts; an obsolete secondary request is a regression.
void main() {
  group('Flutter Devices+Areas route contract', () {
    test(
      'device inventory uses the canonical list route, not /details',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
        final paths = <String>[];

        server.listen((request) async {
          paths.add('${request.method} ${request.uri.path}');
          request.response.write(
            '{"devices":[{"device_id":"dev_1","provider_id":"tuya",'
            '"display_name":"Relé 1","provisioning_state":"CONFIGURED",'
            '"enabled":true,"endpoints":[]}]}',
          );
          await request.response.close();
        });

        final data = await client.deviceInventory();
        expect(data['devices'], isA<List>());
        expect(paths, ['GET /api/v1/devices']);
        expect(paths.any((p) => p.contains('/details')), isFalse);
        await server.close(force: true);
      },
    );

    test('areas uses the canonical list route', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

      server.listen((request) async {
        expect(request.uri.path, '/api/v1/areas');
        request.response.write('{"areas":[]}');
        await request.response.close();
      });

      final areas = await client.areas();
      expect(areas, isEmpty);
      await server.close(force: true);
    });

    test(
      'device detail uses the canonical per-id route (no /details)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        server.listen((request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/v1/devices/dev_7');
          expect(request.uri.path.contains('/details'), isFalse);
          request.response.write(
            '{"device_id":"dev_7","provider_id":"tuya",'
            '"display_name":"Relé 7","provisioning_state":"CONFIGURED",'
            '"enabled":true,"endpoints":[]}',
          );
          await request.response.close();
        });

        final detail = await client.deviceDetail('dev_7');
        expect(detail['device_id'], 'dev_7');
        await server.close(force: true);
      },
    );

    test(
      'canonical endpoint F2-C fields parse from the real DTO shape',
      () async {
        // The AssistantGamma /api/v1/devices/{id} DTO carries endpoint
        // display_name_semantic / display_name_global / naming_source; the
        // client must not require a legacy secondary call for them.
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        server.listen((request) async {
          request.response.write(
            '{"device_id":"dev_9","provider_id":"tuya",'
            '"display_name":"Relé 9","provisioning_state":"CONFIGURED",'
            '"enabled":true,"endpoints":['
            '{"endpoint_id":"relay_1","display_name":null,'
            '"controlled_area_id":null,"enabled":true,'
            '"exposed_to_resolver":false,"binding_id":null,'
            '"semantic_role":"unknown","user_name":null,'
            '"stable_ordinal":1,"display_name_semantic":"Canal 1",'
            '"display_name_global":"Sin ubicación · Canal 1",'
            '"naming_source":"SEMANTIC_ROLE","capabilities":[]}]}',
          );
          await request.response.close();
        });

        final detail = await client.deviceDetail('dev_9');
        final endpoints = detail['endpoints'] as List;
        final ep = (endpoints.first as Map).cast<String, dynamic>();
        expect(ep['display_name_semantic'], 'Canal 1');
        expect(ep['display_name_global'], 'Sin ubicación · Canal 1');
        expect(ep['naming_source'], 'SEMANTIC_ROLE');
        await server.close(force: true);
      },
    );
  });
}
