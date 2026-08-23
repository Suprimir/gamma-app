import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  // HttpClient con idleTimeout: Duration.zero: NO reutiliza conexiones
  // persistentes. El backend (uvicorn) cierra conexiones idle a los 5s y
  // un cliente que reutiliza el socket muerto falla con "connection closed
  // before full header was received". Cada request abre TCP fresco (red
  // local, costo despreciable) y el error desaparece.
  final http.Client _client = IOClient(
    HttpClient()..idleTimeout = const Duration(seconds: 0),
  );

  Future<Map<String, dynamic>> health() => _get('/api/v1/health');

  Future<List<Map<String, dynamic>>> modules() async {
    final data = await _get('/api/v1/modules');
    return (data['modules'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> setModule(String name, bool enabled) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/modules/${Uri.encodeComponent(name)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> turn(String text) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/turns'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> catalog() => _get('/api/v1/catalog');

  Future<Map<String, dynamic>> status({bool refresh = false}) =>
      _get(refresh ? '/api/v1/status?refresh=true' : '/api/v1/status');

  Future<Map<String, dynamic>> setPower(
    String location,
    String deviceId,
    bool enabled,
  ) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/devices/$location/$deviceId/power'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) =>
      _get(pending ? '/api/v1/devices?pending=true' : '/api/v1/devices');

  Future<Map<String, dynamic>> deviceDetail(String deviceId) =>
      _get('/api/v1/devices/${Uri.encodeComponent(deviceId)}');

  Future<Map<String, dynamic>> deviceProviderHealth() =>
      _get('/api/v1/devices/health');

  Future<Map<String, dynamic>> discoverDevices() async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/devices/discovery'),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> updateDevicePhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    final resp = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}'
        '/physical-area',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'area_id': areaId}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> updateEndpointControlledArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    final resp = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}'
        '/endpoints/${Uri.encodeComponent(endpointId)}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'controlled_area_id': areaId}),
    );
    return _decode(resp);
  }

  /// F2-C rename: set (string) or clear (null) the GAMMA-owned device name.
  Future<Map<String, dynamic>> renameDevice(
    String deviceId,
    String? userName,
  ) async {
    final resp = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}/name',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_name': userName}),
    );
    return _decode(resp);
  }

  /// F2-C rename: set (string) or clear (null) the GAMMA-owned endpoint name.
  Future<Map<String, dynamic>> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    final resp = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}'
        '/endpoints/${Uri.encodeComponent(endpointId)}/name',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_name': userName}),
    );
    return _decode(resp);
  }

  /// F2-D closure: set (role key) or clear (null) the endpoint semantic
  /// role (user override). Metadata only.
  Future<Map<String, dynamic>> updateEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    final resp = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}'
        '/endpoints/${Uri.encodeComponent(endpointId)}/semantic-role',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'semantic_role': role}),
    );
    return _decode(resp);
  }

  Future<List<Map<String, dynamic>>> areas() async {
    final data = await _get('/api/v1/areas');
    return (data['areas'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/areas'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'aliases': aliases}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (aliases != null) body['aliases'] = aliases;
    final resp = await _client.patch(
      Uri.parse('$baseUrl/api/v1/areas/${Uri.encodeComponent(areaId)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(resp);
  }

  /// F2-C: conflict-safe Area deletion. 204 on success; 404 unknown; 409 when
  /// devices/endpoints still reference the Area; 503 on persistence failure.
  Future<void> deleteArea(String areaId) async {
    final resp = await _client.delete(
      Uri.parse('$baseUrl/api/v1/areas/${Uri.encodeComponent(areaId)}'),
    );
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _decodeBody(resp));
    }
  }

  Object _decodeBody(http.Response resp) {
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      return resp.body;
    }
  }

  Future<List<Map<String, dynamic>>> cameras() async {
    final data = await _get('/api/v1/cameras');
    return (data['cameras'] as List).cast<Map<String, dynamic>>();
  }

  Future<({List<Map<String, dynamic>> cameras, bool enabled})>
  cameraModule() async {
    final data = await _get('/api/v1/cameras');
    return (
      cameras: (data['cameras'] as List).cast<Map<String, dynamic>>(),
      enabled: data['enabled'] == true,
    );
  }

  Future<Map<String, dynamic>> cameraStatus() => _get('/api/v1/cameras/status');

  Future<List<Map<String, dynamic>>> cameraEvents({int limit = 20}) async {
    final data = await _get('/api/v1/cameras/events?limit=$limit');
    return (data['events'] as List).cast<Map<String, dynamic>>();
  }

  String cameraSnapshotUrl(String cameraId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$baseUrl/api/v1/cameras/${Uri.encodeComponent(cameraId)}/snapshot?ts=$ts';
  }

  Future<Map<String, dynamic>> cameraStream(
    String cameraId, {
    String profile = 'sub',
  }) => _get('/api/v1/cameras/$cameraId/stream?profile=$profile');

  Future<String> webrtcAnswer(String cameraId, String offerSdp) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/cameras/$cameraId/webrtc?profile=sub'),
      headers: {'Content-Type': 'application/sdp'},
      body: offerSdp,
    );
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, utf8.decode(resp.bodyBytes));
    }
    return resp.body;
  }

  Future<List<Map<String, dynamic>>> routines() async {
    final data = await _get('/api/v1/routines');
    return (data['routines'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> routine(String id) =>
      _get('/api/v1/routines/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> createRoutine(
    Map<String, dynamic> payload,
  ) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/routines'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> updateRoutine(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/routines/${Uri.encodeComponent(id)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decode(resp);
  }

  Future<bool> deleteRoutine(String id) async {
    final resp = await _client.delete(
      Uri.parse('$baseUrl/api/v1/routines/${Uri.encodeComponent(id)}'),
    );
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  Future<Map<String, dynamic>> spotifySearch(String query, {int limit = 8}) =>
      _get(
        '/api/v1/spotify/search?q=${Uri.encodeQueryComponent(query)}'
        '&types=track,artist,playlist&limit=$limit',
      );

  Future<Map<String, dynamic>> spotifyPlaylists({int limit = 50}) =>
      _get('/api/v1/spotify/playlists?limit=$limit');

  Future<Map<String, dynamic>> voiceStatus() => _get('/api/v1/voice/status');

  Future<Map<String, dynamic>> ttsSettings() => _get('/api/v1/tts/settings');

  Future<Map<String, dynamic>> ttsVoices() => _get('/api/v1/tts/voices');

  Future<Map<String, dynamic>> updateTtsSettings(
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/tts/settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> spotifySettings() =>
      _get('/api/v1/spotify/settings');

  Future<Map<String, dynamic>> spotifyAuthStart() async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/spotify/auth/start'),
      headers: {'Content-Type': 'application/json'},
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> spotifyAuthReset() async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/spotify/auth/reset'),
      headers: {'Content-Type': 'application/json'},
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> activateVoice() async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/activate'),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> stopVoice({String? sessionId}) async {
    final query = sessionId == null
        ? ''
        : '?session_id=${Uri.encodeQueryComponent(sessionId)}';
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/stop$query'),
    );
    return _decode(resp);
  }

  /// Sube un WAV (PCM16 mono 16 kHz) para transcribirlo y ejecutar el turno.
  /// `sessionId` aísla el turno de voz por sesión en el backend.
  Future<Map<String, dynamic>> audioTurn(
    Uint8List wavBytes, {
    String? sessionId,
  }) async {
    final query = sessionId == null || sessionId.isEmpty
        ? ''
        : '?session_id=${Uri.encodeQueryComponent(sessionId)}';
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/audio-turn$query'),
      headers: {'Content-Type': 'audio/wav'},
      body: wavBytes,
    );
    return _decode(resp);
  }

  /// Flujo SSE de voz de una sesión: reenvía Last-Event-ID y termina con
  /// `voice_finished` o si la sesión ya no existe (HTTP != 200).
  /// `isCancelled()` evita reconexiones tras un stop o dispose.
  Stream<Map<String, dynamic>> voiceEvents(
    String sessionId, {
    required bool Function() isCancelled,
  }) async* {
    while (!isCancelled()) {
      final req = http.Request(
        'GET',
        Uri.parse(
          '$baseUrl/api/v1/voice/events/${Uri.encodeComponent(sessionId)}',
        ),
      );
      final resp = await _client.send(req);
      if (resp.statusCode != 200) return;

      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      String? eventName;
      final data = StringBuffer();
      await for (final line in lines) {
        if (line.isEmpty) {
          if (eventName != null) {
            final payload = jsonDecode(data.toString());
            yield {'event': eventName, 'data': payload};
            if (eventName == 'voice_finished') return;
          }
          eventName = null;
          data.clear();
          continue;
        }
        if (line.startsWith(':')) continue;
        if (line.startsWith('event:')) {
          eventName = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:')) {
          data.writeln(line.substring('data:'.length).trim());
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// Flujo SSE de GET /api/v1/events, con reconexión y Last-Event-ID.
  /// Termina con SystemClosedEvent.
  Stream<Map<String, dynamic>> events() async* {
    String? lastEventId;
    while (true) {
      final req = http.Request('GET', Uri.parse('$baseUrl/api/v1/events'));
      if (lastEventId != null) req.headers['Last-Event-ID'] = lastEventId;
      final resp = await _client.send(req);

      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      String? eventName;
      final data = StringBuffer();
      await for (final line in lines) {
        if (line.isEmpty) {
          if (eventName != null) {
            final payload = jsonDecode(data.toString());
            if (payload is Map && payload['id'] is String) {
              lastEventId = payload['id'] as String;
            }
            yield {'event': eventName, 'data': payload};
            if (eventName == 'system_closed') return;
          }
          eventName = null;
          data.clear();
          continue;
        }
        if (line.startsWith(':')) continue;
        if (line.startsWith('event:')) {
          eventName = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:')) {
          data.writeln(line.substring('data:'.length).trim());
        } else if (line.startsWith('id:')) {
          lastEventId = line.substring('id:'.length).trim();
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await _client.get(Uri.parse('$baseUrl$path'));
    return _decode(resp);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, body);
    }
    return body as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final Object body;

  @override
  String toString() => 'API $statusCode: $body';
}
