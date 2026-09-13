import 'dart:async';

import 'package:flutter/foundation.dart';

enum DeviceProvisioningState {
  discovered,
  enriched,
  partiallyConfigured,
  configured,
  missing,
  disabled,
}

enum DeviceHealthState {
  online,
  offline,
  unknown,
  sleeping,
  unreachable,
  authError,
}

DeviceHealthState parseDeviceHealthState(Object? value) {
  switch (value?.toString().toUpperCase()) {
    case 'ONLINE':
      return DeviceHealthState.online;
    case 'OFFLINE':
      return DeviceHealthState.offline;
    case 'SLEEPING':
      return DeviceHealthState.sleeping;
    case 'UNREACHABLE':
      return DeviceHealthState.unreachable;
    case 'AUTH_ERROR':
      return DeviceHealthState.authError;
    default:
      return DeviceHealthState.unknown;
  }
}

DeviceProvisioningState parseProvisioningState(Object? value) {
  switch (value?.toString().toUpperCase()) {
    case 'DISCOVERED':
      return DeviceProvisioningState.discovered;
    case 'ENRICHED':
      return DeviceProvisioningState.enriched;
    case 'PARTIALLY_CONFIGURED':
      return DeviceProvisioningState.partiallyConfigured;
    case 'CONFIGURED':
      return DeviceProvisioningState.configured;
    case 'MISSING':
      return DeviceProvisioningState.missing;
    case 'DISABLED':
      return DeviceProvisioningState.disabled;
    default:
      throw DeviceDtoException(field: 'provisioning_state', value: value);
  }
}

enum ProviderHealthState {
  lanReady,
  cloudReady,
  cloudDegraded,
  cloudNotConfigured,
  authError,
  unknown,
}

ProviderHealthState parseProviderHealthState(Object? value) {
  switch (value?.toString().toUpperCase()) {
    case 'LAN_READY':
      return ProviderHealthState.lanReady;
    case 'CLOUD_READY':
      return ProviderHealthState.cloudReady;
    case 'CLOUD_DEGRADED':
      return ProviderHealthState.cloudDegraded;
    case 'CLOUD_NOT_CONFIGURED':
      return ProviderHealthState.cloudNotConfigured;
    case 'AUTH_ERROR':
      return ProviderHealthState.authError;
    default:
      return ProviderHealthState.unknown;
  }
}

@immutable
class ProviderHealth {
  const ProviderHealth({
    required this.providerId,
    required this.lanReady,
    required this.cloudReady,
    required this.state,
  });

  factory ProviderHealth.fromJson(Map<String, dynamic> json) {
    return ProviderHealth(
      providerId: json['provider_id'] is String
          ? json['provider_id'] as String
          : '',
      lanReady: json['lan_ready'] == true,
      cloudReady: json['cloud_ready'] is bool
          ? json['cloud_ready'] as bool
          : null,
      state: parseProviderHealthState(json['status']),
    );
  }

  final String providerId;
  final bool lanReady;
  final bool? cloudReady;
  final ProviderHealthState state;
}

enum DeviceKind { light, switchController, outlet, sensor, gateway, unknown }

@immutable
class HomeArea {
  const HomeArea({
    required this.id,
    required this.name,
    this.aliases = const [],
  });

  factory HomeArea.fromJson(Map<String, dynamic> json) {
    final rawAliases = json['aliases'];
    return HomeArea(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      aliases: rawAliases is List
          ? List.unmodifiable(rawAliases.whereType<String>())
          : const [],
    );
  }

  final String id;
  final String name;
  final List<String> aliases;

  HomeArea copyWith({String? name, List<String>? aliases}) {
    return HomeArea(
      id: id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
    );
  }
}

enum NamingSource { user, provider, semanticRole, fallback }

NamingSource parseNamingSource(Object? value) {
  switch (value?.toString().toUpperCase()) {
    case 'USER':
      return NamingSource.user;
    case 'PROVIDER':
      return NamingSource.provider;
    case 'SEMANTIC_ROLE':
      return NamingSource.semanticRole;
    case 'FALLBACK':
      return NamingSource.fallback;
    default:
      return NamingSource.fallback;
  }
}

@immutable
class DeviceBinding {
  const DeviceBinding({
    required this.targetEntityId,
    required this.label,
    this.relation = 'controls',
  });

  final String targetEntityId;
  final String label;
  final String relation;
}

/// Canonical capability descriptor from an endpoint's `capabilities[]` list.
///
/// Purely descriptive: [range] is `[min, max]` for numeric capabilities,
/// [enumValues] the allowed values for enum-like ones. Absent optional
/// metadata stays null instead of being invented.
@immutable
class DeviceCapability {
  const DeviceCapability({
    required this.name,
    required this.readable,
    required this.writable,
    this.range,
    this.enumValues,
    this.confidence,
  });

  final String name;
  final bool readable;
  final bool writable;
  final List<double>? range;
  final List<String>? enumValues;
  final double? confidence;
}

/// Defensive parser for one `capabilities[]` entry. Returns null when the
/// entry is not a map or has no usable `capability` name; every other field
/// degrades to its absent value instead of failing the inventory load.
DeviceCapability? parseDeviceCapability(Object? value) {
  if (value is! Map) return null;
  final name = value['capability'];
  if (name is! String || name.trim().isEmpty) return null;

  List<double>? range;
  final rawRange = value['range'];
  if (rawRange is List && rawRange.length >= 2) {
    final min = rawRange[0];
    final max = rawRange[1];
    if (min is num && max is num) {
      range = List.unmodifiable([min.toDouble(), max.toDouble()]);
    }
  }

  List<String>? enumValues;
  final rawEnum = value['enum_values'];
  if (rawEnum is List) {
    final values = rawEnum.whereType<String>().toList();
    if (values.isNotEmpty) enumValues = List.unmodifiable(values);
  }

  final rawConfidence = value['confidence'];

  return DeviceCapability(
    name: name,
    readable: value['readable'] == true,
    writable: value['writable'] == true,
    range: range,
    enumValues: enumValues,
    confidence: rawConfidence is num ? rawConfidence.toDouble() : null,
  );
}

/// One observed capability value reported under
/// `observed_state.capabilities[name]`. [value] stays untyped on purpose: the
/// contract can carry int, num, string or bool values.
@immutable
class EndpointCapabilityObservation {
  const EndpointCapabilityObservation({
    this.value,
    this.quality,
    this.observedAt,
  });

  final Object? value;
  final String? quality;
  final String? observedAt;
}

/// Defensive parser for the `observed_state.capabilities` map. Malformed
/// entries (non-map values, empty keys) are skipped instead of failing the
/// load; valid entries keep whatever fields they carry.
Map<String, EndpointCapabilityObservation> parseObservedCapabilities(
  Object? raw,
) {
  if (raw is! Map) return const {};
  final result = <String, EndpointCapabilityObservation>{};
  raw.forEach((key, value) {
    if (key is! String || key.trim().isEmpty || value is! Map) return;
    final quality = value['quality'];
    final observedAt = value['observed_at'];
    result[key] = EndpointCapabilityObservation(
      value: value['value'],
      quality: quality is String && quality.isNotEmpty ? quality : null,
      observedAt: observedAt is String ? observedAt : null,
    );
  });
  return Map.unmodifiable(result);
}

@immutable
class DeviceEndpoint {
  const DeviceEndpoint({
    required this.id,
    required this.name,
    required this.kind,
    required this.capabilities,
    this.capabilityDetails = const {},
    this.controlledAreaId,
    this.bindings = const [],
    this.userName,
    this.semanticRole,
    this.providerSemanticRole,
    this.semanticRoleSource,
    this.stableOrdinal,
    this.displayNameSemantic,
    this.displayNameGlobal,
    this.namingSource = NamingSource.fallback,
    this.observedPower,
    this.observedQuality,
    this.observedAt,
    this.observedCapabilities = const {},
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final Set<String> capabilities;

  /// Descriptor metadata per capability name (readable/writable/range/enum).
  /// Empty when the backend omits `capabilities[]` metadata.
  final Map<String, DeviceCapability> capabilityDetails;
  final String? controlledAreaId;
  final List<DeviceBinding> bindings;

  /// GAMMA-owned explicit name; null when unset (F2-B).
  final String? userName;

  /// Backend effective semantic role (light/switch/fan/sensor/unknown).
  final String? semanticRole;

  /// Latest provider-declared semantic role (independent of effective).
  final String? providerSemanticRole;

  /// Ownership of the effective semantic role (provider/user/none).
  final String? semanticRoleSource;

  /// Backend-owned stable ordinal, read-only.
  final int? stableOrdinal;

  /// Backend-computed semantic display names. Rendered exactly; never
  /// recomputed client-side (F2-C).
  final String? displayNameSemantic;
  final String? displayNameGlobal;
  final NamingSource namingSource;

  /// Last observed power state reported by the backend; strictly parsed
  /// (non-bool values become null). Null means unknown/unreported.
  final bool? observedPower;

  /// Observation quality (`confirmed|stale|unknown|unavailable`); only a
  /// non-empty string is kept, anything else becomes null.
  final String? observedQuality;

  /// ISO-8601 timestamp of the observation, when reported.
  final String? observedAt;

  /// Per-capability observations from `observed_state.capabilities`
  /// (keyed by canonical capability name, e.g. `BRIGHTNESS`). Empty when the
  /// backend reports none.
  final Map<String, EndpointCapabilityObservation> observedCapabilities;

  String get displayName => displayNameSemantic ?? name;

  /// True when the user explicitly configured the effective semantic role.
  bool get isUserConfiguredRole => semanticRoleSource == 'user';

  DeviceEndpoint copyWith({
    String? name,
    DeviceKind? kind,
    Set<String>? capabilities,
    Map<String, DeviceCapability>? capabilityDetails,
    Object? controlledAreaId = _unset,
    List<DeviceBinding>? bindings,
    Object? userName = _unset,
    String? semanticRole,
    String? providerSemanticRole,
    String? semanticRoleSource,
    int? stableOrdinal,
    String? displayNameSemantic,
    String? displayNameGlobal,
    NamingSource? namingSource,
    Object? observedPower = _unset,
    Object? observedQuality = _unset,
    Object? observedAt = _unset,
    Map<String, EndpointCapabilityObservation>? observedCapabilities,
  }) {
    return DeviceEndpoint(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      capabilities: capabilities ?? this.capabilities,
      capabilityDetails: capabilityDetails ?? this.capabilityDetails,
      controlledAreaId: identical(controlledAreaId, _unset)
          ? this.controlledAreaId
          : controlledAreaId as String?,
      bindings: bindings ?? this.bindings,
      userName: identical(userName, _unset)
          ? this.userName
          : userName as String?,
      semanticRole: semanticRole ?? this.semanticRole,
      providerSemanticRole: providerSemanticRole ?? this.providerSemanticRole,
      semanticRoleSource: semanticRoleSource ?? this.semanticRoleSource,
      stableOrdinal: stableOrdinal ?? this.stableOrdinal,
      displayNameSemantic: displayNameSemantic ?? this.displayNameSemantic,
      displayNameGlobal: displayNameGlobal ?? this.displayNameGlobal,
      namingSource: namingSource ?? this.namingSource,
      observedPower: identical(observedPower, _unset)
          ? this.observedPower
          : observedPower as bool?,
      observedQuality: identical(observedQuality, _unset)
          ? this.observedQuality
          : observedQuality as String?,
      observedAt: identical(observedAt, _unset)
          ? this.observedAt
          : observedAt as String?,
      observedCapabilities: observedCapabilities ?? this.observedCapabilities,
    );
  }
}

@immutable
class PhysicalDevice {
  const PhysicalDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.provider,
    required this.providerDeviceId,
    required this.model,
    required this.provisioningState,
    required this.online,
    required this.health,
    required this.endpoints,
    this.manufacturer,
    this.gatewayId,
    this.physicalAreaId,
    this.lastSeenLabel,
    this.isSubdevice = false,
    this.isGateway = false,
    this.parentDeviceId,
    this.providerName,
    this.userName,
    this.hasKey,
    this.pendingKey,
    this.deviceClass = 'unknown',
    this.deviceClassSource = 'none',
    // Demo-only display state (mock): optional overrides used by the desktop
    // detail pane to preview type-specific controls. Never parsed from the
    // backend contract; HTTP parsing leaves them null.
    this.powerOn,
    this.brightness,
    this.fanSpeed,
    this.targetTemperature,
    this.climateMode,
    this.position,
    this.colorTemperature,
    this.sensorValue,
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final String provider;
  final String providerDeviceId;
  final String model;
  final String? manufacturer;
  final String? gatewayId;
  final String? physicalAreaId;
  final DeviceProvisioningState provisioningState;
  final bool online;
  final DeviceHealthState health;
  final List<DeviceEndpoint> endpoints;
  final String? lastSeenLabel;
  final bool isSubdevice;
  final bool isGateway;
  final String? parentDeviceId;

  /// Provider-owned name (F2-B), read-only in F2-C.
  final String? providerName;

  /// GAMMA-owned explicit name; null when unset (F2-B).
  final String? userName;

  /// Whether the provider already holds credentials for this device
  /// (`has_key`). Null when the backend omits the field.
  final bool? hasKey;

  /// Whether credential configuration is still pending (`pending_key`).
  /// Null when the backend omits the field.
  final bool? pendingKey;

  final String deviceClass;
  final String deviceClassSource;

  /// Demo-only display state (mock). Null means "unknown / not reported".
  /// [brightness] is 0-100, [fanSpeed] is 1-3, [targetTemperature] is °C,
  /// [climateMode] is one of cold/heat/auto/fan, [position] is 0-100,
  /// [colorTemperature] is 0-100.
  final bool? powerOn;
  final int? brightness;
  final int? fanSpeed;
  final double? targetTemperature;
  final String? climateMode;
  final int? position;
  final int? colorTemperature;
  final String? sensorValue;

  bool get needsConfiguration =>
      provisioningState == DeviceProvisioningState.discovered ||
      provisioningState == DeviceProvisioningState.enriched ||
      provisioningState == DeviceProvisioningState.partiallyConfigured;

  PhysicalDevice copyWith({
    String? name,
    DeviceKind? kind,
    String? provider,
    String? providerDeviceId,
    String? model,
    Object? manufacturer = _unset,
    Object? gatewayId = _unset,
    Object? physicalAreaId = _unset,
    DeviceProvisioningState? provisioningState,
    bool? online,
    DeviceHealthState? health,
    List<DeviceEndpoint>? endpoints,
    Object? lastSeenLabel = _unset,
    bool? isSubdevice,
    bool? isGateway,
    Object? parentDeviceId = _unset,
    Object? providerName = _unset,
    Object? userName = _unset,
    Object? hasKey = _unset,
    Object? pendingKey = _unset,
    String? deviceClass,
    String? deviceClassSource,
    Object? powerOn = _unset,
    Object? brightness = _unset,
    Object? fanSpeed = _unset,
    Object? targetTemperature = _unset,
    Object? climateMode = _unset,
    Object? position = _unset,
    Object? colorTemperature = _unset,
    Object? sensorValue = _unset,
  }) {
    return PhysicalDevice(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      provider: provider ?? this.provider,
      providerDeviceId: providerDeviceId ?? this.providerDeviceId,
      model: model ?? this.model,
      manufacturer: identical(manufacturer, _unset)
          ? this.manufacturer
          : manufacturer as String?,
      gatewayId: identical(gatewayId, _unset)
          ? this.gatewayId
          : gatewayId as String?,
      physicalAreaId: identical(physicalAreaId, _unset)
          ? this.physicalAreaId
          : physicalAreaId as String?,
      provisioningState: provisioningState ?? this.provisioningState,
      online: online ?? this.online,
      health: health ?? this.health,
      endpoints: endpoints ?? this.endpoints,
      lastSeenLabel: identical(lastSeenLabel, _unset)
          ? this.lastSeenLabel
          : lastSeenLabel as String?,
      isSubdevice: isSubdevice ?? this.isSubdevice,
      isGateway: isGateway ?? this.isGateway,
      parentDeviceId: identical(parentDeviceId, _unset)
          ? this.parentDeviceId
          : parentDeviceId as String?,
      providerName: identical(providerName, _unset)
          ? this.providerName
          : providerName as String?,
      userName: identical(userName, _unset)
          ? this.userName
          : userName as String?,
      hasKey: identical(hasKey, _unset) ? this.hasKey : hasKey as bool?,
      pendingKey: identical(pendingKey, _unset)
          ? this.pendingKey
          : pendingKey as bool?,
      deviceClass: deviceClass ?? this.deviceClass,
      deviceClassSource: deviceClassSource ?? this.deviceClassSource,
      powerOn: identical(powerOn, _unset) ? this.powerOn : powerOn as bool?,
      brightness: identical(brightness, _unset)
          ? this.brightness
          : brightness as int?,
      fanSpeed: identical(fanSpeed, _unset) ? this.fanSpeed : fanSpeed as int?,
      targetTemperature: identical(targetTemperature, _unset)
          ? this.targetTemperature
          : targetTemperature as double?,
      climateMode: identical(climateMode, _unset)
          ? this.climateMode
          : climateMode as String?,
      position: identical(position, _unset) ? this.position : position as int?,
      colorTemperature: identical(colorTemperature, _unset)
          ? this.colorTemperature
          : colorTemperature as int?,
      sensorValue: identical(sensorValue, _unset)
          ? this.sensorValue
          : sensorValue as String?,
    );
  }
}

/// Whether [endpoint] exposes a power channel. Accepts the canonical `POWER`
/// capability and the legacy/mock `on_off` spelling.
bool hasPowerCapability(DeviceEndpoint endpoint) =>
    endpoint.capabilities.contains('POWER') ||
    endpoint.capabilities.contains('on_off');

/// Honest power display state for a surface. [unknown] must never be
/// converted into [off]: no observation means no confident state.
enum PowerDisplayState { on, off, unknown }

/// Endpoint power display: on/off only for a confirmed observation; anything
/// else (missing power, stale/unknown quality) is [PowerDisplayState.unknown].
PowerDisplayState endpointPowerDisplayState(DeviceEndpoint endpoint) {
  final power = endpoint.observedPower;
  if (endpoint.observedQuality == 'confirmed' && power != null) {
    return power ? PowerDisplayState.on : PowerDisplayState.off;
  }
  return PowerDisplayState.unknown;
}

/// Device power display: the first endpoint with a confirmed observation
/// decides; otherwise the demo-only [PhysicalDevice.powerOn] (mock path) is
/// the last resort; otherwise unknown.
PowerDisplayState devicePowerDisplayState(PhysicalDevice device) {
  for (final endpoint in device.endpoints) {
    final state = endpointPowerDisplayState(endpoint);
    if (state != PowerDisplayState.unknown) return state;
  }
  final demoPower = device.powerOn;
  if (demoPower != null) {
    return demoPower ? PowerDisplayState.on : PowerDisplayState.off;
  }
  return PowerDisplayState.unknown;
}

/// Power endpoints of [device] (canonical or legacy spelling).
List<DeviceEndpoint> powerEndpoints(PhysicalDevice device) =>
    device.endpoints.where(hasPowerCapability).toList();

/// (confirmedOn, total, unknown) among power endpoints.
(int, int, int) powerStateCounts(PhysicalDevice device) {
  final endpoints = powerEndpoints(device);
  var confirmedOn = 0;
  var unknown = 0;
  for (final endpoint in endpoints) {
    switch (endpointPowerDisplayState(endpoint)) {
      case PowerDisplayState.on:
        confirmedOn++;
      case PowerDisplayState.off:
        break;
      case PowerDisplayState.unknown:
        unknown++;
    }
  }
  return (confirmedOn, endpoints.length, unknown);
}

/// Whether [capability] can receive commands on [endpoint]: the canonical
/// descriptor decides when present, otherwise the legacy
/// [DeviceEndpoint.capabilities] set is the fallback (mock/fake repositories).
bool capabilityWritable(DeviceEndpoint endpoint, String capability) {
  final detail = endpoint.capabilityDetails[capability];
  if (detail != null) return detail.writable;
  return endpoint.capabilities.contains(capability);
}

/// Confirmed [capability] value on [endpoint], or null when there is no
/// observation or it is not `confirmed`. Unconfirmed state is never returned:
/// stale/unknown values must not be presented as confident ones.
Object? confirmedCapabilityValue(DeviceEndpoint endpoint, String capability) {
  final observation = endpoint.observedCapabilities[capability];
  if (observation == null || observation.quality != 'confirmed') return null;
  return observation.value;
}

/// First endpoint of [device] where [capability] is present and writable
/// (descriptor-aware; legacy capability sets without descriptors stay
/// writable). Returns null when no endpoint can receive the command.
DeviceEndpoint? firstEndpointWithCapability(
  PhysicalDevice device,
  String capability,
) {
  for (final endpoint in device.endpoints) {
    if (capabilityWritable(endpoint, capability)) return endpoint;
  }
  return null;
}

/// Bridges the UI's 3-level fan control to the canonical percent domain:
/// 1→33, 2→67, 3→100.
int speedLevelToPercent(int level) => (level * 100 / 3).round();

/// Inverse of [speedLevelToPercent]: 33→1, 67→2, 80→2, 100→3. Clamped to the
/// 1..3 domain.
int percentToSpeedLevel(num percent) =>
    ((percent * 3) / 100).round().clamp(1, 3).toInt();

@immutable
class GatewayInfo {
  const GatewayInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.health,
    required this.childDeviceIds,
  });

  final String id;
  final String name;
  final String provider;

  /// Salud del dispositivo gateway. Antes del smoke LAN no existe evidencia
  /// de alcance físico local, por lo que el repositorio HTTP la reporta como
  /// [DeviceHealthState.unknown]; NUNCA se proyecta provider.lanReady aquí.
  final DeviceHealthState health;
  final List<String> childDeviceIds;
}

@immutable
class DeviceInventorySnapshot {
  const DeviceInventorySnapshot({
    required this.areas,
    required this.devices,
    required this.gateways,
    required this.lastDiscoveryLabel,
  });

  final List<HomeArea> areas;
  final List<PhysicalDevice> devices;
  final List<GatewayInfo> gateways;
  final String lastDiscoveryLabel;

  List<PhysicalDevice> get userDevices =>
      devices.where((d) => !d.isGateway).toList();

  /// Pending configuration among ONLINE devices: offline rows never inflate
  /// pending counts or lists — they live in the offline surfaces
  /// (`offlineDevices`). The per-device [needsConfiguration] state stays
  /// intact for labels.
  List<PhysicalDevice> get unassigned =>
      userDevices
          .where((d) => d.needsConfiguration && !isOfflineDevice(d))
          .toList();

  /// True when the device is known to be not reachable right now.
  static bool isOfflineDevice(PhysicalDevice device) =>
      device.health == DeviceHealthState.offline ||
      device.health == DeviceHealthState.unreachable ||
      device.health == DeviceHealthState.authError;

  List<PhysicalDevice> get offlineDevices =>
      userDevices.where(isOfflineDevice).toList();

  List<PhysicalDevice> get activeDevices =>
      userDevices.where((d) => !isOfflineDevice(d)).toList();

  List<PhysicalDevice> devicesInArea(String areaId) => devices
      .where(
        (device) =>
            device.physicalAreaId == areaId ||
            device.endpoints.any(
              (endpoint) => endpoint.controlledAreaId == areaId,
            ),
      )
      .toList();
}

abstract interface class DeviceInventoryRepository {
  bool get supportsIdentify => true;

  /// F2-D closure: whether the repository can edit the endpoint semantic
  /// role (user override). Defaults false; HTTP repo enables it.
  bool get supportsSemanticRole => false;

  Future<DeviceInventorySnapshot> load();

  Future<DeviceInventorySnapshot> discover();

  Future<PhysicalDevice> assignPhysicalArea(String deviceId, String? areaId);

  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  );

  /// Set (string role key) or clear (null) the user semantic-role override.
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  );

  /// Set (string) or clear (null) the GAMMA-owned device name.
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName);

  /// Set (string) or clear (null) the GAMMA-owned endpoint name.
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  );

  /// Areas CRUD. [deleteArea] may throw an unsupported/conflict error when
  /// the backend has no DELETE or the Area is referenced.
  Future<List<HomeArea>> listAreas();

  Future<HomeArea> createArea(String name, {List<String> aliases = const []});

  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  });

  Future<void> deleteArea(String areaId);

  Future<void> identify(String deviceId, {String? endpointId});
}

/// Optional bulk state-sweep surface, segregated the same way as
/// [DeviceCommandRepository]: only repositories backed by the observed-state
/// store opt in, so every existing [DeviceInventoryRepository] implementer
/// (including test fakes) keeps compiling untouched.
abstract interface class DeviceStateRefreshRepository {
  /// Triggers the backend read-only sweep of current device states and
  /// returns once the summary was accepted. Success means the store is
  /// refreshed, never that any device answered.
  Future<void> refreshDeviceStates();
}

/// Narrows [repo] to [DeviceStateRefreshRepository] when supported, else null.
DeviceStateRefreshRepository? asDeviceStateRefreshRepository(
  DeviceInventoryRepository repo,
) {
  if (repo is DeviceStateRefreshRepository) {
    return repo as DeviceStateRefreshRepository;
  }
  return null;
}

/// Typed outcome of one endpoint power command.
///
/// Deliberately decoupled from [PhysicalDevice]: whether execution succeeded
/// and what state is currently observed are independent facts. Immutable.
@immutable
class EndpointPowerResult {
  const EndpointPowerResult({
    required this.outcome,
    this.changed,
    this.observedPower,
    this.observedQuality,
    this.observedAt,
    this.errorCode,
    this.errorDetail,
    this.responseParsed = true,
  });

  /// Canonical outcome (SUCCESS|NO_CHANGE|UNSUPPORTED|UNAVAILABLE|TIMEOUT|
  /// FAILED|EXECUTION_DISABLED), or `unconfirmed` when the backend returned
  /// no parsed body (current live behavior).
  final String outcome;

  /// Whether the command changed the physical state, when reported.
  final bool? changed;

  /// Observed power after execution; null means unknown/unavailable.
  final bool? observedPower;

  /// Observation quality (`confirmed|stale|unknown|unavailable`).
  final String? observedQuality;

  /// ISO-8601 timestamp of the observation, when reported.
  final String? observedAt;

  /// Machine-readable error code from the backend, when execution failed.
  final String? errorCode;

  /// Human-readable error detail from the backend, when execution failed.
  final String? errorDetail;

  /// False when the response body was null and no typed result was parsed.
  final bool responseParsed;
}

/// Typed outcome of one canonical capability action (`set_brightness`,
/// `set_speed`, `set_mode`, ...).
///
/// Same honesty contract as [EndpointPowerResult]: parsed outcomes are
/// returned as-is, a null body becomes `unconfirmed` with
/// `responseParsed == false`, and no success is ever fabricated.
@immutable
class CapabilityActionResult {
  const CapabilityActionResult({
    required this.action,
    this.capability,
    required this.outcome,
    this.changed,
    this.observedValue,
    this.observedQuality,
    this.observedAt,
    this.errorCode,
    this.errorDetail,
    this.responseParsed = true,
  });

  /// Canonical action name sent to the backend (e.g. `set_brightness`).
  final String action;

  /// Canonical capability the action targets (e.g. `BRIGHTNESS`); null when
  /// the action has no mapped capability.
  final String? capability;

  /// Canonical outcome (SUCCESS|NO_CHANGE|UNSUPPORTED|UNAVAILABLE|TIMEOUT|
  /// FAILED|EXECUTION_DISABLED), or `unconfirmed` for an unparsed body.
  final String outcome;

  final bool? changed;

  /// Value observed after execution in the targeted capability; null means
  /// unknown/unavailable.
  final Object? observedValue;
  final String? observedQuality;
  final String? observedAt;
  final String? errorCode;
  final String? errorDetail;

  /// False when the response body was null and no typed result was parsed.
  final bool responseParsed;
}

/// Result of an identify request: whether the provider supports it, plus the
/// reason when it does not.
@immutable
class IdentifyResult {
  const IdentifyResult({required this.supported, this.reason});

  final bool supported;
  final String? reason;
}

/// Segregated command surface for device operations the read-oriented
/// [DeviceInventoryRepository] intentionally does not expose.
///
/// Kept separate so the existing [DeviceInventoryRepository] implementers
/// (including test fakes) keep compiling; only repositories that opt in
/// implement this interface.
abstract interface class DeviceCommandRepository {
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  );

  /// Executes one canonical endpoint action (`set_power`, `set_brightness`,
  /// `set_position`, `set_color`, `set_color_temperature`, `set_speed`,
  /// `set_mode`) and returns its typed outcome.
  Future<CapabilityActionResult> executeAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  });

  Future<IdentifyResult> identifyDevice(String deviceId, {String? endpointId});

  Future<PhysicalDevice> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  });

  Future<PhysicalDevice> unbindEntity(String deviceId, String bindingId);

  Future<PhysicalDevice> refreshDevice(String deviceId);
}

/// Narrows [repo] to [DeviceCommandRepository] when supported, else null.
DeviceCommandRepository? asDeviceCommandRepository(
  DeviceInventoryRepository repo,
) {
  if (repo is DeviceCommandRepository) {
    return repo as DeviceCommandRepository;
  }
  return null;
}

class MockDeviceInventoryRepository implements DeviceInventoryRepository {
  MockDeviceInventoryRepository();

  static final shared = MockDeviceInventoryRepository();

  @override
  bool get supportsIdentify => true;

  @override
  bool get supportsSemanticRole => true;

  final List<HomeArea> _areas = [
    const HomeArea(id: 'sala', name: 'Sala'),
    const HomeArea(id: 'cocina', name: 'Cocina'),
    const HomeArea(id: 'comedor', name: 'Comedor'),
    const HomeArea(id: 'recamara', name: 'Recámara'),
    const HomeArea(id: 'pasillo', name: 'Pasillo'),
    const HomeArea(id: 'patio', name: 'Patio'),
  ];

  final List<PhysicalDevice> _devices = [
    const PhysicalDevice(
      id: 'dev_switch_triple_01',
      name: 'Interruptor triple',
      kind: DeviceKind.switchController,
      provider: 'Tuya',
      providerDeviceId: 'tuya-bf8a••••',
      model: 'TS0013',
      manufacturer: 'Moes',
      gatewayId: 'gw_tuya_01',
      provisioningState: DeviceProvisioningState.discovered,
      online: true,
      health: DeviceHealthState.online,
      lastSeenLabel: 'Ahora',
      powerOn: true,
      endpoints: [
        DeviceEndpoint(
          id: 'relay_1',
          name: 'Canal 1',
          kind: DeviceKind.switchController,
          capabilities: {'on_off'},
        ),
        DeviceEndpoint(
          id: 'relay_2',
          name: 'Canal 2',
          kind: DeviceKind.switchController,
          capabilities: {'on_off'},
        ),
        DeviceEndpoint(
          id: 'relay_3',
          name: 'Canal 3',
          kind: DeviceKind.switchController,
          capabilities: {'on_off'},
        ),
      ],
    ),
    const PhysicalDevice(
      id: 'dev_bulb_new_01',
      name: 'Foco Zigbee',
      kind: DeviceKind.light,
      provider: 'Tuya',
      providerDeviceId: 'tuya-bf31••••',
      model: 'ZB-RGBCW',
      gatewayId: 'gw_tuya_01',
      provisioningState: DeviceProvisioningState.discovered,
      online: true,
      health: DeviceHealthState.online,
      lastSeenLabel: 'Hace 1 min',
      powerOn: true,
      brightness: 80,
      endpoints: [
        DeviceEndpoint(
          id: 'light',
          name: 'Luz',
          kind: DeviceKind.light,
          capabilities: {'on_off', 'brightness', 'color_temperature'},
        ),
      ],
    ),
    const PhysicalDevice(
      id: 'dev_sensor_new_01',
      name: 'Sensor de movimiento',
      kind: DeviceKind.sensor,
      provider: 'Tuya',
      providerDeviceId: 'tuya-bf19••••',
      model: 'ZP01',
      gatewayId: 'gw_tuya_01',
      provisioningState: DeviceProvisioningState.discovered,
      online: true,
      health: DeviceHealthState.online,
      lastSeenLabel: 'Hace 2 min',
      sensorValue: 'Sin movimiento',
      endpoints: [
        DeviceEndpoint(
          id: 'motion',
          name: 'Movimiento',
          kind: DeviceKind.sensor,
          capabilities: {'motion', 'battery'},
        ),
      ],
    ),
    const PhysicalDevice(
      id: 'dev_plafon_cocina',
      name: 'Plafón cocina',
      kind: DeviceKind.light,
      provider: 'Tuya',
      providerDeviceId: 'tuya-a911••••',
      model: 'ZB-DL01',
      gatewayId: 'gw_tuya_01',
      physicalAreaId: 'cocina',
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.online,
      lastSeenLabel: 'Ahora',
      powerOn: true,
      brightness: 60,
      endpoints: [
        DeviceEndpoint(
          id: 'light',
          name: 'Plafón cocina',
          kind: DeviceKind.light,
          controlledAreaId: 'cocina',
          capabilities: {'on_off', 'brightness'},
        ),
      ],
    ),
    const PhysicalDevice(
      id: 'dev_wall_pasillo',
      name: 'Control de áreas',
      kind: DeviceKind.switchController,
      provider: 'Tuya',
      providerDeviceId: 'tuya-a522••••',
      model: 'TS0013',
      gatewayId: 'gw_tuya_01',
      physicalAreaId: 'pasillo',
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.online,
      lastSeenLabel: 'Ahora',
      endpoints: [
        DeviceEndpoint(
          id: 'relay_1',
          name: 'Luz cocina',
          kind: DeviceKind.switchController,
          controlledAreaId: 'cocina',
          bindings: [
            DeviceBinding(
              targetEntityId: 'dev_plafon_cocina.light',
              label: 'Controla Plafón cocina',
            ),
          ],
          capabilities: {'on_off'},
        ),
        DeviceEndpoint(
          id: 'relay_2',
          name: 'Luz comedor',
          kind: DeviceKind.switchController,
          controlledAreaId: 'comedor',
          bindings: [
            DeviceBinding(
              targetEntityId: 'light_comedor',
              label: 'Controla Luz comedor',
            ),
          ],
          capabilities: {'on_off'},
        ),
        DeviceEndpoint(
          id: 'relay_3',
          name: 'Luz patio',
          kind: DeviceKind.switchController,
          controlledAreaId: 'patio',
          bindings: [
            DeviceBinding(
              targetEntityId: 'light_patio',
              label: 'Controla Luz patio',
            ),
          ],
          capabilities: {'on_off'},
        ),
      ],
    ),
    const PhysicalDevice(
      id: 'dev_outlet_sala',
      name: 'Enchufe TV',
      kind: DeviceKind.outlet,
      provider: 'Tuya',
      providerDeviceId: 'tuya-cc27••••',
      model: 'TS011F',
      gatewayId: 'gw_tuya_01',
      physicalAreaId: 'sala',
      provisioningState: DeviceProvisioningState.configured,
      online: false,
      health: DeviceHealthState.offline,
      lastSeenLabel: 'Hace 18 min',
      powerOn: false,
      endpoints: [
        DeviceEndpoint(
          id: 'outlet',
          name: 'Enchufe TV',
          kind: DeviceKind.outlet,
          controlledAreaId: 'sala',
          capabilities: {'on_off', 'power_meter'},
        ),
      ],
    ),
  ];

  final _gateways = const [
    GatewayInfo(
      id: 'gw_tuya_01',
      name: 'Gateway Zigbee principal',
      provider: 'Tuya',
      health: DeviceHealthState.online,
      childDeviceIds: [
        'dev_switch_triple_01',
        'dev_bulb_new_01',
        'dev_sensor_new_01',
        'dev_plafon_cocina',
        'dev_wall_pasillo',
        'dev_outlet_sala',
      ],
    ),
  ];

  @override
  Future<DeviceInventorySnapshot> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _snapshot('Hace unos segundos');
  }

  @override
  Future<DeviceInventorySnapshot> discover() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return _snapshot('Ahora');
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _indexOf(deviceId);
    final current = _devices[index];
    final updated = current.copyWith(
      physicalAreaId: areaId,
      provisioningState: _provisioningState(areaId, current.endpoints),
    );
    _devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _indexOf(deviceId);
    final current = _devices[index];
    final endpoints = current.endpoints
        .map(
          (endpoint) => endpoint.id == endpointId
              ? endpoint.copyWith(controlledAreaId: areaId)
              : endpoint,
        )
        .toList();
    final updated = current.copyWith(
      endpoints: endpoints,
      provisioningState: _provisioningState(current.physicalAreaId, endpoints),
    );
    _devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _indexOf(deviceId);
    final current = _devices[index];
    final endpoints = current.endpoints
        .map(
          (endpoint) => endpoint.id == endpointId
              ? endpoint.copyWith(semanticRole: role)
              : endpoint,
        )
        .toList();
    final updated = current.copyWith(endpoints: endpoints);
    _devices[index] = updated;
    return updated;
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {
    _indexOf(deviceId);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _indexOf(deviceId);
    final current = _devices[index];
    final updated = current.copyWith(userName: userName);
    _devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _indexOf(deviceId);
    final current = _devices[index];
    final endpoints = current.endpoints
        .map(
          (endpoint) => endpoint.id == endpointId
              ? endpoint.copyWith(userName: userName)
              : endpoint,
        )
        .toList();
    final updated = current.copyWith(endpoints: endpoints);
    _devices[index] = updated;
    return updated;
  }

  @override
  Future<List<HomeArea>> listAreas() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return List.unmodifiable(_areas);
  }

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final area = HomeArea(
      id: 'area_${_areas.length + 1}',
      name: name,
      aliases: aliases,
    );
    _areas.add(area);
    return area;
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _areas.indexWhere((area) => area.id == areaId);
    if (index < 0) throw StateError('Área no encontrada: $areaId');
    final updated = _areas[index].copyWith(name: name, aliases: aliases);
    _areas[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteArea(String areaId) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final index = _areas.indexWhere((area) => area.id == areaId);
    if (index < 0) throw StateError('Área no encontrada: $areaId');
    final used = _devices.any(
      (device) =>
          device.physicalAreaId == areaId ||
          device.endpoints.any(
            (endpoint) => endpoint.controlledAreaId == areaId,
          ),
    );
    if (used) {
      throw StateError('No se puede eliminar esta área mientras esté en uso.');
    }
    _areas.removeAt(index);
  }

  DeviceProvisioningState _provisioningState(
    String? physicalAreaId,
    List<DeviceEndpoint> endpoints,
  ) {
    final assignedEndpoints = endpoints
        .where((endpoint) => endpoint.controlledAreaId != null)
        .length;
    if (physicalAreaId != null && assignedEndpoints == endpoints.length) {
      return DeviceProvisioningState.configured;
    }
    if (physicalAreaId != null || assignedEndpoints > 0) {
      return DeviceProvisioningState.partiallyConfigured;
    }
    return DeviceProvisioningState.discovered;
  }

  int _indexOf(String deviceId) {
    final index = _devices.indexWhere((device) => device.id == deviceId);
    if (index < 0) throw StateError('Dispositivo no encontrado: $deviceId');
    return index;
  }

  DeviceInventorySnapshot _snapshot(String discoveryLabel) {
    return DeviceInventorySnapshot(
      areas: List.unmodifiable(_areas),
      devices: List.unmodifiable(_devices),
      gateways: List.unmodifiable(_gateways),
      lastDiscoveryLabel: discoveryLabel,
    );
  }
}

const _unset = Object();

class DeviceDtoException implements Exception {
  DeviceDtoException({
    required this.field,
    this.value,
    this.detail,
    this.deviceId,
  });

  /// Nombre del campo DTO que falló, p. ej. `device_id` o `is_gateway`.
  final String field;

  /// Valor recibido (nunca un mapa DTO completo; solo el campo).
  final Object? value;

  /// Mensaje human-safe adicional.
  final String? detail;

  /// ID del dispositivo al que pertenecía el DTO, si se conoce.
  final String? deviceId;

  @override
  String toString() {
    final where = deviceId == null ? '' : ' (dispositivo $deviceId)';
    return 'DeviceDtoException$where: campo inválido "$field"'
        '${detail != null ? ' — $detail' : ''}';
  }
}
