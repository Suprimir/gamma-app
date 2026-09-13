import 'api_client.dart';
import 'device_inventory.dart';

/// Repository mapping the DevicePlatform HTTP API into typed domain models.
/// Raw JSON stops at this boundary: callers only see [DeviceInventorySnapshot]
/// and [PhysicalDevice].
class HttpDeviceInventoryRepository
    implements
        DeviceInventoryRepository,
        DeviceCommandRepository,
        DeviceStateRefreshRepository,
        DeviceEventStreamRepository {
  HttpDeviceInventoryRepository(this._api);

  final ApiClient _api;

  // Internal cache of the last loaded devices (id -> PhysicalDevice) so
  // mutation returns keep the gateway partition consistent; cleared on load.
  final Map<String, PhysicalDevice> _cache = {};

  @override
  bool get supportsIdentify => false;

  @override
  Future<void> refreshDeviceStates() => _api.refreshDeviceStates();

  @override
  Stream<Map<String, dynamic>> deviceEvents() => _api.events();

  @override
  Future<DeviceInventorySnapshot> load() async {
    final results = await Future.wait([
      _api.deviceInventory(),
      _api.catalog(),
      _api.deviceProviderHealth(),
      _api.areas(),
    ]);
    final inventory = results[0] as Map<String, dynamic>;
    // Provider health (results[2]) is fetched for contract parity but is NOT
    // projected onto gateway/device health: lanReady describes the Tuya
    // integration, never physical reachability of a specific device.
    // The legacy catalog (results[1]) is likewise fetched for parity; the
    // canonical /api/v1/areas result is authoritative and legacy locations
    // never repopulate the canonical path.

    final parsed = _parseDevices(inventory);
    final gatewayIds = parsed
        .where(
          (device) =>
              device.isGateway ||
              parsed.any((other) => other.parentDeviceId == device.id),
        )
        .map((device) => device.id)
        .toSet();

    final devices = parsed
        .map(
          (device) => gatewayIds.contains(device.id)
              ? device.copyWith(kind: DeviceKind.gateway)
              : device,
        )
        .toList();

    final gateways = devices
        .where((device) => device.isGateway)
        .map(
          (device) => GatewayInfo(
            id: device.id,
            name: device.name,
            provider: device.provider,
            // Provider/runtime health (lanReady) describes the Tuya
            // integration, NOT the reachability of this physical gateway.
            // Before LAN validation the honest state is unknown.
            health: DeviceHealthState.unknown,
            childDeviceIds: List.unmodifiable(
              devices
                  .where((other) => other.parentDeviceId == device.id)
                  .map((other) => other.id)
                  .toList(),
            ),
          ),
        )
        .toList();

    // F2-C + F3-B: Areas come from the real AreaStore contract (/api/v1/areas)
    // and are authoritative — including an explicit empty list. A canonical
    // success with [] is an empty home, never a reason to repopulate from the
    // legacy catalog locations.
    final areaDtos = results[3];
    final areas = areaDtos is List
        ? _parseAreasList(areaDtos)
        : const <HomeArea>[];

    final snapshot = DeviceInventorySnapshot(
      areas: List.unmodifiable(areas),
      devices: List.unmodifiable(devices),
      gateways: List.unmodifiable(gateways),
      lastDiscoveryLabel: '',
    );

    _cache
      ..clear()
      ..addEntries(devices.map((device) => MapEntry(device.id, device)));

    return snapshot;
  }

  @override
  Future<DeviceInventorySnapshot> discover() async {
    await _api.discoverDevices();
    return load();
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    final dto = await _api.updateDevicePhysicalArea(deviceId, areaId);
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    final dto = await _api.updateEndpointControlledArea(
      deviceId,
      endpointId,
      areaId,
    );
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    final dto = await _api.updateEndpointSemanticRole(
      deviceId,
      endpointId,
      role,
    );
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    final dto = await _api.renameDevice(deviceId, userName);
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    final dto = await _api.renameEndpoint(deviceId, endpointId, userName);
    return _cacheAndReturn(dto, deviceId);
  }

  // ---- DeviceCommandRepository: execute/mutate beyond the read surface ----

  /// Canonical action → capability used to extract the per-capability
  /// observation from `observed_state.capabilities`.
  static const _actionCapabilities = <String, String>{
    'set_power': 'POWER',
    'set_brightness': 'BRIGHTNESS',
    'set_position': 'POSITION',
    'set_color': 'COLOR',
    'set_color_temperature': 'COLOR_TEMPERATURE',
    'set_speed': 'SPEED',
    'set_mode': 'MODE',
  };

  @override
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  ) async {
    final result = await executeAction(
      deviceId,
      endpointId,
      action: 'set_power',
      value: enabled,
    );
    return EndpointPowerResult(
      outcome: result.outcome,
      changed: result.changed,
      observedPower: result.observedValue is bool
          ? result.observedValue as bool
          : null,
      observedQuality: result.observedQuality,
      observedAt: result.observedAt,
      errorCode: result.errorCode,
      errorDetail: result.errorDetail,
      responseParsed: result.responseParsed,
    );
  }

  @override
  Future<CapabilityActionResult> executeAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  }) async {
    final response = await _api.endpointAction(
      deviceId,
      endpointId,
      action: action,
      value: value,
    );
    final capability = _actionCapabilities[action];
    // The live backend answers 200 with a literal null body until the typed
    // result DTO ships: the command was accepted but nothing was confirmed.
    if (response == null) {
      return CapabilityActionResult(
        action: action,
        capability: capability,
        outcome: 'unconfirmed',
        responseParsed: false,
      );
    }
    final observedState = response['observed_state'];
    final observed = observedState is Map
        ? observedState.cast<String, dynamic>()
        : const <String, dynamic>{};

    Object? observedValue;
    String? observedQuality;
    String? observedAt;
    if (capability != null) {
      final capabilities = observed['capabilities'];
      final entry = capabilities is Map ? capabilities[capability] : null;
      if (entry is Map) {
        final typed = entry.cast<String, dynamic>();
        observedValue = typed['value'];
        final quality = typed['quality'];
        observedQuality = quality is String && quality.isNotEmpty
            ? quality
            : null;
        observedAt = typed['observed_at'] is String
            ? typed['observed_at'] as String
            : null;
      }
    }
    // Legacy compatibility for set_power: early DTOs report the power
    // observation at the top level of observed_state instead of the
    // per-capability map.
    if (observedValue == null &&
        action == 'set_power' &&
        observed['power'] is bool) {
      observedValue = observed['power'];
      final quality = observed['quality'];
      observedQuality = quality is String && quality.isNotEmpty
          ? quality
          : null;
      observedAt = observed['observed_at'] is String
          ? observed['observed_at'] as String
          : null;
    }

    return CapabilityActionResult(
      action: action,
      capability: capability,
      outcome: response['outcome'] is String
          ? response['outcome'] as String
          : 'unconfirmed',
      changed: response['changed'] is bool ? response['changed'] as bool : null,
      observedValue: observedValue,
      observedQuality: observedQuality,
      observedAt: observedAt,
      errorCode: response['error_code'] is String
          ? response['error_code'] as String
          : null,
      errorDetail: response['error_detail'] is String
          ? response['error_detail'] as String
          : null,
    );
  }

  @override
  Future<IdentifyResult> identifyDevice(
    String deviceId, {
    String? endpointId,
  }) async {
    final dto = await _api.identifyDevice(deviceId);
    return IdentifyResult(
      supported: dto['supported'] == true,
      reason: dto['reason'] is String ? dto['reason'] as String : null,
    );
  }

  @override
  Future<PhysicalDevice> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  }) async {
    final dto = await _api.bindEntity(
      deviceId,
      endpointId: endpointId,
      entityId: entityId,
      capability: capability,
      controlledAreaId: controlledAreaId,
    );
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  Future<PhysicalDevice> unbindEntity(String deviceId, String bindingId) async {
    final dto = await _api.unbindEntity(deviceId, bindingId);
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  Future<PhysicalDevice> refreshDevice(String deviceId) async {
    final dto = await _api.refreshDevice(deviceId);
    return _cacheAndReturn(dto, deviceId);
  }

  @override
  Future<List<HomeArea>> listAreas() async {
    final raw = await _api.areas();
    final areas = _parseAreasList(raw);
    return List.unmodifiable(areas);
  }

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    final dto = await _api.createArea(name, aliases: aliases);
    return HomeArea.fromJson(dto);
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    final dto = await _api.updateArea(areaId, name: name, aliases: aliases);
    return HomeArea.fromJson(dto);
  }

  @override
  Future<void> deleteArea(String areaId) async {
    await _api.deleteArea(areaId);
    // The canonical Area collection changed; drop any cached snapshot so the
    // next load reflects the removal.
    _cache.clear();
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) {
    throw UnsupportedError(
      'Identify no está disponible antes de validar el control local.',
    );
  }

  PhysicalDevice _cacheAndReturn(Map<String, dynamic> dto, String deviceId) {
    // Mutation responses come from the same canonical DTO; is_gateway is
    // authoritative, with the same documented compatibility fallback.
    final isGateway =
        dto['is_gateway'] == true ||
        _cache.values.any((device) => device.parentDeviceId == deviceId);
    final gatewayIds = isGateway ? {deviceId} : const <String>{};
    final device = parsePhysicalDevice(dto, gatewayIds: gatewayIds);
    _cache[deviceId] = device;
    return device;
  }

  List<PhysicalDevice> _parseDevices(Map<String, dynamic> inventory) {
    final raw = inventory['devices'];
    if (raw is! List) return const [];
    return raw.map((dto) {
      if (dto is! Map) {
        throw DeviceDtoException(field: 'devices', value: dto);
      }
      final id = dto['device_id'];
      try {
        return parsePhysicalDevice(dto, gatewayIds: const {});
      } on DeviceDtoException catch (error) {
        throw DeviceDtoException(
          field: error.field,
          value: error.value,
          detail: error.detail,
          deviceId: error.deviceId ?? (id is String ? id : null),
        );
      }
    }).toList();
  }

  List<HomeArea> _parseAreasList(Object? raw) {
    if (raw is! List) return const [];
    final result = <HomeArea>[];
    for (final item in raw) {
      if (item is Map) {
        final area = HomeArea.fromJson(item.cast<String, dynamic>());
        if (area.id.isNotEmpty && area.name.isNotEmpty) result.add(area);
      }
    }
    return result;
  }
}

/// Maps a raw DeviceDTO map into a [PhysicalDevice]. Required fields
/// (device_id, provisioning_state, endpoint shapes) throw
/// [DeviceDtoException]; optional fields default instead of throwing.
PhysicalDevice parsePhysicalDevice(
  Map json, {
  required Set<String> gatewayIds,
}) {
  final id = json['device_id'];
  if (id is! String) {
    throw DeviceDtoException(field: 'device_id', value: id);
  }

  final provisioningState = parseProvisioningState(json['provisioning_state']);

  // Tri-state availability: true/false come from the provider, null/absent
  // means "unknown" and must not collapse to offline. The bool field keeps
  // its historical semantics (only true is reachable).
  final onlineValue = json['online']; // bool | null | absent
  final health = onlineValue is bool
      ? (onlineValue ? DeviceHealthState.online : DeviceHealthState.offline)
      : DeviceHealthState.unknown;

  List rawEndpoints;
  final endpointsValue = json['endpoints'];
  if (endpointsValue == null) {
    rawEndpoints = const [];
  } else if (endpointsValue is List) {
    rawEndpoints = endpointsValue;
  } else {
    throw DeviceDtoException(
      field: 'endpoints',
      value: endpointsValue,
      detail: 'Se esperaba una lista de endpoints.',
    );
  }

  final isSubdevice = _parseBoolField(json, 'is_subdevice');
  final isGateway = _parseBoolField(json, 'is_gateway');
  final hasKey = _parseNullableBoolField(json, 'has_key');
  final pendingKey = _parseNullableBoolField(json, 'pending_key');
  final parentDeviceId = json['parent_device_id'] is String
      ? json['parent_device_id'] as String
      : null;

  final endpoints = List<DeviceEndpoint>.unmodifiable(
    rawEndpoints.map(_parseEndpoint),
  );

  return PhysicalDevice(
    id: id,
    name: json['display_name'] is String ? json['display_name'] as String : id,
    kind: gatewayIds.contains(id) ? DeviceKind.gateway : DeviceKind.unknown,
    provider: json['provider_id'] is String
        ? json['provider_id'] as String
        : 'unknown',
    providerDeviceId: '',
    model: json['model'] is String ? json['model'] as String : '',
    manufacturer: json['manufacturer'] is String
        ? json['manufacturer'] as String
        : null,
    gatewayId: isSubdevice ? parentDeviceId : null,
    physicalAreaId: json['physical_area_id'] is String
        ? json['physical_area_id'] as String
        : null,
    provisioningState: provisioningState,
    health: health,
    online: onlineValue == true,
    isSubdevice: isSubdevice,
    isGateway: isGateway,
    parentDeviceId: parentDeviceId,
    lastSeenLabel: null,
    // F2-C/F2-B naming fields (append-only; optional DTOs keep working).
    providerName: json['provider_name'] is String
        ? json['provider_name'] as String
        : null,
    userName: json['user_name'] is String ? json['user_name'] as String : null,
    hasKey: hasKey,
    pendingKey: pendingKey,
    deviceClass: json['device_class'] is String
        ? json['device_class'] as String
        : 'unknown',
    deviceClassSource: json['device_class_source'] is String
        ? json['device_class_source'] as String
        : 'none',
    endpoints: endpoints,
  );
}

/// Defensive boolean field parsing: a missing value falls back to `false`,
/// a real bool passes through, and any malformed value (e.g. a String) is
/// rejected with context instead of being coerced silently.
bool _parseBoolField(Map json, String field) {
  final value = json[field];
  if (value == null) return false;
  if (value is bool) return value;
  throw DeviceDtoException(
    field: field,
    value: value,
    detail: 'Se esperaba un booleano.',
  );
}

/// Nullable variant of [_parseBoolField]: a missing/null value stays unknown
/// (`null`), a real bool passes through, and any malformed value is rejected
/// with context instead of being coerced silently.
bool? _parseNullableBoolField(Map json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is bool) return value;
  throw DeviceDtoException(
    field: field,
    value: value,
    detail: 'Se esperaba un booleano.',
  );
}

DeviceEndpoint _parseEndpoint(Object? value) {
  if (value is! Map) {
    throw DeviceDtoException(
      field: 'endpoints',
      value: value,
      detail: 'Se esperaba un endpoint válido.',
    );
  }
  final id = value['endpoint_id'];
  if (id is! String) {
    throw DeviceDtoException(field: 'endpoint_id', value: id);
  }

  final capabilities = <String>{};
  final capabilityDetails = <String, DeviceCapability>{};
  final rawCapabilities = value['capabilities'];
  if (rawCapabilities is List) {
    for (final capability in rawCapabilities) {
      final detail = parseDeviceCapability(capability);
      if (detail == null) continue;
      capabilities.add(detail.name);
      capabilityDetails[detail.name] = detail;
    }
  }

  final bindingEntity = value['binding_entity'];
  final bindings = bindingEntity is String && bindingEntity.isNotEmpty
      ? <DeviceBinding>[
          DeviceBinding(targetEntityId: bindingEntity, label: bindingEntity),
        ]
      : const <DeviceBinding>[];

  // Observed state is optional and best-effort: malformed values degrade to
  // null instead of failing the whole inventory load.
  final observedState = value['observed_state'];
  final observed = observedState is Map ? observedState : const {};
  final observedPower = observed['power'];
  final observedQuality = observed['quality'];
  final observedAt = observed['observed_at'];

  return DeviceEndpoint(
    id: id,
    name: value['display_name'] is String
        ? value['display_name'] as String
        : id,
    kind: DeviceKind.unknown,
    capabilities: Set.unmodifiable(capabilities),
    capabilityDetails: Map.unmodifiable(capabilityDetails),
    controlledAreaId: value['controlled_area_id'] is String
        ? value['controlled_area_id'] as String
        : null,
    bindings: List.unmodifiable(bindings),
    // F2-C/F2-B naming fields (append-only; optional DTOs keep working).
    userName: value['user_name'] is String
        ? value['user_name'] as String
        : null,
    semanticRole: value['semantic_role'] is String
        ? value['semantic_role'] as String
        : null,
    providerSemanticRole: value['provider_semantic_role'] is String
        ? value['provider_semantic_role'] as String
        : null,
    semanticRoleSource: value['semantic_role_source'] is String
        ? value['semantic_role_source'] as String
        : null,
    stableOrdinal: value['stable_ordinal'] is int
        ? value['stable_ordinal'] as int
        : null,
    displayNameSemantic: value['display_name_semantic'] is String
        ? value['display_name_semantic'] as String
        : null,
    displayNameGlobal: value['display_name_global'] is String
        ? value['display_name_global'] as String
        : null,
    namingSource: parseNamingSource(value['naming_source']),
    observedPower: observedPower is bool ? observedPower : null,
    observedQuality: observedQuality is String && observedQuality.isNotEmpty
        ? observedQuality
        : null,
    observedAt: observedAt is String ? observedAt : null,
    observedCapabilities: parseObservedCapabilities(observed['capabilities']),
  );
}
