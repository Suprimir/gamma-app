import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';

/// Interpolates the current playback position from the backend's position
/// anchor: `position_ms + (nowMs - timestamp_ms) * speed`, clamped to
/// `[0, duration_ms]`.
///
/// A speed <= 0 (paused) returns `position_ms`; without an anchor the track's
/// `progress_ms` is used; with no usable data the result is null. Pure so it
/// is testable without timers or a real clock.
int? interpolatedPositionMs(
  Map<String, dynamic>? player, {
  required int nowMs,
}) {
  if (player == null) return null;
  final track = player['track'];
  final durationMs = track is Map ? _asNum(track['duration_ms']) : null;
  final anchor = player['position'];
  if (anchor is Map) {
    final positionMs = _asNum(anchor['position_ms']);
    if (positionMs == null) return _trackProgressMs(player);
    final timestampMs = _asNum(anchor['timestamp_ms']);
    final speed = _asNum(anchor['speed']);
    if (timestampMs == null || speed == null || speed <= 0) {
      return _clampPosition(positionMs.round(), durationMs);
    }
    final elapsed = nowMs - timestampMs.round();
    return _clampPosition(
      positionMs.round() + (elapsed * speed).round(),
      durationMs,
    );
  }
  return _trackProgressMs(player);
}

int? _trackProgressMs(Map<String, dynamic> player) {
  final track = player['track'];
  if (track is! Map) return null;
  return _asNum(track['progress_ms'])?.round();
}

int _clampPosition(int value, num? durationMs) {
  if (value < 0) return 0;
  if (durationMs != null && value > durationMs) return durationMs.round();
  return value;
}

num? _asNum(Object? value) => value is num ? value : null;

/// Shared Spotify playback state for the desktop and wall surfaces.
///
/// Everything rendered from this controller reflects the last canonical
/// response or SSE event (or null/empty while unknown) — never a fabricated
/// track/device. Commands call the backend with the explicit
/// [selectedDeviceId] when the user picked one and `null` otherwise, so the
/// backend resolves the device.
class SpotifyPlayerController extends ChangeNotifier {
  SpotifyPlayerController(this.api);

  final ApiClient api;

  Map<String, dynamic>? _player;
  List<Map<String, dynamic>> _devices = const [];
  String? _defaultDeviceId;
  String? _selectedDeviceId;
  Map<String, dynamic> _queue = const {};
  bool _loading = false;
  String? _error;
  bool _needsAuth = false;
  Timer? _pollTimer;
  Timer? _resubscribeTimer;
  Timer? _ticker;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  bool _live = false;
  bool _disposed = false;

  /// Last `GET /spotify/player` body (or SSE merge), or null while unknown.
  Map<String, dynamic>? get player => _player;

  /// Last successfully loaded `GET /spotify/devices` list.
  List<Map<String, dynamic>> get devices => _devices;

  String? get defaultDeviceId => _defaultDeviceId;

  /// Explicit user pick; null means "let the backend resolve the device".
  String? get selectedDeviceId => _selectedDeviceId;

  bool get loading => _loading;

  /// Spanish message from the last command/refresh failure, or null.
  String? get error => _error;

  /// True while the service answers 503 (module disabled / not authorized) or
  /// 401 (auth expired): the surfaces then show the connect-account affordance.
  bool get needsAuth => _needsAuth;

  bool get isPlaying => _player?['is_playing'] == true;

  /// Current track map, or null when the player has no playback loaded.
  Map<String, dynamic>? get track {
    final value = _player?['track'];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  /// Player-reported device, else the explicit pick, else the backend default.
  Map<String, dynamic>? get activeDevice {
    final fromPlayer = _player?['device'];
    if (fromPlayer is Map) return fromPlayer.cast<String, dynamic>();
    final wanted = _selectedDeviceId ?? _defaultDeviceId;
    if (wanted == null) return null;
    for (final device in _devices) {
      if (device['id'] == wanted) return device;
    }
    return null;
  }

  /// Upcoming tracks from the last queue event/fetch, empty while unknown.
  List<Map<String, dynamic>> get upcomingQueue => _queueList('upcoming');

  /// Tracks played before the current one, empty while unknown.
  List<Map<String, dynamic>> get previousQueue => _queueList('previous');

  /// True when the backend truncated the queue listing.
  bool get queueLimited => _queue['limited'] == true;

  /// Interpolated playback position in ms; null while unknown.
  int? get progressMs => interpolatedPositionMs(
    _player,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );

  /// Current track duration in ms; null while unknown.
  int? get durationMs {
    final value = track?['duration_ms'];
    return value is num ? value.round() : null;
  }

  /// True when the backend did not advertise an action list (legacy player
  /// responses keep the previous gating) or when [action] is advertised.
  bool actionEnabled(String action) {
    final actions = _player?['actions'];
    if (actions is! List || actions.isEmpty) return true;
    return actions.contains(action);
  }

  /// Loads the player state, the device list and the playback queue. The
  /// device and queue calls are non-fatal: a failed listing keeps the last
  /// known data.
  Future<void> refresh() async {
    if (_disposed) return;
    _loading = true;
    notifyListeners();

    Map<String, dynamic>? player;
    Object? playerError;
    try {
      player = await api.spotifyPlayer();
    } catch (error) {
      playerError = error;
    }
    if (_disposed) return;

    List<Map<String, dynamic>> devices = _devices;
    String? defaultDeviceId = _defaultDeviceId;
    try {
      final data = await api.spotifyDevices();
      devices =
          (data['devices'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      defaultDeviceId = data['default_device_id']?.toString();
    } catch (_) {
      // Non-fatal: device discovery failing never erases known devices.
    }
    if (_disposed) return;

    Map<String, dynamic> queue = _queue;
    try {
      final data = await api.spotifyPlaybackQueue(limit: 20);
      queue = _normalizeQueue(data);
    } catch (_) {
      // Non-fatal: a failed queue read keeps the last known queue.
    }
    if (_disposed) return;

    if (playerError != null) {
      _player = null;
      _needsAuth = _isAuthError(playerError);
      _error = _needsAuth ? null : _describe(playerError);
    } else {
      _player = player;
      _needsAuth = false;
      _error = null;
    }
    // Devices and queue apply independently: a failed player call must not
    // erase successful listings (and vice versa).
    _devices = devices;
    _defaultDeviceId = defaultDeviceId;
    _queue = queue;
    _loading = false;
    _syncTicker();
    notifyListeners();
  }

  Future<void> play() =>
      _command(() => api.spotifyResume(deviceId: _selectedDeviceId));

  Future<void> pause() =>
      _command(() => api.spotifyPause(deviceId: _selectedDeviceId));

  Future<void> next() =>
      _command(() => api.spotifyNext(deviceId: _selectedDeviceId));

  Future<void> previous() =>
      _command(() => api.spotifyPrevious(deviceId: _selectedDeviceId));

  Future<void> playContext(String uri) => _command(
    () => api.spotifyPlay(contextUri: uri, deviceId: _selectedDeviceId),
  );

  Future<void> playUri(String uri) =>
      _command(() => api.spotifyPlay(uri: uri, deviceId: _selectedDeviceId));

  Future<void> setVolume(int volumePercent) => _command(
    () => api.spotifySetVolume(volumePercent, deviceId: _selectedDeviceId),
  );

  Future<void> shuffle(bool state) =>
      _command(() => api.spotifyShuffle(state, deviceId: _selectedDeviceId));

  Future<void> repeat(String state) =>
      _command(() => api.spotifyRepeat(state, deviceId: _selectedDeviceId));

  /// Transfers playback to [deviceId] and remembers it as the explicit pick.
  Future<void> transferTo(String deviceId) {
    _selectedDeviceId = deviceId;
    notifyListeners();
    return _command(() => api.spotifyTransfer(deviceId));
  }

  /// Stores (or clears, with null) the explicit device pick. No API call:
  /// `null` lets the backend resolve the active/default device.
  void selectDevice(String? deviceId) {
    if (deviceId == _selectedDeviceId) return;
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  /// Starts periodic refreshes plus the SSE stream. [interval] <=
  /// [Duration.zero] disables everything (tests mount with zero so no timer
  /// or subscription outlives the widget tree). The interval is the fallback
  /// cadence; SSE events converge state in between.
  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    stopPolling();
    if (_disposed || interval <= Duration.zero) return;
    _live = true;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
    _subscribeEvents();
    _syncTicker();
  }

  void stopPolling() {
    _live = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _ticker?.cancel();
    _ticker = null;
    unawaited(_eventsSub?.cancel());
    _eventsSub = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }

  /// Subscribes to the shared event stream. A dropped stream triggers one
  /// immediate refresh and a resubscribe after ~5s while polling is live.
  void _subscribeEvents() {
    unawaited(_eventsSub?.cancel());
    _eventsSub = api.events().listen(
      _onEvent,
      onError: (Object _, StackTrace _) => _handleStreamDown(),
      onDone: _handleStreamDown,
    );
  }

  void _handleStreamDown() {
    if (_disposed || !_live) return;
    unawaited(refresh());
    if (_resubscribeTimer != null) return;
    _resubscribeTimer = Timer(const Duration(seconds: 5), () {
      _resubscribeTimer = null;
      if (_disposed || !_live) return;
      _subscribeEvents();
    });
  }

  void _onEvent(Map<String, dynamic> event) {
    final data = event['data'];
    if (data is! Map) return;
    switch (event['event']) {
      case 'spotify_state_changed':
        _applyStateEvent(data.cast<String, dynamic>());
      case 'spotify_queue_changed':
        _applyQueueEvent(data.cast<String, dynamic>());
    }
  }

  /// Merges an SSE `spotify_state_changed` payload over the last player
  /// response. The event carries no device, so the previous device map is
  /// preserved; it is proof of a usable account, so auth/error are cleared.
  void _applyStateEvent(Map<String, dynamic> data) {
    final merged = <String, dynamic>{...?_player};
    final status = data['status'];
    if (status is String) {
      merged['is_playing'] = status == 'playing' || status == 'buffering';
    }
    if (data.containsKey('item')) {
      final item = data['item'];
      merged['track'] = item is Map ? item.cast<String, dynamic>() : null;
    }
    final volume = data['volume'];
    if (volume is num) merged['volume_percent'] = volume.round();
    if (data.containsKey('shuffle')) merged['shuffle'] = data['shuffle'];
    if (data.containsKey('repeat')) merged['repeat'] = data['repeat'];
    final position = data['position'];
    if (position is Map) {
      merged['position'] = position.cast<String, dynamic>();
    }
    final actions = data['actions'];
    if (actions is List) merged['actions'] = actions;
    if (data.containsKey('is_active')) merged['is_active'] = data['is_active'];
    merged['has_playback'] = true;
    _player = merged;
    _needsAuth = false;
    _error = null;
    _syncTicker();
    notifyListeners();
  }

  void _applyQueueEvent(Map<String, dynamic> data) {
    _queue = _normalizeQueue(data);
    notifyListeners();
  }

  Map<String, dynamic> _normalizeQueue(Map<String, dynamic> data) => {
    'previous': data['previous'] is List ? data['previous'] : const [],
    'upcoming': data['upcoming'] is List ? data['upcoming'] : const [],
    'limited': data['limited'] == true,
  };

  List<Map<String, dynamic>> _queueList(String key) {
    final value = _queue[key];
    return value is List ? value.cast<Map<String, dynamic>>() : const [];
  }

  /// Advances the local progress while playing. Only a live controller with
  /// an anchor and a non-zero speed ticks; paused playback stays honest and
  /// zero-interval controllers never start a timer.
  void _syncTicker() {
    final anchor = _player?['position'];
    final speed = anchor is Map ? _asNum(anchor['speed']) : null;
    final wanted =
        _live &&
        !_disposed &&
        isPlaying &&
        anchor is Map &&
        speed != null &&
        speed != 0;
    if (wanted) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Runs one backend command, then refreshes so the UI converges on the
  /// canonical state. Failures land in [error]/[needsAuth]; they never throw
  /// at the UI. The command failure wins over a successful refresh.
  Future<void> _command(Future<Map<String, dynamic>> Function() run) async {
    String? failure;
    var authFailure = false;
    try {
      await run();
    } on ApiException catch (error) {
      if (_isAuthError(error)) {
        authFailure = true;
      } else {
        failure = _describe(error);
      }
    } catch (error) {
      failure = _describe(error);
    }
    if (_disposed) return;

    await refresh();
    if (_disposed) return;

    if (authFailure) {
      _needsAuth = true;
      _error = null;
      notifyListeners();
    } else if (failure != null) {
      _error = failure;
      notifyListeners();
    }
  }

  bool _isAuthError(Object error) =>
      error is ApiException &&
      (error.statusCode == 401 || error.statusCode == 503);

  String _describe(Object error) {
    if (error is ApiException) {
      final body = error.body;
      final detail = body is Map ? body['detail'] : null;
      if (detail is String && detail.isNotEmpty) return detail;
      return 'Error del servidor (${error.statusCode}).';
    }
    return error.toString();
  }
}
