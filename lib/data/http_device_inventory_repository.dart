import 'api_client.dart';
import 'device_inventory.dart';

/// Repository mapping the DevicePlatform HTTP API into typed domain models.
/// Raw JSON stops at this boundary: callers only see [DeviceInventorySnapshot]
/// and [PhysicalDevice].
class HttpDeviceInventoryRepository implements DeviceInventoryRepository {
  HttpDeviceInventoryRepository(this._api);

  final ApiClient _api;

  // Internal cache of the last loaded devices (id -> PhysicalDevice) so
  // mutation returns keep the gateway partition consistent; cleared on load.
  final Map<String, PhysicalDevice> _cache = {};

  @override
  bool get supportsIdentify => false;

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
    health: DeviceHealthState.unknown,
    online: false,
    isSubdevice: isSubdevice,
    isGateway: isGateway,
    parentDeviceId: parentDeviceId,
    lastSeenLabel: null,
    // F2-C/F2-B naming fields (append-only; optional DTOs keep working).
    providerName: json['provider_name'] is String
        ? json['provider_name'] as String
        : null,
    userName: json['user_name'] is String ? json['user_name'] as String : null,
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
  final rawCapabilities = value['capabilities'];
  if (rawCapabilities is List) {
    for (final capability in rawCapabilities) {
      if (capability is Map && capability['capability'] is String) {
        capabilities.add(capability['capability'] as String);
      }
    }
  }

  final bindingEntity = value['binding_entity'];
  final bindings = bindingEntity is String && bindingEntity.isNotEmpty
      ? <DeviceBinding>[
          DeviceBinding(targetEntityId: bindingEntity, label: bindingEntity),
        ]
      : const <DeviceBinding>[];

  return DeviceEndpoint(
    id: id,
    name: value['display_name'] is String
        ? value['display_name'] as String
        : id,
    kind: DeviceKind.unknown,
    capabilities: Set.unmodifiable(capabilities),
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
  );
}
