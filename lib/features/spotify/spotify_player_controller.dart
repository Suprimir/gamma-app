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

/// Canonical Spotify playback state for every surface.
///
/// [GammaApp] owns one instance and shares it through `SpotifyScope`, so the
/// wall music card, the sleep chip and the desktop dashboard render the same
/// state with a single poll and a single SSE subscription. On its own (tests,
/// previews, a page mounted without the app shell) a surface owns a local one.
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

  /// Current fallback poll cadence; swapped by [setPollInterval] without
  /// touching the SSE subscription or the canonical state.
  Duration _pollInterval = Duration.zero;

  /// Optimistic seek target while the backend round-trip is in flight: target
  /// ms, local wall-clock ms when it was issued and the playback speed
  /// captured at that moment (0 while paused).
  ({int ms, int wallMs, double speed})? _pendingSeek;

  /// Optimistic transfer target while the backend catches up: the picked
  /// device id plus the local wall-clock ms when it was set. Bounded by
  /// [_pendingDeviceTimeoutMs] and cleared once canonical state confirms it.
  ({String id, int wallMs})? _pendingDevice;

  /// Bumped on every applied SSE state event. An HTTP player read that started
  /// before a bump is stale and must not overwrite the fresher event.
  int _stateVersion = 0;

  /// Last reactive refresh issued from an SSE device signal; guards the
  /// debounce so a burst of events cannot hammer the backend.
  int? _lastReactiveRefreshMs;

  /// One-shot follow-up scheduled after a deactivation whose canonical state
  /// was still stale; bounded so no refresh loop can form.
  Timer? _reactiveRetryTimer;

  /// Safety window for a pending seek; after it the preview falls back to the
  /// canonical state instead of masking a lost acknowledgement forever.
  static const _pendingSeekTimeoutMs = 10000;

  /// Safety window for the optimistic transfer target; after it the card falls
  /// back to canonical state instead of masking a lost switch forever.
  static const _pendingDeviceTimeoutMs = 12000;

  /// At most one reactive refresh per window, driven by SSE device signals.
  static const _reactiveRefreshDebounceMs = 2000;

  /// Delay before the single bounded follow-up refresh.
  static const _reactiveRetryDelay = Duration(milliseconds: 1500);

  /// Single-flight del sondeo: un lote de llamadas concurrentes a [refresh]
  /// comparte una sola lectura HTTP, y a lo sumo una repetición si algo llegó
  /// mientras esa lectura estaba en vuelo.
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _queuedForce = false;
  final List<Completer<void>> _refreshWaiters = [];

  /// Epoch ms of the last device listing read (null = never). Devices ride a
  /// slower cadence than the player: the transport is the hot path and every
  /// listing read costs a backend-to-Spotify call.
  int? _devicesFetchedAtMs;

  /// Epoch ms of the last playback-queue read (null = never). The queue also
  /// arrives through `spotify_queue_changed`, so polling it is only a safety
  /// net for a missed event.
  int? _queueFetchedAtMs;

  /// Serializa las lecturas secundarias para que pases solapados no dupliquen
  /// tráfico de dispositivos/cola, y recuerda un pedido forzado que llegó
  /// mientras otra pasada corría (una orden o el picker no deben perderse).
  bool _detailsInFlight = false;
  bool _detailsForcedPending = false;

  /// Epoch ms of the last applied Spotify SSE event. A poll tick inside the
  /// cadence window is skipped: the stream already delivered newer state.
  int? _lastStateEventMs;

  /// Secondary listing cadences, both slower than the player poll.
  static const _devicesRefreshIntervalMs = 15000;
  static const _queueRefreshIntervalMs = 20000;

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
  ///
  /// An in-flight transfer optimistically wins: the card must not keep showing
  /// the previous device while the backend catches up. The override expires
  /// after [_pendingDeviceTimeoutMs].
  Map<String, dynamic>? get activeDevice {
    _expirePendingDevice();
    final pendingId = _pendingDevice?.id;
    if (pendingId != null) {
      final pending = _deviceById(pendingId);
      if (pending != null) return pending;
    }
    final fromPlayer = _player?['device'];
    if (fromPlayer is Map) return fromPlayer.cast<String, dynamic>();
    final wanted = _selectedDeviceId ?? _defaultDeviceId;
    if (wanted == null) return null;
    return _deviceById(wanted);
  }

  Map<String, dynamic>? _deviceById(String id) {
    for (final device in _devices) {
      if (device['id']?.toString() == id) return device;
    }
    return null;
  }

  /// Listing entry whose name matches [name]: exact first, then
  /// case-insensitive. Null when the listing does not know the device.
  Map<String, dynamic>? _deviceByName(String name) {
    for (final device in _devices) {
      if (device['name']?.toString() == name) return device;
    }
    final lower = name.toLowerCase();
    for (final device in _devices) {
      if (device['name']?.toString().toLowerCase() == lower) return device;
    }
    return null;
  }

  /// Drops the optimistic transfer target once its bounded window elapsed.
  void _expirePendingDevice() {
    final pending = _pendingDevice;
    if (pending == null) return;
    if (_nowMs() - pending.wallMs >= _pendingDeviceTimeoutMs) {
      _pendingDevice = null;
    }
  }

  /// Drops the optimistic transfer target (command failure / teardown).
  void _clearPendingDevice() {
    _pendingDevice = null;
  }

  /// Clears the optimistic target when [player] reports its id as the
  /// canonical device (HTTP refresh or SSE merge).
  void _settlePendingDeviceByCanonical(Map<String, dynamic>? player) {
    _expirePendingDevice();
    final pending = _pendingDevice;
    if (pending == null) return;
    final device = player?['device'];
    if (device is Map && device['id']?.toString() == pending.id) {
      _pendingDevice = null;
    }
  }

  /// Clears the optimistic target when an SSE event names the pending device:
  /// the real switch happened even before the HTTP listing catches up.
  void _clearPendingDeviceIfNamed(String eventName) {
    final pending = _pendingDevice;
    if (pending == null) return;
    final pendingName = _deviceById(pending.id)?['name']?.toString();
    if (pendingName == null || pendingName.isEmpty) return;
    if (pendingName == eventName ||
        pendingName.toLowerCase() == eventName.toLowerCase()) {
      _pendingDevice = null;
    }
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

  /// Loads the player state and publishes it as soon as it arrives; the device
  /// listing and the playback queue refresh behind it (see [_scheduleDetails]),
  /// so the track/pause/seek state never waits on secondary reads — and a slow
  /// listing never delays the next pass.
  ///
  /// Concurrent calls are coalesced into a single HTTP read; a poll that
  /// overlaps another joins the in-flight batch, while an explicit request
  /// (command convergence, picker) queues at most one follow-up pass so it
  /// never renders state read before it was issued.
  ///
  /// [forceDetails] refreshes the secondary listings regardless of their
  /// cadence (user commands, picker open) without making the player read wait.
  Future<void> refresh({bool forceDetails = false}) {
    if (_disposed) return Future<void>.value();
    if (forceDetails) _queuedForce = true;
    final waiter = Completer<void>();
    _refreshWaiters.add(waiter);
    if (_refreshing) {
      // Solo un pedido explícito (convergencia post-orden, picker) justifica
      // releer: un sondeo que coincide con otro se une al lote en vuelo.
      if (forceDetails) _refreshQueued = true;
    } else {
      _refreshing = true;
      unawaited(_drainRefreshes());
    }
    return waiter.future;
  }

  /// Runs the coalesced refresh passes and completes every waiting caller once
  /// the queue drains. Each pass publishes the player and hands the secondary
  /// listings to [_scheduleDetails], so a slow listing never delays the next
  /// pass.
  Future<void> _drainRefreshes() async {
    try {
      do {
        _refreshQueued = false;
        final force = _queuedForce;
        _queuedForce = false;
        await _refreshPlayerOnce(forceDetails: force);
      } while (_refreshQueued && !_disposed);
    } finally {
      _refreshing = false;
      _refreshQueued = false;
      _queuedForce = false;
      final waiters = _refreshWaiters.toList();
      _refreshWaiters.clear();
      for (final waiter in waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  /// One player read. The device listing and the playback queue refresh behind
  /// it (see [_scheduleDetails]).
  Future<void> _refreshPlayerOnce({required bool forceDetails}) async {
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

    // Un evento SSE que llegó durante la lectura es más nuevo: ni el cuerpo ni
    // el error de esta respuesta pueden pisarlo (el error viejo no debe borrar
    // la canción que el evento acaba de traer, ni marcar falta de cuenta).
    final stale = versionBeforePlayer != _stateVersion;
    if (!stale) {
      if (playerError != null) {
        final authFailure = _isAuthError(playerError);
        _needsAuth = authFailure;
        _error = authFailure ? null : _describe(playerError);
        // Un fallo transitorio (límite de tasa, 5xx, red) conserva la última
        // canción conocida en vez de vaciar la tarjeta; una respuesta
        // definitiva (sin autorización, sin dispositivo activo) sí la limpia.
        if (authFailure || !_keepsLastPlayerOnError(playerError)) {
          _player = null;
        }
      } else {
        _player = player;
        _acknowledgePendingSeek(player);
        _settlePendingDeviceByCanonical(player);
        _needsAuth = false;
        _error = null;
      }
    }
    _loading = false;
    _syncTicker();
    notifyListeners();

    _scheduleDetails(force: forceDetails);
  }

  /// Schedules the secondary listings behind the player read.
  ///
  /// They never block a player pass: un `/devices` (o `/queue`) colgado no debe
  /// retrasar el siguiente sondeo ni la convergencia tras una orden. Un pedido
  /// forzado que llega mientras otra pasada corre se encola una vez.
  void _scheduleDetails({required bool force}) {
    if (_disposed) return;
    if (force) _detailsForcedPending = true;
    if (_detailsInFlight) return;
    unawaited(_drainDetails());
  }

  Future<void> _drainDetails() async {
    _detailsInFlight = true;
    try {
      do {
        final force = _detailsForcedPending;
        _detailsForcedPending = false;
        await _refreshDetailsOnce(force: force);
      } while (!_disposed && _detailsForcedPending);
    } finally {
      _detailsInFlight = false;
      _detailsForcedPending = false;
    }
  }

  /// Refreshes the device listing and the playback queue, gated by their own
  /// cadences. Non-fatal: a failed listing keeps the last known data and never
  /// erases the canonical player state.
  Future<void> _refreshDetailsOnce({required bool force}) async {
    if (_disposed) return;
    final now = _nowMs();
    final devicesDue =
        force ||
        _devicesFetchedAtMs == null ||
        now - _devicesFetchedAtMs! >= _devicesRefreshIntervalMs;
    // La cola en tiempo real (Soloist) solo se pide con reproducción activa:
    // sin playback, el backend responde 503 (Soloist no disponible) y el
    // fetch únicamente ensucia la consola del navegador.
    final playbackActive =
        _player?['has_playback'] == true || _player?['is_playing'] == true;
    final queueDue =
        playbackActive &&
        (force ||
            _queueFetchedAtMs == null ||
            now - _queueFetchedAtMs! >= _queueRefreshIntervalMs);
    if (!devicesDue && !queueDue) return;

    if (devicesDue) {
      try {
        final data = await api.spotifyDevices();
        if (_disposed) return;
        _devices =
            (data['devices'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        _defaultDeviceId = data['default_device_id']?.toString();
        _devicesFetchedAtMs = _nowMs();
        notifyListeners();
      } catch (_) {
        // Non-fatal: device discovery failing never erases known devices.
      }
    }
    if (_disposed) return;
    if (queueDue) {
      try {
        final data = await api.spotifyPlaybackQueue(limit: 20);
        if (_disposed) return;
        _queue = _normalizeQueue(data);
        _queueFetchedAtMs = _nowMs();
        notifyListeners();
      } catch (_) {
        // Non-fatal: a failed queue read keeps the last known queue.
      }
    }
  }

  /// Refreshes the player and the secondary listings on demand. Wired to the
  /// device picker and to command convergence so a freshly started device
  /// appears without waiting for the listing cadence.
  Future<void> refreshNow() => refresh(forceDetails: true);

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
  ///
  /// The pick is shown immediately (optimistic override over the device
  /// listing) and cleared once canonical state confirms it, the command
  /// fails, or the bounded window elapses.
  Future<void> transferTo(String deviceId) {
    _selectedDeviceId = deviceId;
    _pendingDevice = (id: deviceId, wallMs: _nowMs());
    notifyListeners();
    return _command(
      () => api.spotifyTransfer(deviceId),
      onCommandFailure: _clearPendingDevice,
    );
  }

  /// Stores (or clears, with null) the explicit device pick. No API call:
  /// `null` lets the backend resolve the active/default device and drops any
  /// in-flight optimistic transfer so Automático wins immediately.
  void selectDevice(String? deviceId) {
    if (deviceId == _selectedDeviceId) return;
    _selectedDeviceId = deviceId;
    if (deviceId == null) _pendingDevice = null;
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
    _pollInterval = interval;
    _pollTimer = Timer.periodic(interval, (_) => _pollTick(interval));
    _subscribeEvents();
    _syncTicker();
  }

  /// Changes the fallback poll cadence while keeping the SSE subscription and
  /// the canonical state (foreground/background switching). Zero pauses the
  /// poll; the stream stays live.
  void setPollInterval(Duration interval) {
    if (_disposed || !_live) return;
    if (interval == _pollInterval && _pollTimer != null) return;
    _pollInterval = interval;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (interval <= Duration.zero) return;
    _pollTimer = Timer.periodic(interval, (_) => _pollTick(interval));
  }

  /// One fallback poll tick. Only an applied playback change counts as fresh
  /// SSE state: a queue event or an ignored inactive snapshot must not suppress
  /// the read that reveals what another device (e.g. the phone) is playing.
  void _pollTick(Duration interval) {
    if (_disposed) return;
    final last = _lastStateEventMs;
    final sseFresh = last != null && _nowMs() - last < interval.inMilliseconds;
    if (sseFresh) {
      _scheduleDetails(force: false);
    } else {
      unawaited(refresh());
    }
  }

  void stopPolling() {
    _live = false;
    _pollInterval = Duration.zero;
    _pollTimer?.cancel();
    _pollTimer = null;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _reactiveRetryTimer?.cancel();
    _reactiveRetryTimer = null;
    _lastReactiveRefreshMs = null;
    _pendingSeek = null;
    _pendingDevice = null;
    _devicesFetchedAtMs = null;
    _queueFetchedAtMs = null;
    _lastStateEventMs = null;
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
        // Solo un evento aplicado marca frescura: un snapshot inactivo se
        // ignora y no debe suprimir el sondeo del dispositivo activo.
        if (_applyStateEvent(data.cast<String, dynamic>())) {
          _lastStateEventMs = _nowMs();
        }
      case 'spotify_queue_changed':
        // La cola no dice nada del reproductor activo: no marca frescura.
        _applyQueueEvent(data.cast<String, dynamic>());
      case 'resync_required':
        // El bus no pudo replayar la historia solicitada: la única salida
        // segura es releer el estado canónico y descartar la supresión de
        // sondeo para que el siguiente tick no se salte.
        _lastStateEventMs = null;
        unawaited(refresh());
    }
  }

  /// Merges an SSE `spotify_state_changed` payload over the last player
  /// response. When the event carries the active device name the matching
  /// listing entry wins, so the real id and capabilities resolve without
  /// waiting for the next HTTP read; otherwise the previous device map is
  /// preserved. Device signals the merge alone cannot resolve (deactivation
  /// of the shown device, or an active name missing from a stale listing)
  /// trigger a debounced canonical read. It is proof of a usable account, so
  /// auth/error are cleared.
  ///
  /// An event with `is_active == false` is never merged: the local renderer
  /// stopped being the active Connect device, so its snapshot does not describe
  /// what is playing (e.g. the phone took over). It only arms the reactive
  /// canonical read that resolves the new device.
  ///
  /// Returns true when the payload was applied as playback state; an ignored
  /// event must not count as fresh state for the fallback poll.
  bool _applyStateEvent(Map<String, dynamic> data) {
    final isActive = data['is_active'];
    final deviceName = data['device_name']?.toString();
    if (isActive == false) {
      // Solo reconcilia cuando el dispositivo que se muestra es el que dejó de
      // estar activo: la desactivación de otro renderer no cambia lo que suena.
      final shownName = _shownDeviceNamed(deviceName);
      if (shownName != null) {
        _scheduleReactiveRefresh(retryWhileShowing: shownName);
      }
      return false;
    }

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
    var unresolvedActiveDevice = false;
    if (deviceName != null && deviceName.isNotEmpty) {
      final entry = _deviceByName(deviceName);
      if (entry != null) {
        merged['device'] = entry;
      } else {
        // Stale listing: the active device is unknown here.
        unresolvedActiveDevice = true;
      }
      _clearPendingDeviceIfNamed(deviceName);
    }
    // has_playback refleja lo que el payload realmente trae: sin ítem y sin
    // reproducción no se anuncia reproducción (antes se forzaba a true).
    merged['has_playback'] =
        merged['track'] is Map || merged['is_playing'] == true;
    _player = merged;
    _settlePendingDeviceByCanonical(merged);
    _needsAuth = false;
    _error = null;
    // Any HTTP player read in flight started before this event is stale now.
    _stateVersion++;
    _acknowledgePendingSeek(merged);
    _syncTicker();
    notifyListeners();

    // Reactive convergence: an active name missing from a stale listing needs
    // a canonical read (debounced) to resolve the real device entry.
    if (unresolvedActiveDevice) {
      _scheduleReactiveRefresh();
    }
    return true;
  }

  /// Name of the currently shown device when it matches [deviceName]
  /// (case-insensitive); null otherwise. Arms the bounded follow-up refresh
  /// after a deactivation, because the core may still serve the old device for
  /// a moment.
  String? _shownDeviceNamed(String? deviceName) {
    if (deviceName == null || deviceName.isEmpty) return null;
    final shown = activeDevice?['name']?.toString();
    if (shown == null || shown.isEmpty) return null;
    return shown.toLowerCase() == deviceName.toLowerCase() ? shown : null;
  }

  /// Issues one canonical read at most every [_reactiveRefreshDebounceMs]
  /// after an SSE device signal. [retryWhileShowing] schedules exactly one
  /// bounded follow-up when the shown device still matches after
  /// [_reactiveRetryDelay] (the adapter may need a moment to catch up);
  /// the follow-up respects stop/dispose semantics and never loops.
  void _scheduleReactiveRefresh({String? retryWhileShowing}) {
    if (_disposed || !_live) return;
    final now = _nowMs();
    final last = _lastReactiveRefreshMs;
    if (last != null && now - last < _reactiveRefreshDebounceMs) return;
    _lastReactiveRefreshMs = now;
    unawaited(refresh());
    if (retryWhileShowing == null) return;

    _reactiveRetryTimer?.cancel();
    _reactiveRetryTimer = Timer(_reactiveRetryDelay, () {
      _reactiveRetryTimer = null;
      if (_disposed || !_live) return;
      final shownName = activeDevice?['name']?.toString();
      if (shownName == null || shownName.isEmpty) return;
      if (shownName.toLowerCase() != retryWhileShowing.toLowerCase()) return;
      unawaited(refresh());
    });
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

    // forceDetails: una orden puede haber arrancado/cambiado de dispositivo;
    // la convergencia no debe esperar la cadencia de listados.
    await refresh(forceDetails: true);
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

  /// True for transient failures (rate limit, server error, network) whose only
  /// sane reaction is keeping the last known state and retrying later.
  bool _keepsLastPlayerOnError(Object error) {
    if (error is ApiException) {
      return error.statusCode == 429 || error.statusCode >= 500;
    }
    return true;
  }

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
