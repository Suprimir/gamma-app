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

/// System wall clock in epoch ms; the controller's default [nowMs] source.
int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

/// Hint shown when the target device explicitly reports
/// `supports_volume == false`: GAMMA cannot control its volume via the API.
const spotifyVolumeUnsupportedHint =
    'Este dispositivo no permite controlar el volumen desde GAMMA';

/// Tooltip shown on the disabled volume trigger when the target device cannot
/// be volume-controlled via the API.
const spotifyVolumeUnsupportedTooltip =
    'Este dispositivo no permite controlar el volumen';

/// Shared Spotify playback state for the desktop and wall surfaces.
///
/// Everything rendered from this controller reflects the last canonical
/// response or SSE event (or null/empty while unknown) — never a fabricated
/// track/device. Commands call the backend with the explicit
/// [selectedDeviceId] when the user picked one and `null` otherwise, so the
/// backend resolves the device.
class SpotifyPlayerController extends ChangeNotifier {
  SpotifyPlayerController(this.api, {int Function()? nowMs})
    : _nowMs = nowMs ?? _systemNowMs;

  final ApiClient api;

  /// Wall-clock source in epoch ms; tests inject a deterministic clock to
  /// exercise the optimistic seek preview without real delays.
  final int Function() _nowMs;

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

  /// Optimistic seek target while the backend round-trip is in flight: target
  /// ms, local wall-clock ms when it was issued and the playback speed
  /// captured at that moment (0 while paused).
  ({int ms, int wallMs, double speed})? _pendingSeek;

  /// Bumped on every applied SSE state event. An HTTP player read that started
  /// before a bump is stale and must not overwrite the fresher event.
  int _stateVersion = 0;

  /// Safety window for a pending seek; after it the preview falls back to the
  /// canonical state instead of masking a lost acknowledgement forever.
  static const _pendingSeekTimeoutMs = 10000;

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

  /// Whether the resolved target device can be volume-controlled via the API.
  ///
  /// Resolution: [activeDevice], then its entry in the device listing by `id`,
  /// with a fallback match by `name` for synthetic ids (e.g. the
  /// Soloist-served player reports `soloist`, which never appears in the
  /// Spotify listing). Returns the listed `supports_volume` when it is a bool,
  /// otherwise null (unknown) so callers keep the legacy behavior.
  bool? get targetSupportsVolume {
    final target = activeDevice;
    if (target == null) return null;

    Map<String, dynamic>? entry;
    final id = target['id']?.toString();
    if (id != null && id.isNotEmpty) {
      for (final device in _devices) {
        if (device['id']?.toString() == id) {
          entry = device;
          break;
        }
      }
    }
    if (entry == null) {
      final name = target['name']?.toString();
      if (name != null && name.isNotEmpty) {
        for (final device in _devices) {
          if (device['name']?.toString() == name) {
            entry = device;
            break;
          }
        }
      }
    }
    final value = entry?['supports_volume'];
    return value is bool ? value : null;
  }

  /// Upcoming tracks from the last queue event/fetch, empty while unknown.
  List<Map<String, dynamic>> get upcomingQueue => _queueList('upcoming');

  /// Tracks played before the current one, empty while unknown.
  List<Map<String, dynamic>> get previousQueue => _queueList('previous');

  /// True when the backend truncated the queue listing.
  bool get queueLimited => _queue['limited'] == true;

  /// Interpolated playback position in ms; null while unknown.
  ///
  /// While a seek is in flight the optimistic target wins (advancing at the
  /// speed captured when it was issued) so the UI never snaps back to the
  /// pre-seek position during the round-trip. A pending seek older than
  /// [_pendingSeekTimeoutMs] is dropped silently.
  int? get progressMs {
    final pending = _pendingSeek;
    if (pending != null) {
      final elapsed = _nowMs() - pending.wallMs;
      if (elapsed < _pendingSeekTimeoutMs) {
        final position = pending.ms + (elapsed * pending.speed).round();
        final duration = durationMs;
        if (position < 0) return 0;
        if (duration != null && position > duration) return duration;
        return position;
      }
      // Expired: drop the preview and let the ticker state follow.
      _pendingSeek = null;
      _syncTicker();
    }
    return interpolatedPositionMs(_player, nowMs: _nowMs());
  }

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

    final versionBeforePlayer = _stateVersion;
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
      // An SSE state event that landed while this read was in flight is
      // fresher: keep it instead of overwriting with the stale body.
      final playerIsStale = versionBeforePlayer != _stateVersion;
      if (!playerIsStale) {
        _player = player;
        _acknowledgePendingSeek(player);
      }
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

  /// Seeks to [positionMs] in the current track. Negative values clamp to 0.
  ///
  /// The target is shown immediately (optimistic preview) before the backend
  /// call, so the scrubber never snaps back while the request runs. The
  /// preview clears when a fresher canonical anchor arrives, the call fails,
  /// polling stops, or the safety timeout elapses.
  Future<void> seek(int positionMs) {
    final target = positionMs < 0 ? 0 : positionMs;
    final anchor = _player?['position'];
    final anchorSpeed = anchor is Map ? _asNum(anchor['speed']) : null;
    _pendingSeek = (
      ms: target,
      wallMs: _nowMs(),
      speed: anchorSpeed?.toDouble() ?? (isPlaying ? 1.0 : 0.0),
    );
    _syncTicker();
    notifyListeners();
    return _command(
      () => api.spotifySeek(target, deviceId: _selectedDeviceId),
      onCommandFailure: _clearPendingSeek,
    );
  }

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
    _pendingSeek = null;
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

  /// Dispatches one stream frame.
  ///
  /// [ApiClient.events] yields `{'event': <name>, 'data': <decoded frame>}`,
  /// and the core bus wraps every payload in an envelope
  /// (`{id, event, data, timestamp}`), so the real payload lives one level
  /// deeper. Alternate producers that emit the payload directly still work
  /// through the fallback.
  void _onEvent(Map<String, dynamic> event) {
    final outer = event['data'];
    if (outer is! Map) return;
    var name = event['event'];
    var data = outer;
    final innerData = outer['data'];
    final innerName = outer['event'];
    if (innerData is Map && innerName is String) {
      name = innerName;
      data = innerData;
    }
    switch (name) {
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
    // Any HTTP player read in flight started before this event is stale now.
    _stateVersion++;
    _acknowledgePendingSeek(merged);
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
  /// an anchor and a non-zero speed ticks; an in-flight seek also keeps the
  /// ticker alive so its optimistic preview advances. Paused playback stays
  /// honest and zero-interval controllers never start a timer.
  void _syncTicker() {
    final anchor = _player?['position'];
    final speed = anchor is Map ? _asNum(anchor['speed']) : null;
    final wanted =
        _live &&
        !_disposed &&
        (_pendingSeek != null ||
            (isPlaying && anchor is Map && speed != null && speed != 0));
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
  /// [onCommandFailure] runs as soon as the command itself fails (before the
  /// convergence refresh), so callers can drop optimistic state immediately.
  Future<void> _command(
    Future<Map<String, dynamic>> Function() run, {
    VoidCallback? onCommandFailure,
  }) async {
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

    if (failure != null || authFailure) {
      onCommandFailure?.call();
    }

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

  /// Drops the optimistic seek target. Safe to call when none is pending.
  void _clearPendingSeek() {
    _pendingSeek = null;
  }

  /// Drops the optimistic seek target once the canonical state proves the
  /// backend applied it: an anchor measured after the seek was issued.
  void _acknowledgePendingSeek(Map<String, dynamic>? player) {
    final pending = _pendingSeek;
    if (pending == null) return;
    final position = player?['position'];
    final timestampMs = position is Map
        ? _asNum(position['timestamp_ms'])
        : null;
    if (timestampMs != null && timestampMs.round() > pending.wallMs) {
      _pendingSeek = null;
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
