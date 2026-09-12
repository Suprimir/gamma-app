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

  /// POSTs a chat turn. Optional `session_id`/`client_id` isolate voice and
  /// surface clients; null fields are omitted from the JSON body.
  Future<Map<String, dynamic>> turn(
    String text, {
    String? sessionId,
    String? clientId,
    String? speakerName,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/turns'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        'session_id': ?sessionId,
        'client_id': ?clientId,
        'speaker_name': ?speakerName,
      }),
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

  /// POSTs one canonical endpoint action (e.g. `set_power`).
  ///
  /// The live backend currently answers HTTP 200 with a literal `null` body
  /// (known gap); a typed result DTO is returned once the backend fix lands.
  /// Both shapes are tolerated. Errors surface as [ApiException] with the
  /// decoded JSON body (422 `detail`; 404 `error_code`/`detail`).
  Future<Map<String, dynamic>?> endpointAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object? value,
    String? requestId,
  }) async {
    final resp = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}'
        '/endpoints/${Uri.encodeComponent(endpointId)}/actions',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'value': value,
        'request_id': ?requestId,
      }),
    );
    final decoded = _decodeBodyOrNull(resp);
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, decoded ?? resp.body);
    }
    if (decoded == null) return null;
    return (decoded as Map).cast<String, dynamic>();
  }

  /// Asks the provider to flash/beep a device for physical identification.
  Future<Map<String, dynamic>> identifyDevice(String deviceId) async {
    final resp = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}/identify',
      ),
    );
    return _decode(resp);
  }

  /// Provider-neutral refresh/enrich; returns the normalized DeviceDTO.
  Future<Map<String, dynamic>> refreshDevice(String deviceId) async {
    final resp = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}/refresh',
      ),
    );
    return _decode(resp);
  }

  /// Binds a logical entity to an endpoint (returns the DeviceDTO).
  /// `controlled_area_id` is omitted when null.
  Future<Map<String, dynamic>> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  }) async {
    final resp = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}/bindings',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'endpoint_id': endpointId,
        'entity_id': entityId,
        'capability': capability,
        'controlled_area_id': ?controlledAreaId,
      }),
    );
    return _decode(resp);
  }

  /// Removes a binding (returns the DeviceDTO).
  Future<Map<String, dynamic>> unbindEntity(
    String deviceId,
    String bindingId,
  ) async {
    final resp = await _client.delete(
      Uri.parse(
        '$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}'
        '/bindings/${Uri.encodeComponent(bindingId)}',
      ),
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

  /// Nullable variant of [_decodeBody]: `jsonDecode` can legitimately return
  /// null for a literal `null` body, and endpoint actions need to tell that
  /// apart from a malformed body.
  Object? _decodeBodyOrNull(http.Response resp) {
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
  }) => _get(
    '/api/v1/cameras/${Uri.encodeComponent(cameraId)}/stream?profile=$profile',
  );

  Future<String> webrtcAnswer(String cameraId, String offerSdp) async {
    final resp = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/cameras/'
        '${Uri.encodeComponent(cameraId)}/webrtc?profile=sub',
      ),
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

  // --- Spotify playback ----------------------------------------------------

  Future<Map<String, dynamic>> spotifyPlayer() =>
      _get('/api/v1/spotify/player');

  Future<Map<String, dynamic>> spotifyDevices() =>
      _get('/api/v1/spotify/devices');

  /// Starts playback. Requires exactly one selector — [uri], [contextUri] or
  /// [query] (the backend resolves a query to its first match). Only non-null
  /// fields are sent; `device_id` null lets the backend resolve the device.
  Future<Map<String, dynamic>> spotifyPlay({
    String? uri,
    String? contextUri,
    String? query,
    String? deviceId,
    int? positionMs,
  }) async {
    final selectors = [
      uri,
      contextUri,
      query,
    ].where((value) => value != null && value.isNotEmpty).length;
    if (selectors != 1) {
      throw ArgumentError(
        'spotifyPlay requires exactly one of uri, contextUri or query',
      );
    }
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/spotify/play'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uri': ?uri,
        'context_uri': ?contextUri,
        'query': ?query,
        'device_id': ?deviceId,
        'position_ms': ?positionMs,
      }),
    );
    return _decode(resp);
  }

  /// POSTs a device-scoped playback command. The body is omitted when
  /// [deviceId] is null so the backend resolves the active/default device.
  Future<Map<String, dynamic>> _spotifyCommand(
    String action, {
    String? deviceId,
  }) async {
    final hasDevice = deviceId != null;
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/spotify/$action'),
      headers: hasDevice ? {'Content-Type': 'application/json'} : null,
      body: hasDevice ? jsonEncode({'device_id': deviceId}) : null,
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> spotifyPause({String? deviceId}) =>
      _spotifyCommand('pause', deviceId: deviceId);

  Future<Map<String, dynamic>> spotifyResume({String? deviceId}) =>
      _spotifyCommand('resume', deviceId: deviceId);

  Future<Map<String, dynamic>> spotifyNext({String? deviceId}) =>
      _spotifyCommand('next', deviceId: deviceId);

  Future<Map<String, dynamic>> spotifyPrevious({String? deviceId}) =>
      _spotifyCommand('previous', deviceId: deviceId);

  Future<Map<String, dynamic>> spotifySetVolume(
    int volumePercent, {
    String? deviceId,
  }) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/spotify/volume'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'volume_percent': volumePercent,
        'device_id': ?deviceId,
      }),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> spotifySeek(
    int positionMs, {
    String? deviceId,
  }) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/spotify/seek'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'position_ms': positionMs, 'device_id': ?deviceId}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> spotifyTransfer(String deviceId) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/spotify/transfer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId}),
    );
    return _decode(resp);
  }

  Future<Map<String, dynamic>> spotifyShuffle(
    bool state, {
    String? deviceId,
  }) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/spotify/shuffle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'state': state, 'device_id': ?deviceId}),
    );
    return _decode(resp);
  }

  /// [state] is one of `off`, `track`, `context`.
  Future<Map<String, dynamic>> spotifyRepeat(
    String state, {
    String? deviceId,
  }) async {
    final resp = await _client.put(
      Uri.parse('$baseUrl/api/v1/spotify/repeat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'state': state, 'device_id': ?deviceId}),
    );
    return _decode(resp);
  }

  /// Adds [uri] to the playback queue (POST). See [spotifyPlaybackQueue]
  /// for the read-only listing of the same route.
  Future<Map<String, dynamic>> spotifyQueue(
    String uri, {
    String? deviceId,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/spotify/queue'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'uri': uri, 'device_id': ?deviceId}),
    );
    return _decode(resp);
  }

  /// Read-only playback queue listing:
  /// `GET /api/v1/spotify/queue?limit=N` →
  /// `{previous, upcoming, source, limited}`.
  Future<Map<String, dynamic>> spotifyPlaybackQueue({int limit = 20}) =>
      _get('/api/v1/spotify/queue?limit=$limit');

  Future<Map<String, dynamic>> voiceStatus() => _get('/api/v1/voice/status');

  Future<Map<String, dynamic>> ttsSettings() => _get('/api/v1/tts/settings');

  /// Synthesizes a voice preview; returns the raw WAV bytes. Backend errors
  /// (400 missing voice, 502 synthesis failure) throw [ApiException] with the
  /// decoded JSON body when possible.
  Future<Uint8List> ttsPreview(String voice, String text) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/v1/tts/preview'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'voice': voice, 'text': text}),
    );
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _decodeBody(resp));
    }
    return resp.bodyBytes;
  }

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

  /// Flujo SSE de voz de una sesión: reenvía Last-Event-ID al reconectar
  /// (desde las líneas `id:` y/o `payload.data.sequence`) y termina con
  /// `voice_finished` o si la sesión ya no existe (HTTP != 200).
  /// `isCancelled()` evita reconexiones tras un stop o dispose.
  Stream<Map<String, dynamic>> voiceEvents(
    String sessionId, {
    required bool Function() isCancelled,
  }) async* {
    String? lastEventId;
    while (!isCancelled()) {
      final req = http.Request(
        'GET',
        Uri.parse(
          '$baseUrl/api/v1/voice/events/${Uri.encodeComponent(sessionId)}',
        ),
      );
      if (lastEventId != null) req.headers['Last-Event-ID'] = lastEventId;
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
            // The backend emits both `id:` and `data.sequence`; the payload
            // value is the fallback when the id line is missing.
            if (payload is Map) {
              final inner = payload['data'];
              final sequence = inner is Map ? inner['sequence'] : null;
              if (sequence != null) lastEventId = sequence.toString();
            }
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
        } else if (line.startsWith('id:')) {
          lastEventId = line.substring('id:'.length).trim();
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
