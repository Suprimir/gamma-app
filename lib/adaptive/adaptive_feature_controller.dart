import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device_capability_commit.dart';
import '../data/device_inventory.dart';

/// Estado compartido de la feature Devices/Areas para las superficies
/// Mobile/Desktop/Wall. El controlador posee el snapshot, la selección y las
/// cargas canónicas; las mutaciones por dispositivo siguen viviendo en las
/// páginas de detalle (Fase 8 las centraliza aquí).
class AdaptiveFeatureController extends ChangeNotifier {
  AdaptiveFeatureController(this._repository);

  final DeviceInventoryRepository _repository;

  /// Set when [dispose] runs; guards in-flight async work from notifying a
  /// disposed notifier (F3-C Phase 12 hardening).
  bool _disposed = false;

  /// Notifies listeners unless the controller was already disposed. Every
  /// public mutator and async phase routes through here so a load/mutation
  /// that completes after teardown never touches the listener list.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Repositorio canónico de inventario; las páginas lo necesitan para las
  /// mutaciones por dispositivo (Fase 3-C desktop).
  DeviceInventoryRepository get repository => _repository;

  /// Whether the repository implements the segregated command surface
  /// ([DeviceCommandRepository]). Plain test fakes without commands keep the
  /// local fallback behavior on every surface.
  bool get supportsEndpointCommands =>
      asDeviceCommandRepository(_repository) != null;

  /// Whether the repository can trigger the backend bulk state sweep
  /// ([DeviceStateRefreshRepository]). Plain test fakes stay without it.
  bool get supportsStateRefresh =>
      asDeviceStateRefreshRepository(_repository) != null;

  DeviceInventorySnapshot? _snapshot;
  Object? _deviceError;
  bool _devicesLoading = false;
  bool _discovering = false;
  String? _selectedDeviceId;

  /// In-flight guard for [refreshStatesAndReload]: at most one sweep at a
  /// time so repeated gestures never stack network work.
  bool _statesRefreshInFlight = false;

  /// One-shot guard for the automatic sweep after the first successful load.
  bool _autoSweepDone = false;

  /// One-shot guard for the lazy SSE subscription after the first successful
  /// load. The stream is passive: the server pushes state updates, the client
  /// never polls. Plain test fakes without [DeviceEventStreamRepository] never
  /// subscribe.
  bool _eventsSubscribed = false;

  /// Live core-bus subscription; cancelled in [dispose].
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  /// Ids created through [addLocalDevice] ("Agregar dispositivo") that the
  /// backend doesn't know yet. Every canonical reload re-appends them, so a
  /// locally created device is never wiped from the list (e.g. when coming
  /// back from its detail after turning it off: it must stay visible as
  /// "Apagado", never disappear).
  final Set<String> _localOnlyIds = {};

  List<HomeArea>? _areas;
  Object? _areasError;
  bool _areasLoading = false;
  bool _areaMutating = false;
  String? _selectedAreaId;

  DeviceInventorySnapshot? get snapshot => _snapshot;
  Object? get deviceError => _deviceError;
  bool get devicesLoading => _devicesLoading;
  bool get discovering => _discovering;
  String? get selectedDeviceId => _selectedDeviceId;

  List<HomeArea>? get areas => _areas;
  Object? get areasError => _areasError;
  bool get areasLoading => _areasLoading;
  bool get areaMutating => _areaMutating;
  String? get selectedAreaId => _selectedAreaId;

  PhysicalDevice? get selectedDevice {
    final id = _selectedDeviceId;
    if (id == null || _snapshot == null) return null;
    for (final device in _snapshot!.devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  HomeArea? get selectedArea {
    final id = _selectedAreaId;
    if (id == null || _areas == null) return null;
    for (final area in _areas!) {
      if (area.id == id) return area;
    }
    return null;
  }

  Future<void> loadDevices() async {
    _devicesLoading = true;
    _deviceError = null;
    _notify();
    var loaded = false;
    try {
      final previousLocals = _localOnlyDevices();
      _snapshot = await _repository.load();
      _restoreLocalDevices(previousLocals);
      _clearStaleSelection();
      loaded = true;
    } catch (error) {
      _deviceError = error;
    } finally {
      _devicesLoading = false;
      _notify();
    }
    _maybeAutoSweep(loaded);
    _maybeSubscribeEvents(loaded);
  }

  /// One-shot automatic state sweep after the first successful inventory
  /// load, only when the repository supports it. Fire-and-forget: the load
  /// path never awaits it and no timer is involved. Plain test fakes (no
  /// [DeviceStateRefreshRepository]) are untouched.
  void _maybeAutoSweep(bool loaded) {
    if (!loaded || _autoSweepDone) return;
    if (!supportsStateRefresh) return;
    _autoSweepDone = true;
    unawaited(refreshStatesAndReload());
  }

  /// One-shot lazy subscription to the repository's passive SSE surface,
  /// started after the first successful inventory load. Repositories without
  /// [DeviceEventStreamRepository] (plain fakes) never subscribe, so tests
  /// stay timer-free and no behavior changes for them.
  void _maybeSubscribeEvents(bool loaded) {
    if (!loaded || _eventsSubscribed) return;
    final events = asDeviceEventStreamRepository(_repository)?.deviceEvents();
    if (events == null) return;
    _eventsSubscribed = true;
    _eventsSub = events.listen(_onDeviceEvent, onError: (_) {});
  }

  /// Dispatches one stream frame.
  ///
  /// [ApiClient.events] yields `{'event': <name>, 'data': <decoded frame>}`,
  /// and the core bus wraps every payload in an envelope
  /// (`{id, event, data, timestamp}`), so the real name/payload may live one
  /// level deeper. Only `devices_state_updated` reacts: the canonical snapshot
  /// is silently reloaded, nothing else.
  void _onDeviceEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    final outer = event['data'];
    if (outer is! Map) return;
    var name = event['event'];
    final innerData = outer['data'];
    final innerName = outer['event'];
    if (innerData is Map && innerName is String) {
      name = innerName;
    }
    if (name != 'devices_state_updated') return;
    unawaited(loadDevices());
  }

  /// Bulk read-only sweep of backend device states followed by a canonical
  /// reload. Event-driven only (first successful load and user
  /// pull-to-refresh gestures), never a timer.
  ///
  /// Repositories without the sweep surface are a no-op. A failed sweep is
  /// silent (last known states stay as they were) and the inventory still
  /// reloads, so the gesture always refreshes something.
  Future<void> refreshStatesAndReload() async {
    final sweeper = asDeviceStateRefreshRepository(_repository);
    if (sweeper == null) return;
    if (_statesRefreshInFlight) return;
    _statesRefreshInFlight = true;
    try {
      try {
        await sweeper.refreshDeviceStates();
      } catch (_) {
        // Silent by design: states stay as-is on sweep failure.
      }
      // The flag stays held through the reload so the auto-sweep fired by
      // loadDevices coalesces instead of stacking a second sweep.
      await loadDevices();
    } finally {
      _statesRefreshInFlight = false;
    }
  }

  /// Busca dispositivos sin SnackBar (concern de UI); lanza el error para que
  /// la página decida el mensaje. Devuelve `false` si ya hay una búsqueda en
  /// curso (no-op).
  Future<bool> discover() async {
    if (_discovering) return false;
    _discovering = true;
    _notify();
    try {
      final previousLocals = _localOnlyDevices();
      _snapshot = await _repository.discover();
      _restoreLocalDevices(previousLocals);
      _clearStaleSelection();
      return true;
    } finally {
      _discovering = false;
      _notify();
    }
  }

  /// Limpia una selección que apunta a un dispositivo que ya no existe en el
  /// snapshot canónico (no-op cuando no hay selección o el dispositivo sigue
  /// presente). La notificación la cubre el bloque `finally` del llamador.
  void _clearStaleSelection() {
    final id = _selectedDeviceId;
    final snapshot = _snapshot;
    if (id == null || snapshot == null) return;
    for (final device in snapshot.devices) {
      if (device.id == id) return;
    }
    _selectedDeviceId = null;
  }

  /// Local-only devices (by id) in the current snapshot, with their latest
  /// local state (including power converges applied from a detail page).
  Map<String, PhysicalDevice> _localOnlyDevices() {
    final snapshot = _snapshot;
    if (snapshot == null || _localOnlyIds.isEmpty) return const {};
    final byId = {for (final device in snapshot.devices) device.id: device};
    return {
      for (final id in _localOnlyIds)
        if (byId.containsKey(id)) id: byId[id]!,
    };
  }

  /// Re-appends local-only devices missing from a freshly loaded snapshot.
  /// When the backend finally returns one of them, the backend version wins
  /// and the id leaves the local-only set.
  void _restoreLocalDevices(Map<String, PhysicalDevice> locals) {
    final snapshot = _snapshot;
    if (snapshot == null || locals.isEmpty) return;
    final freshIds = snapshot.devices.map((device) => device.id).toSet();
    final missing = <PhysicalDevice>[
      for (final entry in locals.entries)
        if (!freshIds.contains(entry.key)) entry.value,
    ];
    for (final id in locals.keys) {
      if (freshIds.contains(id)) _localOnlyIds.remove(id);
    }
    if (missing.isEmpty) return;
    _snapshot = DeviceInventorySnapshot(
      areas: snapshot.areas,
      devices: List.unmodifiable([...snapshot.devices, ...missing]),
      gateways: snapshot.gateways,
      lastDiscoveryLabel: snapshot.lastDiscoveryLabel,
    );
  }

  // ---- Dirty buffer for batched Save (Slice C) ----
  String? _pendingLocationId;
  bool? _pendingPower;
  int? _pendingBrightness;
  int? _pendingFanSpeed;
  double? _pendingTargetTemperature;
  String? _pendingClimateMode;
  int? _pendingPosition;
  int? _pendingColorTemperature;

  /// Device-level detail type chosen in the desktop detail pane (light /
  /// switch / fan / ...), not yet saved. [_pendingRole] is the matching
  /// backend semantic role when the type has one (null for outlet/climate,
  /// which stay local-only).
  String? _pendingType;
  String? _pendingRole;

  /// One-shot truthful notice for the last commit (see [consumeCommitNotice]).
  String? _commitNotice;

  String? get pendingLocationId => _pendingLocationId;
  String? get pendingLocation => _pendingLocationId;
  bool? get pendingPower => _pendingPower;
  int? get pendingBrightness => _pendingBrightness;
  int? get pendingFanSpeed => _pendingFanSpeed;
  double? get pendingTargetTemperature => _pendingTargetTemperature;
  String? get pendingClimateMode => _pendingClimateMode;
  int? get pendingPosition => _pendingPosition;
  int? get pendingColorTemperature => _pendingColorTemperature;
  String? get pendingType => _pendingType;
  bool get hasPendingChanges =>
      _pendingLocationId != null ||
      _pendingPower != null ||
      _pendingBrightness != null ||
      _pendingFanSpeed != null ||
      _pendingTargetTemperature != null ||
      _pendingClimateMode != null ||
      _pendingPosition != null ||
      _pendingColorTemperature != null ||
      _pendingType != null;

  void markPendingLocation(String? locationId) {
    _pendingLocationId = locationId;
    _notify();
  }

  /// Buffers a device-level type change; [role] is the backend semantic role
  /// (or null when the type has no contract role). Notifies so the detail
  /// controls react instantly, before saving.
  void markPendingType(String? type, String? role) {
    _pendingType = type;
    _pendingRole = role;
    _notify();
  }

  void markPendingPower(bool? power) {
    _pendingPower = power;
    _notify();
  }

  void markPendingBrightness(int? brightness) {
    _pendingBrightness = brightness;
    _notify();
  }

  void markPendingFanSpeed(int? speed) {
    _pendingFanSpeed = speed;
    _notify();
  }

  void markPendingTargetTemperature(double? temperature) {
    _pendingTargetTemperature = temperature;
    _notify();
  }

  void markPendingClimateMode(String? mode) {
    _pendingClimateMode = mode;
    _notify();
  }

  void markPendingPosition(int? position) {
    _pendingPosition = position;
    _notify();
  }

  void markPendingColorTemperature(int? colorTemperature) {
    _pendingColorTemperature = colorTemperature;
    _notify();
  }

  void markDirty({String? locationId, bool? power, int? brightness}) {
    var changed = false;
    if (locationId != null) {
      _pendingLocationId = locationId;
      changed = true;
    }
    if (power != null) {
      _pendingPower = power;
      changed = true;
    }
    if (brightness != null) {
      _pendingBrightness = brightness;
      changed = true;
    }
    if (changed) _notify();
  }

  void discardPendingChanges() {
    if (!hasPendingChanges) return;
    _pendingLocationId = null;
    _pendingPower = null;
    _pendingBrightness = null;
    _pendingFanSpeed = null;
    _pendingTargetTemperature = null;
    _pendingClimateMode = null;
    _pendingPosition = null;
    _pendingColorTemperature = null;
    _pendingType = null;
    _pendingRole = null;
    _notify();
  }

  /// Sequentially commits pending changes via repository, applying each
  /// canonical response via [applyCanonicalDevice]. Keeps dirty on failure.
  ///
  /// With a command-capable repository the capability-backed fields execute
  /// canonical actions (`set_brightness`, `set_speed`, `set_mode`,
  /// `set_power`); without one they keep the legacy local-only convergence.
  Future<PhysicalDevice> commitPendingChanges(String deviceId) async {
    if (!hasPendingChanges) {
      final current = snapshot?.devices.firstWhere(
        (d) => d.id == deviceId,
        orElse: () => throw StateError('Device not found: $deviceId'),
      );
      if (current != null) return current;
      throw StateError('No snapshot');
    }
    _commitNotice = null;
    PhysicalDevice? last;
    // Location is repository-backed on every repository implementation.
    if (_pendingLocationId != null) {
      final location = _pendingLocationId;
      final updated = await _repository.assignPhysicalArea(deviceId, location);
      applyCanonicalDevice(updated);
      last = updated;
      _pendingLocationId = null;
    }
    // Device-level type: persist the matching semantic role on the first
    // endpoint when the backend supports it. Types without a contract role
    // (outlet/climate) resolve locally with no repository call.
    if (_pendingRole != null) {
      final role = _pendingRole;
      final current = snapshot?.devices.firstWhere((d) => d.id == deviceId);
      final endpoint = current == null || current.endpoints.isEmpty
          ? null
          : current.endpoints.first;
      if (current != null &&
          endpoint != null &&
          _repository.supportsSemanticRole) {
        final updated = await _repository.assignEndpointSemanticRole(
          deviceId,
          endpoint.id,
          role,
        );
        applyCanonicalDevice(updated);
        last = updated;
      }
      _pendingType = null;
      _pendingRole = null;
    } else if (_pendingType != null) {
      _pendingType = null;
      _pendingRole = null;
    }
    final commands = asDeviceCommandRepository(_repository);
    if (commands == null) {
      // Legacy local convergence: power and demo display values are
      // mock-only fields with no repository setter, so they apply locally
      // instead of being sent to a backend.
      if (_pendingPower != null ||
          _pendingBrightness != null ||
          _pendingFanSpeed != null ||
          _pendingTargetTemperature != null ||
          _pendingClimateMode != null ||
          _pendingPosition != null ||
          _pendingColorTemperature != null) {
        var current = snapshot?.devices.firstWhere((d) => d.id == deviceId);
        if (current != null) {
          final power = _pendingPower;
          current = current.copyWith(
            powerOn: power ?? current.powerOn,
            online: power ?? current.online,
            health: power == null
                ? current.health
                : (power
                      ? DeviceHealthState.online
                      : DeviceHealthState.sleeping),
            brightness: _pendingBrightness ?? current.brightness,
            fanSpeed: _pendingFanSpeed ?? current.fanSpeed,
            targetTemperature:
                _pendingTargetTemperature ?? current.targetTemperature,
            climateMode: _pendingClimateMode ?? current.climateMode,
            position: _pendingPosition ?? current.position,
            colorTemperature:
                _pendingColorTemperature ?? current.colorTemperature,
          );
          applyCanonicalDevice(current);
          last = current;
        }
        _pendingPower = null;
        _pendingBrightness = null;
        _pendingFanSpeed = null;
        _pendingTargetTemperature = null;
        _pendingClimateMode = null;
        _pendingPosition = null;
        _pendingColorTemperature = null;
      }
    } else {
      final committed = await _commitPendingCapabilities(deviceId);
      if (committed != null) last = committed;
    }
    _notify();
    if (last != null) return last;
    // No location change: return current canonical device.
    final fallback = snapshot?.devices.firstWhere((d) => d.id == deviceId);
    if (fallback != null) return fallback;
    throw StateError('Device not found after commit: $deviceId');
  }

  /// Commands path of [commitPendingChanges]: every capability-backed field
  /// runs on the first writable endpoint of its capability through the shared
  /// [commitCapabilityFields] helper, sequentially and in the canonical order
  /// (brightness, speed, mode, position, color temperature). Each field is
  /// cleared only after its batch returned, so an [ApiException] mid-way keeps
  /// the fields that were not executed yet buffered and the already-executed
  /// ones merged. Power and target temperature stay controller-local: power
  /// uses the canonical `set_power` path and temperature has no backend action
  /// (documented contract gap) so it converges locally.
  ///
  /// Returns the last canonical device applied, if any.
  Future<PhysicalDevice?> _commitPendingCapabilities(String deviceId) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      throw StateError('No snapshot');
    }
    var current = snapshot.devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw StateError('Device not found: $deviceId'),
    );
    final commands = asDeviceCommandRepository(_repository);
    if (commands == null) {
      throw UnsupportedError(
        'El repositorio no soporta comandos de dispositivo.',
      );
    }
    PhysicalDevice? last;
    final executed = <String>[];

    Future<void> runBatch({
      int? brightness,
      int? fanSpeed,
      String? climateMode,
      int? position,
      int? colorTemperature,
    }) async {
      final result = await commitCapabilityFields(
        commands: commands,
        device: current,
        brightness: brightness,
        fanSpeed: fanSpeed,
        climateMode: climateMode,
        position: position,
        colorTemperature: colorTemperature,
        onOutcome: executed.add,
      );
      current = result.device;
      // Converge immediately so an ApiException on a later field keeps the
      // already-executed observations in the snapshot.
      applyCanonicalDevice(current);
      last = current;
    }

    final brightness = _pendingBrightness;
    if (brightness != null) {
      await runBatch(brightness: brightness);
      _pendingBrightness = null;
    }

    final fanSpeed = _pendingFanSpeed;
    if (fanSpeed != null) {
      await runBatch(fanSpeed: fanSpeed);
      _pendingFanSpeed = null;
    }

    final climateMode = _pendingClimateMode;
    if (climateMode != null) {
      await runBatch(climateMode: climateMode);
      _pendingClimateMode = null;
    }

    final position = _pendingPosition;
    if (position != null) {
      await runBatch(position: position);
      _pendingPosition = null;
    }

    final colorTemperature = _pendingColorTemperature;
    if (colorTemperature != null) {
      await runBatch(colorTemperature: colorTemperature);
      _pendingColorTemperature = null;
    }

    final power = _pendingPower;
    if (power != null) {
      final endpoint = _firstPowerEndpoint(current);
      if (endpoint != null) {
        final result = await setEndpointPower(deviceId, endpoint.id, power);
        executed.add(result.outcome);
        current = _deviceById(deviceId) ?? current;
        last = current;
      }
      _pendingPower = null;
    }

    // No canonical backend action exists for target temperature: it keeps
    // converging locally exactly as before (documented contract gap).
    final targetTemperature = _pendingTargetTemperature;
    if (targetTemperature != null) {
      final updated = current.copyWith(targetTemperature: targetTemperature);
      applyCanonicalDevice(updated);
      current = updated;
      last = updated;
    }
    _pendingTargetTemperature = null;

    _commitNotice = capabilityCommitNotice(executed);
    return last;
  }

  /// Truthful one-shot notice for the last commit. Returns
  /// 'Escritura deshabilitada en el modo actual' when every executed action
  /// answered `EXECUTION_DISABLED`, or 'Orden enviada — sin confirmación del
  /// dispositivo' when every executed action was `unconfirmed`; null
  /// otherwise (including mixed results). Cleared on read.
  String? consumeCommitNotice() {
    final notice = _commitNotice;
    _commitNotice = null;
    return notice;
  }

  PhysicalDevice? _deviceById(String deviceId) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    for (final device in snapshot.devices) {
      if (device.id == deviceId) return device;
    }
    return null;
  }

  DeviceEndpoint? _firstPowerEndpoint(PhysicalDevice device) {
    for (final endpoint in device.endpoints) {
      if (hasPowerCapability(endpoint)) return endpoint;
    }
    return null;
  }

  void selectDevice(String? id) {
    if (id == _selectedDeviceId) return;
    // Batched Save: discard pending when switching device.
    if (hasPendingChanges) {
      _pendingLocationId = null;
      _pendingPower = null;
      _pendingBrightness = null;
      _pendingFanSpeed = null;
      _pendingTargetTemperature = null;
      _pendingClimateMode = null;
      _pendingPosition = null;
      _pendingColorTemperature = null;
      _pendingType = null;
      _pendingRole = null;
    }
    _selectedDeviceId = id;
    _notify();
  }

  /// Replaces the canonical device with [device] by opaque ID in the shared
  /// snapshot, preserving the selection and list order. Unknown IDs are a
  /// no-op (never duplicated). No network fetch — the caller supplies the
  /// canonical DTO.
  ///
  /// Selection is a display concern and never gates convergence: any known
  /// device may converge, so a backend response resolving after the user moved
  /// the selection still lands in the shared state (F3-C race closure).
  void applyCanonicalDevice(PhysicalDevice device) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final index = snapshot.devices.indexWhere((d) => d.id == device.id);
    if (index < 0) return; // policy: unknown id -> no-op, deterministic
    final devices = List<PhysicalDevice>.of(snapshot.devices);
    devices[index] = device;
    _snapshot = DeviceInventorySnapshot(
      areas: snapshot.areas,
      devices: devices,
      gateways: snapshot.gateways,
      lastDiscoveryLabel: snapshot.lastDiscoveryLabel,
    );
    _notify();
  }

  /// Executes one canonical endpoint power action (`set_power`).
  ///
  /// When the backend parses a typed response with a confirmed observation,
  /// the observation is merged into the cached snapshot device endpoint so
  /// every surface converges. The typed [EndpointPowerResult] is returned
  /// as-is: success is never fabricated.
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  ) async {
    final commands = asDeviceCommandRepository(_repository);
    if (commands == null) {
      throw UnsupportedError(
        'El repositorio no soporta comandos de dispositivo.',
      );
    }
    final result = await commands.setEndpointPower(
      deviceId,
      endpointId,
      enabled,
    );
    if (result.responseParsed &&
        result.observedPower != null &&
        result.observedQuality != null) {
      _mergeEndpointObservation(deviceId, endpointId, result);
    }
    return result;
  }

  /// Device-level power: resolves the first endpoint with a power channel.
  /// Throws [UnsupportedError] when the device exposes none.
  Future<EndpointPowerResult> setDevicePower(
    String deviceId,
    bool enabled,
  ) async {
    final snapshot = _snapshot;
    PhysicalDevice? device;
    if (snapshot != null) {
      for (final candidate in snapshot.devices) {
        if (candidate.id == deviceId) {
          device = candidate;
          break;
        }
      }
    }
    DeviceEndpoint? endpoint;
    if (device != null) {
      endpoint = _firstPowerEndpoint(device);
    }
    if (endpoint == null) {
      throw UnsupportedError('El dispositivo no expone un canal de encendido.');
    }
    return setEndpointPower(deviceId, endpoint.id, enabled);
  }

  /// Executes `set_brightness` on [endpointId] with an int percent (0-100).
  Future<CapabilityActionResult> setBrightness(
    String deviceId,
    String endpointId,
    int percent,
  ) => _executeCapability(
    deviceId,
    endpointId,
    action: 'set_brightness',
    value: percent,
  );

  /// Executes `set_speed` on [endpointId] with an int percent (0-100). The
  /// UI's 3-level fan control converts through [speedLevelToPercent].
  Future<CapabilityActionResult> setSpeed(
    String deviceId,
    String endpointId,
    int percent,
  ) => _executeCapability(
    deviceId,
    endpointId,
    action: 'set_speed',
    value: percent,
  );

  /// Executes `set_mode` on [endpointId] with an enum string.
  Future<CapabilityActionResult> setMode(
    String deviceId,
    String endpointId,
    String mode,
  ) =>
      _executeCapability(deviceId, endpointId, action: 'set_mode', value: mode);

  /// Shared capability command path: requires the segregated command surface,
  /// executes one canonical action and merges the confirmed observation into
  /// the snapshot endpoint. The typed result is returned as-is.
  Future<CapabilityActionResult> _executeCapability(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  }) async {
    final commands = asDeviceCommandRepository(_repository);
    if (commands == null) {
      throw UnsupportedError(
        'El repositorio no soporta comandos de dispositivo.',
      );
    }
    final result = await commands.executeAction(
      deviceId,
      endpointId,
      action: action,
      value: value,
    );
    final capability = result.capability;
    final observedValue = result.observedValue;
    if (result.responseParsed &&
        capability != null &&
        observedValue != null &&
        result.observedQuality != null) {
      _mergeCapabilityObservation(
        deviceId,
        endpointId,
        capability,
        observedValue,
        result.observedQuality,
        result.observedAt,
      );
    }
    return result;
  }

  /// Merges one observed capability value into the cached snapshot endpoint.
  /// Unknown ids and endpoints are deterministic no-ops.
  void _mergeCapabilityObservation(
    String deviceId,
    String endpointId,
    String capability,
    Object value,
    String? quality,
    String? observedAt,
  ) {
    final device = _deviceById(deviceId);
    if (device == null) return;
    if (!device.endpoints.any((endpoint) => endpoint.id == endpointId)) return;
    final endpoints = device.endpoints
        .map(
          (endpoint) => endpoint.id == endpointId
              ? endpoint.copyWith(
                  observedCapabilities: Map.unmodifiable({
                    ...endpoint.observedCapabilities,
                    capability: EndpointCapabilityObservation(
                      value: value,
                      quality: quality,
                      observedAt: observedAt,
                    ),
                  }),
                )
              : endpoint,
        )
        .toList();
    applyCanonicalDevice(device.copyWith(endpoints: endpoints));
  }

  /// Merges a confirmed power observation into the cached snapshot endpoint.
  /// Unknown ids and unknown endpoints are deterministic no-ops.
  void _mergeEndpointObservation(
    String deviceId,
    String endpointId,
    EndpointPowerResult result,
  ) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    PhysicalDevice? device;
    for (final candidate in snapshot.devices) {
      if (candidate.id == deviceId) {
        device = candidate;
        break;
      }
    }
    if (device == null) return;
    if (!device.endpoints.any((endpoint) => endpoint.id == endpointId)) return;
    final endpoints = device.endpoints
        .map(
          (endpoint) => endpoint.id == endpointId
              ? endpoint.copyWith(
                  observedPower: result.observedPower,
                  observedQuality: result.observedQuality,
                  observedAt: result.observedAt,
                )
              : endpoint,
        )
        .toList();
    applyCanonicalDevice(device.copyWith(endpoints: endpoints));
  }

  /// Adds a locally-created device to the snapshot and notifies listeners.
  /// Used by the "Add device" dialog to make the button functional without
  /// requiring a backend round-trip.
  void addLocalDevice(PhysicalDevice device) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      _localOnlyIds.add(device.id);
      _snapshot = DeviceInventorySnapshot(
        areas: const [],
        devices: [device],
        gateways: const [],
        lastDiscoveryLabel: '',
      );
      _notify();
      return;
    }
    if (snapshot.devices.any((d) => d.id == device.id)) return;
    _localOnlyIds.add(device.id);
    final devices = List<PhysicalDevice>.of(snapshot.devices)..add(device);
    _snapshot = DeviceInventorySnapshot(
      areas: snapshot.areas,
      devices: List.unmodifiable(devices),
      gateways: snapshot.gateways,
      lastDiscoveryLabel: snapshot.lastDiscoveryLabel,
    );
    _notify();
  }

  /// Removes a locally-created device from the snapshot and clears the
  /// selection when it pointed at it. Used by "Eliminar dispositivo" on
  /// surfaces without a backend delete endpoint. Unknown IDs are a no-op.
  void removeLocalDevice(String deviceId) {
    final snapshot = _snapshot;
    _localOnlyIds.remove(deviceId);
    if (snapshot == null) return;
    if (!snapshot.devices.any((d) => d.id == deviceId)) return;
    if (_selectedDeviceId == deviceId) {
      _selectedDeviceId = null;
      _pendingLocationId = null;
      _pendingPower = null;
      _pendingBrightness = null;
    }
    final devices = snapshot.devices.where((d) => d.id != deviceId).toList();
    _snapshot = DeviceInventorySnapshot(
      areas: snapshot.areas,
      devices: List.unmodifiable(devices),
      gateways: snapshot.gateways,
      lastDiscoveryLabel: snapshot.lastDiscoveryLabel,
    );
    _notify();
  }

  Future<bool> loadAreas() async {
    _areasLoading = true;
    _areasError = null;
    _notify();
    try {
      _areas = await _repository.listAreas();
      _clearStaleAreaSelection();
      return true;
    } catch (error) {
      _areasError = error;
      return false;
    } finally {
      _areasLoading = false;
      _notify();
    }
  }

  /// Limpia una selección de área que apunta a un área que ya no existe en la
  /// lista canónica (no-op cuando no hay selección o el área sigue presente).
  /// La notificación la cubre el bloque `finally` del llamador (F3-C Fase 6).
  void _clearStaleAreaSelection() {
    final id = _selectedAreaId;
    final areas = _areas;
    if (id == null || areas == null) return;
    for (final area in areas) {
      if (area.id == id) return;
    }
    _selectedAreaId = null;
  }

  void selectArea(String? id) {
    if (id == _selectedAreaId) return;
    _selectedAreaId = id;
    _notify();
  }

  Future<void> createArea(String name, List<String> aliases) async {
    _areaMutating = true;
    _notify();
    try {
      await _repository.createArea(name, aliases: aliases);
      await loadAreas();
    } finally {
      _areaMutating = false;
      _notify();
    }
  }

  Future<void> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    _areaMutating = true;
    _notify();
    try {
      await _repository.updateArea(areaId, name: name, aliases: aliases);
      await loadAreas();
    } finally {
      _areaMutating = false;
      _notify();
    }
  }

  Future<void> deleteArea(String areaId) async {
    _areaMutating = true;
    _notify();
    try {
      await _repository.deleteArea(areaId);
      await loadAreas();
    } finally {
      _areaMutating = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_eventsSub?.cancel());
    _eventsSub = null;
    super.dispose();
  }
}
