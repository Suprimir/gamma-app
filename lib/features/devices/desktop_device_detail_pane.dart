import 'dart:async';

import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../data/device_inventory.dart';
import '../../ui/app_colors.dart';
import '../../ui/device_status.dart';
import '../routines/related_routines.dart';
import '../routines/routines_page.dart';

/// Desktop detail pane: header with big kind icon + power switch, section
/// cards (Ubicación / Controles / Rutinas relacionadas) and a right rail with
/// technical info plus connection actions.
///
/// The "Tipo" selector inside Controles is device-level and reactive: type
/// specific controls below it rebuild instantly when the user picks another
/// type (e.g. a switch misdetected as generic that is really a fan).
/// Brightness, fan speed, climate mode, position and color temperature read
/// the canonical confirmed observations when present and buffer the user's
/// value until Guardar cambios, which executes the canonical capability
/// actions through the shared commit helper. Demo-only values remain the last
/// resort for mock/fake repositories without observations.
class DesktopDeviceDetailPane extends StatefulWidget {
  const DesktopDeviceDetailPane({
    super.key,
    required this.device,
    required this.areas,
    required this.controller,
    this.gateways = const [],
    this.api,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final AdaptiveFeatureController controller;
  final List<GatewayInfo> gateways;

  /// Optional API client used only to open the Rutinas screen. When null the
  /// "Crear rutina" button degrades to an explanatory message.
  final ApiClient? api;

  @override
  State<DesktopDeviceDetailPane> createState() =>
      _DesktopDeviceDetailPaneState();
}

/// Device-level detail types driving the reactive controls section. Fan and
/// climate have no [DeviceKind] counterpart: they are manual refinements over
/// a generically detected device.
const _typeLight = 'light';
const _typeOutlet = 'outlet';
const _typeSwitch = 'switch';
const _typeBlinds = 'blinds';
const _typeFan = 'fan';
const _typeClimate = 'climate';
const _typeSensor = 'sensor';

const _detailTypes = <String>[
  _typeLight,
  _typeOutlet,
  _typeSwitch,
  _typeBlinds,
  _typeFan,
  _typeClimate,
  _typeSensor,
];

class _DetailTypeMeta {
  const _DetailTypeMeta(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

_DetailTypeMeta _metaFor(String type) => switch (type) {
  _typeLight => const _DetailTypeMeta(
    'Luz',
    Icons.lightbulb_outline,
    AppColors.kindLight,
  ),
  _typeOutlet => const _DetailTypeMeta(
    'Enchufe',
    Icons.power_outlined,
    AppColors.kindBlinds,
  ),
  _typeBlinds => const _DetailTypeMeta(
    'Persiana',
    Icons.blinds_closed,
    AppColors.kindBlinds,
  ),
  _typeFan => const _DetailTypeMeta('Ventilador', Icons.air, AppColors.kindFan),
  _typeClimate => const _DetailTypeMeta(
    'Clima',
    Icons.ac_unit,
    AppColors.kindBlinds,
  ),
  _typeSensor => const _DetailTypeMeta(
    'Sensor',
    Icons.sensors_outlined,
    AppColors.kindSensorGrey,
  ),
  _ => const _DetailTypeMeta(
    'Interruptor',
    Icons.toggle_on_outlined,
    AppColors.kindBlinds,
  ),
};

/// Initial detail type: explicit semantic role wins, then the backend device
/// class, then the device kind. Unknown/gateway kinds fall back to the
/// generic switch (the classic "Interruptor genérico" misdetection).
String _initialType(PhysicalDevice device) {
  final role = device.endpoints
      .map((e) => e.semanticRole?.toLowerCase())
      .whereType<String>()
      .firstOrNull;
  final fromRole = switch (role) {
    'light' => _typeLight,
    'switch' => _typeSwitch,
    'fan' || 'extractor' => _typeFan,
    'sensor' => _typeSensor,
    'outlet' => _typeOutlet,
    'climate' => _typeClimate,
    'cover' || 'blind' || 'blinds' || 'shutter' || 'curtain' => _typeBlinds,
    _ => null,
  };
  if (fromRole != null) return fromRole;
  final fromClass = switch (device.deviceClass.toLowerCase()) {
    'light' => _typeLight,
    'switch' || 'relay' => _typeSwitch,
    'outlet' => _typeOutlet,
    'fan' => _typeFan,
    'climate' || 'ac' || 'thermostat' => _typeClimate,
    'sensor' => _typeSensor,
    'cover' || 'blind' || 'blinds' || 'shutter' || 'curtain' => _typeBlinds,
    _ => null,
  };
  if (fromClass != null && fromClass != 'unknown') return fromClass;
  // Position capability without role/class metadata: a generically detected
  // blind must still resolve to its real control.
  if (device.endpoints.any(
    (endpoint) =>
        endpoint.capabilities.contains('POSITION') ||
        endpoint.capabilityDetails.containsKey('POSITION'),
  )) {
    return _typeBlinds;
  }
  return switch (device.kind) {
    DeviceKind.light => _typeLight,
    DeviceKind.outlet => _typeOutlet,
    DeviceKind.sensor => _typeSensor,
    _ => _typeSwitch,
  };
}

/// Backend semantic role matching a detail type, when one exists. Outlet,
/// blinds and climate have no role in the current contract, so they stay
/// local-only.
String? _roleForType(String type) => switch (type) {
  _typeLight => 'light',
  _typeSwitch => 'switch',
  _typeFan => 'fan',
  _typeSensor => 'sensor',
  _ => null,
};

class _DesktopDeviceDetailPaneState extends State<DesktopDeviceDetailPane> {
  bool _saving = false;
  bool _testingConnection = false;
  bool _deleting = false;
  bool _savingEndpoint = false;

  /// Endpoint ids with an in-flight power command: only that channel's switch
  /// is disabled while the command is running.
  final Set<String> _powerBusyEndpoints = {};
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  /// Related routines from `GET /api/v1/routines`, filtered by canonical
  /// action `device_id`. Null = pending ('—'); failed = 'Sin datos'. With a
  /// null [DesktopDeviceDetailPane.api] (test hosts) the legacy '0 rutinas'
  /// rendering is preserved instead of showing an unknown state.
  int? _relatedRoutineCount;
  bool _relatedRoutinesFailed = false;
  String? _relatedRoutinesDeviceId;

  @override
  void initState() {
    super.initState();
    _loadRelatedRoutines();
  }

  @override
  void didUpdateWidget(covariant DesktopDeviceDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id ||
        !identical(oldWidget.api, widget.api)) {
      _loadRelatedRoutines();
    }
  }

  void _loadRelatedRoutines() {
    final api = widget.api;
    final deviceId = widget.device.id;
    if (api == null) {
      _relatedRoutinesDeviceId = null;
      _relatedRoutineCount = 0;
      _relatedRoutinesFailed = false;
      return;
    }
    _relatedRoutinesDeviceId = deviceId;
    _relatedRoutineCount = null;
    _relatedRoutinesFailed = false;
    _fetchRelatedRoutines(api, deviceId);
  }

  Future<void> _fetchRelatedRoutines(ApiClient api, String deviceId) async {
    try {
      final routines = await api.routines().timeout(
        const Duration(milliseconds: 900),
      );
      if (!mounted || _relatedRoutinesDeviceId != deviceId) return;
      setState(() {
        _relatedRoutineCount = countRelatedRoutines(routines, deviceId);
        _relatedRoutinesFailed = false;
      });
    } catch (_) {
      if (!mounted || _relatedRoutinesDeviceId != deviceId) return;
      setState(() {
        _relatedRoutineCount = null;
        _relatedRoutinesFailed = true;
      });
    }
  }

  /// Label for the related-routines card. '—' while unknown, 'Sin datos' when
  /// the routines fetch failed; a resolved count is always real.
  String get _relatedRoutinesLabel {
    if (_relatedRoutinesFailed) return 'Sin datos';
    final count = _relatedRoutineCount;
    if (count == null) return '—';
    return count == 1 ? '1 rutina' : '$count rutinas';
  }

  PhysicalDevice get _canonical {
    final selected = widget.controller.selectedDevice;
    return selected != null && selected.id == widget.device.id
        ? selected
        : widget.device;
  }

  /// Effective detail type: buffered user choice wins, otherwise the derived
  /// initial type. The controls below react instantly through the controller
  /// notification, before saving.
  String _effectiveType(PhysicalDevice device) =>
      widget.controller.pendingType ?? _initialType(device);

  /// Whether the repository exposes the canonical command surface. Plain
  /// fakes without commands keep the legacy local behavior untouched.
  bool get _commandsAvailable => widget.controller.supportsEndpointCommands;

  /// Power display for the header switch: a buffered pending value wins; with
  /// command support the honest device state decides (unknown is never shown
  /// as a confident off); without command support the legacy
  /// `pendingPower ?? powerOn ?? online` fallback stays.
  PowerDisplayState _effectivePowerState(PhysicalDevice device) {
    final pending = widget.controller.pendingPower;
    if (!_commandsAvailable) {
      final legacyOn = pending ?? device.powerOn ?? device.online;
      return legacyOn ? PowerDisplayState.on : PowerDisplayState.off;
    }
    if (pending != null) {
      return pending ? PowerDisplayState.on : PowerDisplayState.off;
    }
    return devicePowerDisplayState(device);
  }

  /// Confirmed numeric observation for [capability] on the first writable
  /// endpoint; null when unknown (never a fabricated value).
  num? _confirmedCapabilityNumber(PhysicalDevice device, String capability) {
    final endpoint = firstEndpointWithCapability(device, capability);
    if (endpoint == null) return null;
    final value = confirmedCapabilityValue(endpoint, capability);
    return value is num ? value : null;
  }

  double _effectiveBrightness(PhysicalDevice device) {
    final pending = widget.controller.pendingBrightness;
    if (pending != null) return pending.toDouble().clamp(0, 100);
    final observed = _confirmedCapabilityNumber(device, 'BRIGHTNESS');
    if (observed != null) return observed.toDouble().clamp(0, 100);
    return (device.brightness ?? 80).toDouble();
  }

  int _effectiveFanSpeed(PhysicalDevice device) {
    final pending = widget.controller.pendingFanSpeed;
    if (pending != null) return pending;
    final percent = _confirmedCapabilityNumber(device, 'SPEED');
    if (percent != null) return percentToSpeedLevel(percent);
    return device.fanSpeed ?? 2;
  }

  double _effectiveTargetTemperature(PhysicalDevice device) =>
      widget.controller.pendingTargetTemperature ??
      device.targetTemperature ??
      22;

  String _effectiveClimateMode(PhysicalDevice device) {
    final pending = widget.controller.pendingClimateMode;
    if (pending != null) return pending;
    final endpoint = firstEndpointWithCapability(device, 'MODE');
    final observed = endpoint == null
        ? null
        : confirmedCapabilityValue(endpoint, 'MODE');
    if (observed is String && observed.isNotEmpty) return observed;
    return device.climateMode ?? 'cold';
  }

  int _effectivePosition(PhysicalDevice device) {
    final pending = widget.controller.pendingPosition;
    if (pending != null) return pending.clamp(0, 100);
    final observed = _confirmedCapabilityNumber(device, 'POSITION');
    if (observed != null) return observed.round().clamp(0, 100);
    return (device.position ?? 0).clamp(0, 100);
  }

  int _effectiveColorTemperature(PhysicalDevice device) {
    final pending = widget.controller.pendingColorTemperature;
    if (pending != null) return pending.clamp(0, 100);
    final observed = _confirmedCapabilityNumber(device, 'COLOR_TEMPERATURE');
    if (observed != null) return observed.round().clamp(0, 100);
    return (device.colorTemperature ?? 50).clamp(0, 100);
  }

  /// Whether the resolved COLOR_TEMPERATURE endpoint carries descriptor
  /// metadata: the color-temperature slider only renders for
  /// descriptor-backed lights (never for type-driven mocks).
  bool _showColorTemperature(PhysicalDevice device) {
    final endpoint = firstEndpointWithCapability(device, 'COLOR_TEMPERATURE');
    return endpoint?.capabilityDetails.containsKey('COLOR_TEMPERATURE') ??
        false;
  }

  bool _isSensorFor(PhysicalDevice device) =>
      _effectiveType(device) == _typeSensor || device.isGateway;

  /// Power switch applies instantly (it is a direct action, not a form
  /// field): the list row and header dot converge at once. Any buffered
  /// power value is cleared so a later Guardar does not re-apply it.
  ///
  /// With command support the canonical backend is called and success is
  /// never fabricated; the legacy local `online/health` mutation is the
  /// fallback for repositories without commands.
  Future<void> _setPower(bool value) async {
    if (!_commandsAvailable) {
      widget.controller.applyCanonicalDevice(
        _canonical.copyWith(
          powerOn: value,
          online: value,
          health: value ? DeviceHealthState.online : DeviceHealthState.sleeping,
        ),
      );
      widget.controller.markPendingPower(null);
      return;
    }
    widget.controller.markPendingPower(null);
    try {
      final result = await widget.controller.setDevicePower(
        _canonical.id,
        value,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(powerOutcomeMessage(result, requested: value))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(powerFailureMessage(error))));
    }
  }

  void _setType(String? type) {
    if (type == null) return;
    // Buffered only: controls below react instantly via the controller
    // notification; persistence happens on Guardar cambios.
    widget.controller.markPendingType(type, _roleForType(type));
  }

  Future<void> _saveAll() async {
    if (_saving || !widget.controller.hasPendingChanges) return;
    setState(() => _saving = true);
    try {
      await widget.controller.commitPendingChanges(_canonical.id);
      final notice = widget.controller.consumeCommitNotice();
      if (!mounted) return;
      if (notice != null) {
        // Truthful notice instead of the success toast: the command was not
        // confirmed (writes disabled / unparsed response).
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notice)));
        return;
      }
      _showSavedToast();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Dark auto-dismissing confirmation pill (desktop structure): ✓ +
  /// message + X dismiss, gone after 3s. Failure keeps the dirty buffer
  /// and surfaces a SnackBar instead (see [_saveAll]).
  void _showSavedToast() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: 24,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              key: const Key('detail-toast-pump'),
              color: AppColors.toastDark,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '✓',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Cambios guardados',
                    style: TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Cerrar',
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _dismissSavedToast,
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      _dismissSavedToast();
    });
  }

  void _dismissSavedToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    _toastEntry?.remove();
    _toastEntry = null;
  }

  /// Wall parity: per-channel area persists immediately through the shared
  /// repository and converges into the list + detail at once.
  Future<void> _setEndpointArea(DeviceEndpoint endpoint, String? areaId) async {
    if (_savingEndpoint) return;
    setState(() => _savingEndpoint = true);
    try {
      final updated = await widget.controller.repository.assignEndpointArea(
        _canonical.id,
        endpoint.id,
        areaId,
      );
      widget.controller.applyCanonicalDevice(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingEndpoint = false);
    }
  }

  /// Per-channel power command: calls the canonical `set_power` through the
  /// controller, which merges a confirmed observation into the shared
  /// snapshot (the pane rebuilds from it via [ListenableBuilder]). Only the
  /// targeted channel's switch is disabled while the command is in flight.
  Future<void> _setEndpointPower(DeviceEndpoint endpoint, bool value) async {
    if (_powerBusyEndpoints.contains(endpoint.id)) return;
    if (!_commandsAvailable) return;
    setState(() => _powerBusyEndpoints.add(endpoint.id));
    try {
      final result = await widget.controller.setEndpointPower(
        _canonical.id,
        endpoint.id,
        value,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(powerOutcomeMessage(result, requested: value))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(powerFailureMessage(error))));
    } finally {
      if (mounted) setState(() => _powerBusyEndpoints.remove(endpoint.id));
    }
  }

  /// Wall parity: per-channel semantic role persists immediately when the
  /// repository supports it.
  Future<void> _setEndpointRole(DeviceEndpoint endpoint, String? role) async {
    if (_savingEndpoint) return;
    setState(() => _savingEndpoint = true);
    try {
      final updated = await widget.controller.repository
          .assignEndpointSemanticRole(_canonical.id, endpoint.id, role);
      widget.controller.applyCanonicalDevice(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingEndpoint = false);
    }
  }

  /// Shows [message] when the host provides a Scaffold. Bare hosts without a
  /// Scaffold (e.g. pane-level test harnesses) skip presentation instead of
  /// breaking the mutation flow.
  void _showSnack(String message) {
    if (Scaffold.maybeOf(context) == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Wall parity: per-channel rename with explicit reset (null clears the
  /// custom name back to the provider display name).
  Future<void> _renameEndpoint(DeviceEndpoint endpoint) async {
    if (_savingEndpoint) return;
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _DetailRenameDialog(
        initialName: endpoint.userName ?? endpoint.displayName,
        canReset: endpoint.userName != null,
      ),
    );
    if (result == null || !mounted) return;
    // Empty string is the reset sentinel from the dialog.
    final userName = result.isEmpty ? null : result;
    if (userName != null && userName.trim().isEmpty) return;
    setState(() => _savingEndpoint = true);
    try {
      final updated = await widget.controller.repository.renameEndpoint(
        _canonical.id,
        endpoint.id,
        userName,
      );
      widget.controller.applyCanonicalDevice(updated);
      if (!mounted) return;
      _showSnack('Nombre actualizado');
    } catch (e) {
      // Honest failure: the previous canonical name stays in place and the
      // backend error is surfaced instead of a fake success.
      if (!mounted) return;
      _showSnack(deviceMutationErrorMessage(e));
    } finally {
      if (mounted) setState(() => _savingEndpoint = false);
    }
  }

  Future<void> _renameDevice() async {
    final device = _canonical;
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DetailRenameDialog(initialName: device.userName ?? device.name),
    );
    if (result == null) return;
    final newName = result.trim();
    if (newName.isEmpty) return;
    try {
      final updated = await widget.controller.repository.renameDevice(
        device.id,
        newName,
      );
      widget.controller.applyCanonicalDevice(updated);
      if (!mounted) return;
      _showSnack('Nombre actualizado');
    } catch (e) {
      // Honest failure: no local rename is applied and no success is shown.
      if (!mounted) return;
      _showSnack(deviceMutationErrorMessage(e));
    }
  }

  Future<void> _testConnection() async {
    if (_testingConnection) return;
    setState(() => _testingConnection = true);
    try {
      final result = await identifyDeviceWithFallback(
        widget.controller.repository,
        _canonical.id,
      );
      if (!mounted) return;
      if (!result.supported) {
        _showSnack(identifyUnsupportedMessage(result));
        return;
      }
      _showSnack('Conexión correcta con el dispositivo.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(deviceMutationErrorMessage(e));
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _deleteDevice() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar dispositivo'),
        content: Text(
          '¿Eliminar "${_canonical.userName ?? _canonical.name}" de la lista? '
          'Esta acción solo lo quita de la vista local.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    // La animación se lanza antes de eliminar: el panel se desmonta al
    // quitar la selección y su context dejaría de ser válido.
    unawaited(
      showDesktopSuccessSplash(
        context,
        message: 'Dispositivo eliminado correctamente',
      ),
    );
    widget.controller.removeLocalDevice(_canonical.id);
    if (!mounted) return;
    setState(() => _deleting = false);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  void _openRoutines() {
    final api = widget.api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las rutinas no están disponibles en esta vista.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinesPage(api: api, showBackButton: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final device = _canonical;
        final areas = widget.areas;
        final displayName = device.userName ?? device.name;
        final areaName =
            areas
                .where((a) => a.id == device.physicalAreaId)
                .map((a) => a.name)
                .firstOrNull ??
            (device.physicalAreaId ?? 'Sin área');
        final meta = _metaFor(_effectiveType(device));
        final healthColor = healthToColor(device.health);
        // Wall parity in the detail header: plain-language availability
        // ('En línea · Cocina') instead of the power vocabulary used in rows.
        final healthLabel = _headerHealthLabel(device.health);

        GatewayInfo? gateway;
        for (final g in widget.gateways) {
          if (g.id == device.gatewayId) {
            gateway = g;
            break;
          }
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                displayName: displayName,
                areaName: areaName,
                meta: meta,
                healthColor: healthColor,
                healthLabel: healthLabel,
                sensorValue: device.sensorValue,
                isSensor: _isSensorFor(device),
                powerState: _effectivePowerState(device),
                onPowerChanged: _setPower,
                onRename: _renameDevice,
                pendingKey: device.pendingKey == true,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          KeyedSubtree(
                            key: const Key('physical-area-dropdown'),
                            child: _SectionCard(
                              icon: Icons.location_on_outlined,
                              title: 'Ubicación física',
                              child: _LocationBody(
                                value:
                                    widget.controller.pendingLocationId ??
                                    device.physicalAreaId,
                                areas: areas,
                                onChanged:
                                    widget.controller.markPendingLocation,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SectionCard(
                            icon: Icons.tune_outlined,
                            title: 'Controles del dispositivo',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Wall parity: per-channel reality (each canal
                                // controls its own area/role/name) persists
                                // immediately through the shared repository.
                                _ChannelEditors(
                                  device: device,
                                  areas: areas,
                                  supportsRoles: widget
                                      .controller
                                      .repository
                                      .supportsSemanticRole,
                                  canCommandPower: _commandsAvailable,
                                  powerBusyEndpointIds: _powerBusyEndpoints,
                                  onAreaChanged: _setEndpointArea,
                                  onRoleChanged: _setEndpointRole,
                                  onPowerChanged: _setEndpointPower,
                                  onRename: _renameEndpoint,
                                ),
                                const SizedBox(height: 16),
                                _ControlsBody(
                                  device: device,
                                  areas: areas,
                                  type: _effectiveType(device),
                                  brightness: _effectiveBrightness(device),
                                  fanSpeed: _effectiveFanSpeed(device),
                                  targetTemperature:
                                      _effectiveTargetTemperature(device),
                                  climateMode: _effectiveClimateMode(device),
                                  position: _effectivePosition(device),
                                  colorTemperature: _effectiveColorTemperature(
                                    device,
                                  ),
                                  showColorTemperature: _showColorTemperature(
                                    device,
                                  ),
                                  commandsAvailable: _commandsAvailable,
                                  onTypeChanged: _setType,
                                  onBrightnessChanged: (v) => widget.controller
                                      .markPendingBrightness(v.round()),
                                  onFanSpeedChanged:
                                      widget.controller.markPendingFanSpeed,
                                  onTemperatureChanged: widget
                                      .controller
                                      .markPendingTargetTemperature,
                                  onClimateModeChanged:
                                      widget.controller.markPendingClimateMode,
                                  onPositionChanged: (v) => widget.controller
                                      .markPendingPosition(v.round()),
                                  onColorTemperatureChanged: (v) => widget
                                      .controller
                                      .markPendingColorTemperature(v.round()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SectionCard(
                            icon: Icons.auto_awesome_outlined,
                            title: 'Rutinas relacionadas',
                            trailing: Text(
                              _relatedRoutinesLabel,
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 12.5,
                              ),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _openRoutines,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gammaIndigoLight,
                                  foregroundColor: AppColors.gammaIndigo,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                child: const Text(
                                  '+ Crear rutina con este dispositivo',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 260,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          // Wall parity: technical metadata collapsed by
                          // default so raw IDs never leak into the primary
                          // view; desktop structure keeps the right rail.
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                4,
                                0,
                                4,
                                8,
                              ),
                              title: const Text(
                                'Información técnica',
                                style: TextStyle(
                                  color: AppColors.textDim,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              children: [
                                _TechRow(
                                  label: 'Última conexión',
                                  value: device.lastSeenLabel ?? 'Sin datos',
                                ),
                                _TechRow(
                                  label: 'Detectado como',
                                  value: _detectedAsLabel(device),
                                ),
                                _TechRow(label: 'ID', value: device.id),
                                _TechRow(label: 'Modelo', value: device.model),
                                if (device.manufacturer != null)
                                  _TechRow(
                                    label: 'Fabricante',
                                    value: device.manufacturer!,
                                  ),
                                if (gateway != null)
                                  _TechRow(
                                    label: 'Gateway',
                                    value: gateway.name,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _testingConnection
                                  ? null
                                  : _testConnection,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.gammaIndigo,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              child: _testingConnection
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Probar conexión',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _deleting ? null : _deleteDevice,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.errorRed.withValues(
                                  alpha: 0.12,
                                ),
                                foregroundColor: AppColors.errorRed,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              child: const Text(
                                'Eliminar dispositivo',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: Builder(
                              builder: (context) {
                                final canSave =
                                    widget.controller.hasPendingChanges &&
                                    !_saving;
                                return ElevatedButton(
                                  onPressed: canSave ? _saveAll : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.gammaIndigo,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: AppColors
                                        .gammaIndigo
                                        .withValues(alpha: 0.4),
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Guardar cambios',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _detectedAsLabel(PhysicalDevice device) {
  final providerRole = device.endpoints
      .map((e) => e.providerSemanticRole)
      .whereType<String>()
      .firstOrNull;
  if (providerRole != null) {
    return _metaFor(switch (providerRole.toLowerCase()) {
      'light' => _typeLight,
      'switch' => _typeSwitch,
      'fan' || 'extractor' => _typeFan,
      'sensor' => _typeSensor,
      'outlet' => _typeOutlet,
      'climate' => _typeClimate,
      _ => _typeSwitch,
    }).label;
  }
  return switch (device.kind) {
    DeviceKind.light => 'Luz',
    DeviceKind.outlet => 'Enchufe',
    DeviceKind.sensor => 'Sensor',
    DeviceKind.gateway => 'Gateway',
    DeviceKind.switchController => 'Interruptor genérico',
    DeviceKind.unknown => 'Dispositivo',
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.displayName,
    required this.areaName,
    required this.meta,
    required this.healthColor,
    required this.healthLabel,
    required this.sensorValue,
    required this.isSensor,
    required this.powerState,
    required this.onPowerChanged,
    required this.onRename,
    required this.pendingKey,
  });

  final String displayName;
  final String areaName;
  final _DetailTypeMeta meta;
  final Color healthColor;
  final String healthLabel;
  final String? sensorValue;
  final bool isSensor;
  final PowerDisplayState powerState;
  final ValueChanged<bool> onPowerChanged;
  final VoidCallback onRename;

  /// Whether the provider still owes credentials (`pending_key == true`):
  /// shows the subtle 'Sin credenciales' chip in the header.
  final bool pendingKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(meta.icon, size: 28, color: meta.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cambiar nombre',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: healthColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$healthLabel ● $areaName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (pendingKey) ...[
                const SizedBox(height: 4),
                const PendingCredentialsBadge(),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (isSensor)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              sensorValue ?? 'Sin datos recientes',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else ...[
          if (powerState == PowerDisplayState.unknown) ...[
            const Text(
              'Sin datos',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            const SizedBox(width: 8),
          ],
          Transform.scale(
            scale: 1.2,
            child: Switch(
              value: powerState == PowerDisplayState.on,
              activeTrackColor: AppColors.gammaIndigo,
              onChanged: onPowerChanged,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.accentStrong),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (trailing case final Widget t) t,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LocationBody extends StatelessWidget {
  const _LocationBody({
    required this.value,
    required this.areas,
    required this.onChanged,
  });

  final String? value;
  final List<HomeArea> areas;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = areas.any((a) => a.id == value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Habitación',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          key: const Key('desktop-location-dropdown'),
          value: effectiveValue,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            for (final area in areas)
              DropdownMenuItem<String?>(
                value: area.id,
                child: Text(area.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Wall parity: per-channel reality inside the desktop Controles card.
///
/// Each canal renders its display name, its real function ('Luz regulable',
/// 'Sensor de movimiento', …), a 'Tipo' role selector and a 'Controla' area
/// selector — both keyed per endpoint so tests and assistive tech can target
/// them. Mutations persist immediately through the shared repository (same
/// contract as the wall endpoint editor); the device-level dirty buffer below
/// (Tipo/sliders/Guardar) is untouched.
class _ChannelEditors extends StatelessWidget {
  const _ChannelEditors({
    required this.device,
    required this.areas,
    required this.supportsRoles,
    required this.canCommandPower,
    required this.powerBusyEndpointIds,
    required this.onAreaChanged,
    required this.onRoleChanged,
    required this.onPowerChanged,
    required this.onRename,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final bool supportsRoles;

  /// Whether the repository exposes canonical commands: without them no
  /// per-channel power switch is offered.
  final bool canCommandPower;

  /// Endpoint ids whose power command is currently in flight.
  final Set<String> powerBusyEndpointIds;
  final void Function(DeviceEndpoint endpoint, String? areaId) onAreaChanged;
  final void Function(DeviceEndpoint endpoint, String? role) onRoleChanged;
  final void Function(DeviceEndpoint endpoint, bool value) onPowerChanged;
  final void Function(DeviceEndpoint endpoint) onRename;

  static const _roleOptions = <String, String>{
    'light': 'Luz',
    'switch': 'Interruptor',
    'fan': 'Ventilador',
    'extractor': 'Extractor',
    'sensor': 'Sensor',
  };

  @override
  Widget build(BuildContext context) {
    final endpoints = device.endpoints;
    if (endpoints.isEmpty) {
      return const Text(
        'Sin controles adicionales para este tipo.',
        style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (endpoints.length > 1) ...[
          Text(
            '${endpoints.length} canales independientes',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < endpoints.length; i++) ...[
          if (i > 0) const Divider(height: 24, color: AppColors.border),
          _EndpointEditor(
            endpoint: endpoints[i],
            areas: areas,
            supportsRoles: supportsRoles,
            showPowerState: powerEndpoints(device).length > 1,
            powerBusy: powerBusyEndpointIds.contains(endpoints[i].id),
            roleOptions: _roleOptions,
            onAreaChanged: (areaId) => onAreaChanged(endpoints[i], areaId),
            onRoleChanged: (role) => onRoleChanged(endpoints[i], role),
            onPowerChanged: canCommandPower
                ? (value) => onPowerChanged(endpoints[i], value)
                : null,
            onRename: () => onRename(endpoints[i]),
          ),
        ],
      ],
    );
  }
}

/// Named like the mobile/wall per-channel editor on purpose: cross-surface
/// tests locate it by runtime type.
class _EndpointEditor extends StatelessWidget {
  const _EndpointEditor({
    required this.endpoint,
    required this.areas,
    required this.supportsRoles,
    required this.roleOptions,
    required this.onAreaChanged,
    required this.onRoleChanged,
    required this.onRename,
    this.showPowerState = false,
    this.powerBusy = false,
    this.onPowerChanged,
  });

  final DeviceEndpoint endpoint;
  final List<HomeArea> areas;
  final bool supportsRoles;
  final Map<String, String> roleOptions;
  final ValueChanged<String?> onAreaChanged;
  final ValueChanged<String?> onRoleChanged;
  final VoidCallback onRename;

  /// Whether the device has more than one power endpoint: only then is the
  /// per-control state shown (single-control devices already surface it in
  /// the header switch).
  final bool showPowerState;

  /// Whether this channel's power command is in flight: disables only this
  /// channel's switch.
  final bool powerBusy;

  /// Per-channel power command; null hides the switch (repository without
  /// command support).
  final ValueChanged<bool>? onPowerChanged;

  @override
  Widget build(BuildContext context) {
    final readOnly = _isReadOnlyEndpoint(endpoint);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(kindIcon(endpoint.kind), size: 18, color: AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    endpoint.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _channelFunctionLabel(endpoint),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11.5,
                    ),
                  ),
                  if (showPowerState && hasPowerCapability(endpoint)) ...[
                    const SizedBox(height: 2),
                    EndpointPowerBadge(endpoint: endpoint),
                  ],
                  if (readOnly)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Solo lectura',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showPowerState &&
                hasPowerCapability(endpoint) &&
                onPowerChanged != null) ...[
              Transform.scale(
                scale: 1.1,
                child: Switch(
                  value:
                      endpointPowerDisplayState(endpoint) ==
                      PowerDisplayState.on,
                  activeTrackColor: AppColors.gammaIndigo,
                  onChanged: powerBusy ? null : onPowerChanged,
                ),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'Cambiar nombre del canal',
              visualDensity: VisualDensity.compact,
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Each selector lives in its own labeled group Column so assistive
        // tech (and tests) resolve label → dropdown unambiguously.
        if (supportsRoles) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Qué controla',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                key: Key('desktop-channel-role-${endpoint.id}'),
                value: roleOptions.containsKey(endpoint.semanticRole)
                    ? endpoint.semanticRole
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin configurar'),
                  ),
                  for (final entry in roleOptions.entries)
                    DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: onRoleChanged,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controla',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              key: Key('desktop-channel-area-${endpoint.id}'),
              value: areas.any((a) => a.id == endpoint.controlledAreaId)
                  ? endpoint.controlledAreaId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin asignar'),
                ),
                for (final area in areas)
                  DropdownMenuItem<String?>(
                    value: area.id,
                    child: Text(area.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onAreaChanged,
            ),
          ],
        ),
      ],
    );
  }
}

/// Friendly per-channel function: what the canal really does, from its
/// capabilities (case-insensitive — the contract mixes `brightness` and
/// `BRIGHTNESS`). Never invents state, only labels capability.
String _channelFunctionLabel(DeviceEndpoint endpoint) {
  final caps = {for (final c in endpoint.capabilities) c.trim().toUpperCase()};
  final role = endpoint.semanticRole?.toLowerCase();
  if (role == 'sensor' ||
      endpoint.kind == DeviceKind.sensor ||
      caps.contains('MOTION')) {
    return 'Sensor de movimiento';
  }
  if (caps.contains('BRIGHTNESS')) return 'Luz regulable';
  if (caps.contains('TEMPERATURE_READ') || caps.contains('TEMPERATURE')) {
    return 'Sensor de temperatura';
  }
  if (caps.contains('HUMIDITY_READ') || caps.contains('HUMIDITY')) {
    return 'Sensor de humedad';
  }
  return 'Controla ${endpoint.displayName}';
}

bool _isReadOnlyEndpoint(DeviceEndpoint endpoint) {
  final caps = {for (final c in endpoint.capabilities) c.trim().toUpperCase()};
  if (endpoint.kind == DeviceKind.sensor) return true;
  if (caps.contains('MOTION')) return true;
  if (caps.contains('ON_OFF') || caps.contains('POWER')) return false;
  return caps.intersection({'BRIGHTNESS', 'SPEED', 'POSITION'}).isEmpty;
}

/// Detail-header availability in household language (wall parity): 'En línea'
/// instead of the power vocabulary used in list rows.
String _headerHealthLabel(DeviceHealthState health) => switch (health) {
  DeviceHealthState.online => 'En línea',
  DeviceHealthState.sleeping => 'En espera',
  DeviceHealthState.offline ||
  DeviceHealthState.unreachable ||
  DeviceHealthState.authError => 'Desconectado',
  DeviceHealthState.unknown => 'Desconocido',
};

class _TechRow extends StatelessWidget {
  const _TechRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsBody extends StatelessWidget {
  const _ControlsBody({
    required this.device,
    required this.areas,
    required this.type,
    required this.brightness,
    required this.fanSpeed,
    required this.targetTemperature,
    required this.climateMode,
    required this.position,
    required this.colorTemperature,
    required this.showColorTemperature,
    required this.commandsAvailable,
    required this.onTypeChanged,
    required this.onBrightnessChanged,
    required this.onFanSpeedChanged,
    required this.onTemperatureChanged,
    required this.onClimateModeChanged,
    required this.onPositionChanged,
    required this.onColorTemperatureChanged,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final String type;
  final double brightness;
  final int fanSpeed;
  final double targetTemperature;
  final String climateMode;
  final int position;
  final int colorTemperature;
  final bool showColorTemperature;

  /// Whether the repository exposes the canonical command surface; drives the
  /// fallback mode domain when the descriptor publishes no enum values.
  final bool commandsAvailable;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<int> onFanSpeedChanged;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<String> onClimateModeChanged;
  final ValueChanged<double> onPositionChanged;
  final ValueChanged<double> onColorTemperatureChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('desktop-type-dropdown'),
          value: type,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            for (final t in _detailTypes)
              DropdownMenuItem<String>(
                value: t,
                child: Text(_metaFor(t).label),
              ),
          ],
          onChanged: onTypeChanged,
        ),
        const SizedBox(height: 6),
        Text(
          _typeSourceLabel(device),
          style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
        ),
        const SizedBox(height: 12),
        _TypeControls(
          device: device,
          type: type,
          brightness: brightness,
          fanSpeed: fanSpeed,
          targetTemperature: targetTemperature,
          climateMode: climateMode,
          position: position,
          colorTemperature: colorTemperature,
          showColorTemperature: showColorTemperature,
          commandsAvailable: commandsAvailable,
          onBrightnessChanged: onBrightnessChanged,
          onFanSpeedChanged: onFanSpeedChanged,
          onTemperatureChanged: onTemperatureChanged,
          onClimateModeChanged: onClimateModeChanged,
          onPositionChanged: onPositionChanged,
          onColorTemperatureChanged: onColorTemperatureChanged,
        ),
      ],
    );
  }
}

String _typeSourceLabel(PhysicalDevice device) {
  final source = device.endpoints
      .map((e) => e.semanticRoleSource)
      .whereType<String>()
      .firstOrNull;
  return switch (source) {
    'user' => 'Configurado manualmente',
    'provider' => 'Detectado automáticamente',
    _ => 'Sin configurar',
  };
}

/// Reactive type-specific controls below the Tipo selector.
class _TypeControls extends StatelessWidget {
  const _TypeControls({
    required this.device,
    required this.type,
    required this.brightness,
    required this.fanSpeed,
    required this.targetTemperature,
    required this.climateMode,
    required this.position,
    required this.colorTemperature,
    required this.showColorTemperature,
    required this.commandsAvailable,
    required this.onBrightnessChanged,
    required this.onFanSpeedChanged,
    required this.onTemperatureChanged,
    required this.onClimateModeChanged,
    required this.onPositionChanged,
    required this.onColorTemperatureChanged,
  });

  final PhysicalDevice device;
  final String type;
  final double brightness;
  final int fanSpeed;
  final double targetTemperature;
  final String climateMode;
  final int position;
  final int colorTemperature;
  final bool showColorTemperature;
  final bool commandsAvailable;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<int> onFanSpeedChanged;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<String> onClimateModeChanged;
  final ValueChanged<double> onPositionChanged;
  final ValueChanged<double> onColorTemperatureChanged;

  @override
  Widget build(BuildContext context) {
    if (device.isGateway || device.kind == DeviceKind.gateway) {
      return const Text(
        'Este gateway conecta tus dispositivos. No tiene controles: '
        'su estado se gestiona solo.',
        style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
      );
    }
    final modeOptions = capabilityModeOptions(
      endpoint: firstEndpointWithCapability(device, 'MODE'),
      commandsAvailable: commandsAvailable,
      selected: climateMode,
    );
    return switch (type) {
      _typeBlinds => _PositionControl(
        position: position.toDouble(),
        onChanged: onPositionChanged,
      ),
      _typeFan => _FanControls(
        fanSpeed: fanSpeed,
        onChanged: onFanSpeedChanged,
      ),
      _typeClimate => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TemperatureControl(
            targetTemperature: targetTemperature,
            onChanged: onTemperatureChanged,
          ),
          const SizedBox(height: 12),
          _ClimateModeChips(
            mode: climateMode,
            options: modeOptions,
            onChanged: onClimateModeChanged,
          ),
          const SizedBox(height: 12),
          _FanControls(
            fanSpeed: fanSpeed,
            onChanged: onFanSpeedChanged,
            label: 'Velocidad del ventilador',
          ),
        ],
      ),
      _typeLight => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrightnessControl(
            brightness: brightness,
            onChanged: onBrightnessChanged,
          ),
          if (showColorTemperature) ...[
            const SizedBox(height: 12),
            _ColorTemperatureControl(
              colorTemperature: colorTemperature.toDouble(),
              onChanged: onColorTemperatureChanged,
            ),
          ],
        ],
      ),
      _typeSensor => _SensorReading(value: device.sensorValue),
      _ => const Text(
        'Sin controles adicionales para este tipo.',
        style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
      ),
    };
  }
}

class _FanControls extends StatelessWidget {
  const _FanControls({
    required this.fanSpeed,
    required this.onChanged,
    this.label = 'Velocidad',
  });

  final int fanSpeed;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var speed = 1; speed <= 3; speed++) ...[
              Expanded(
                child: _SpeedCard(
                  speed: speed,
                  selected: fanSpeed == speed,
                  onTap: () => onChanged(speed),
                ),
              ),
              if (speed != 3) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final int speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.gammaIndigoLight : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.gammaIndigo : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '$speed',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.gammaIndigo : AppColors.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemperatureControl extends StatelessWidget {
  const _TemperatureControl({
    required this.targetTemperature,
    required this.onChanged,
  });

  final double targetTemperature;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Temperatura objetivo',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Bajar temperatura',
              onPressed: targetTemperature > 16
                  ? () => onChanged(targetTemperature - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '${targetTemperature.toStringAsFixed(0)} °C',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Subir temperatura',
              onPressed: targetTemperature < 30
                  ? () => onChanged(targetTemperature + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Slider(
          value: targetTemperature.clamp(16, 30),
          min: 16,
          max: 30,
          divisions: 14,
          label: '${targetTemperature.toStringAsFixed(0)} °C',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ClimateModeChips extends StatelessWidget {
  const _ClimateModeChips({
    required this.mode,
    required this.options,
    required this.onChanged,
  });

  final String mode;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modo',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(capabilityModeLabel(option)),
                selected: mode == option,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    );
  }
}

/// Shared percent slider used by the capability-backed controls (brightness,
/// position, color temperature). 0-100 with 20 divisions.
class _PercentControl extends StatelessWidget {
  const _PercentControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const Spacer(),
            Text(
              '${value.round()} %',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0, 100),
          min: 0,
          max: 100,
          divisions: 20,
          label: '${value.round()} %',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _BrightnessControl extends StatelessWidget {
  const _BrightnessControl({required this.brightness, required this.onChanged});

  final double brightness;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PercentControl(
      label: 'Brillo',
      value: brightness,
      onChanged: onChanged,
    );
  }
}

class _PositionControl extends StatelessWidget {
  const _PositionControl({required this.position, required this.onChanged});

  final double position;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PercentControl(
      label: 'Posición',
      value: position,
      onChanged: onChanged,
    );
  }
}

class _ColorTemperatureControl extends StatelessWidget {
  const _ColorTemperatureControl({
    required this.colorTemperature,
    required this.onChanged,
  });

  final double colorTemperature;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PercentControl(
      label: 'Temperatura de color',
      value: colorTemperature,
      onChanged: onChanged,
    );
  }
}

class _SensorReading extends StatelessWidget {
  const _SensorReading({required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.sensors_outlined,
            size: 20,
            color: AppColors.textDim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value ?? 'Sin datos recientes',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Valor actual reportado (solo lectura)',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRenameDialog extends StatefulWidget {
  const _DetailRenameDialog({required this.initialName, this.canReset = false});
  final String initialName;

  /// When true, offers 'Restablecer' which pops an empty string: the caller
  /// clears the custom name back to the provider display name (wall parity).
  final bool canReset;
  @override
  State<_DetailRenameDialog> createState() => _DetailRenameDialogState();
}

class _DetailRenameDialogState extends State<_DetailRenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar nombre'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Nombre',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Restablecer'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

/// Splash animado de éxito para el detalle desktop: tarjeta centrada con
/// check verde que entra con rebote (scale + fade) y se cierra sola.
/// Se muestra por encima con un leve velo; tocar fuera la descarta antes.
Future<void> showDesktopSuccessSplash(
  BuildContext context, {
  required String message,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: message,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _SuccessSplash(message: message),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: 0.7, end: 1).animate(curved),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class _SuccessSplash extends StatefulWidget {
  const _SuccessSplash({required this.message});

  final String message;

  @override
  State<_SuccessSplash> createState() => _SuccessSplashState();
}

class _SuccessSplashState extends State<_SuccessSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          decoration: BoxDecoration(
            color: AppColors.toastDark,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.statusEncendido,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
