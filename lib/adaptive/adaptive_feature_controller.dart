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

  DeviceInventorySnapshot? _snapshot;
  Object? _deviceError;
  bool _devicesLoading = false;
  bool _discovering = false;
  String? _selectedDeviceId;

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
      _snapshot = await _repository.load();
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
      _snapshot = await _repository.discover();
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

  void selectDevice(String? id) {
    if (id == _selectedDeviceId) return;
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
