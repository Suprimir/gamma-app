import 'package:flutter/foundation.dart';

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

  DeviceInventorySnapshot? _snapshot;
  Object? _deviceError;
  bool _devicesLoading = false;
  bool _discovering = false;
  String? _selectedDeviceId;

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
    try {
      final previousLocals = _localOnlyDevices();
      _snapshot = await _repository.load();
      _restoreLocalDevices(previousLocals);
      _clearStaleSelection();
    } catch (error) {
      _deviceError = error;
    } finally {
      _devicesLoading = false;
      _notify();
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

  /// Device-level detail type chosen in the desktop detail pane (light /
  /// switch / fan / ...), not yet saved. [_pendingRole] is the matching
  /// backend semantic role when the type has one (null for outlet/climate,
  /// which stay local-only).
  String? _pendingType;
  String? _pendingRole;

  String? get pendingLocationId => _pendingLocationId;
  String? get pendingLocation => _pendingLocationId;
  bool? get pendingPower => _pendingPower;
  int? get pendingBrightness => _pendingBrightness;
  int? get pendingFanSpeed => _pendingFanSpeed;
  double? get pendingTargetTemperature => _pendingTargetTemperature;
  String? get pendingClimateMode => _pendingClimateMode;
  String? get pendingType => _pendingType;
  bool get hasPendingChanges =>
      _pendingLocationId != null ||
      _pendingPower != null ||
      _pendingBrightness != null ||
      _pendingFanSpeed != null ||
      _pendingTargetTemperature != null ||
      _pendingClimateMode != null ||
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
    _pendingType = null;
    _pendingRole = null;
    _notify();
  }

  /// Sequentially commits pending changes via repository, applying each
  /// canonical response via [applyCanonicalDevice]. Keeps dirty on failure.
  Future<PhysicalDevice> commitPendingChanges(String deviceId) async {
    if (!hasPendingChanges) {
      final current = snapshot?.devices.firstWhere(
        (d) => d.id == deviceId,
        orElse: () => throw StateError('Device not found: $deviceId'),
      );
      if (current != null) return current;
      throw StateError('No snapshot');
    }
    PhysicalDevice? last;
    // Location is the only repository-backed field currently; power/brightness
    // are buffered locally until contract extends (disabled+Tooltip in UI).
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
    // Power and demo display values converge locally (mock-only fields with
    // no repository setter): they buffer until Guardar cambios instead of
    // applying instantly.
    if (_pendingPower != null ||
        _pendingBrightness != null ||
        _pendingFanSpeed != null ||
        _pendingTargetTemperature != null ||
        _pendingClimateMode != null) {
      var current = snapshot?.devices.firstWhere((d) => d.id == deviceId);
      if (current != null) {
        final power = _pendingPower;
        current = current.copyWith(
          powerOn: power ?? current.powerOn,
          online: power ?? current.online,
          health: power == null
              ? current.health
              : (power ? DeviceHealthState.online : DeviceHealthState.sleeping),
          brightness: _pendingBrightness ?? current.brightness,
          fanSpeed: _pendingFanSpeed ?? current.fanSpeed,
          targetTemperature:
              _pendingTargetTemperature ?? current.targetTemperature,
          climateMode: _pendingClimateMode ?? current.climateMode,
        );
        applyCanonicalDevice(current);
        last = current;
      }
      _pendingPower = null;
      _pendingBrightness = null;
      _pendingFanSpeed = null;
      _pendingTargetTemperature = null;
      _pendingClimateMode = null;
    }
    _notify();
    if (last != null) return last;
    // No location change: return current canonical device.
    final fallback = snapshot?.devices.firstWhere((d) => d.id == deviceId);
    if (fallback != null) return fallback;
    throw StateError('Device not found after commit: $deviceId');
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
      for (final candidate in device.endpoints) {
        if (hasPowerCapability(candidate)) {
          endpoint = candidate;
          break;
        }
      }
    }
    if (endpoint == null) {
      throw UnsupportedError('El dispositivo no expone un canal de encendido.');
    }
    return setEndpointPower(deviceId, endpoint.id, enabled);
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
    super.dispose();
  }
}
