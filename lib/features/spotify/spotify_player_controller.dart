import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';

/// Shared Spotify playback state for the desktop and wall surfaces.
///
/// Everything rendered from this controller reflects the last canonical
/// response (or null/empty while unknown) — never a fabricated track/device.
/// Commands call the backend with the explicit [selectedDeviceId] when the
/// user picked one and `null` otherwise, so the backend resolves the device.
class SpotifyPlayerController extends ChangeNotifier {
  SpotifyPlayerController(this.api);

  final ApiClient api;

  Map<String, dynamic>? _player;
  List<Map<String, dynamic>> _devices = const [];
  String? _defaultDeviceId;
  String? _selectedDeviceId;
  bool _loading = false;
  String? _error;
  bool _needsAuth = false;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Last `GET /spotify/player` body, or null while unknown/unavailable.
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

  /// Loads the player state and the device list. The device call is
  /// non-fatal: a failed listing keeps the last known devices.
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

    if (playerError != null) {
      _player = null;
      _needsAuth = _isAuthError(playerError);
      _error = _needsAuth ? null : _describe(playerError);
    } else {
      _player = player;
      _needsAuth = false;
      _error = null;
    }
    // Devices apply independently: a failed player call must not erase a
    // successful device listing (and vice versa).
    _devices = devices;
    _defaultDeviceId = defaultDeviceId;
    _loading = false;
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

  /// Starts periodic refreshes. [interval] <= [Duration.zero] disables
  /// polling (tests mount with zero so no timer outlives the widget tree).
  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    stopPolling();
    if (_disposed || interval <= Duration.zero) return;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
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
