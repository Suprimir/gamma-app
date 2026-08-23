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

@immutable
class DeviceEndpoint {
  const DeviceEndpoint({
    required this.id,
    required this.name,
    required this.kind,
    required this.capabilities,
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
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final Set<String> capabilities;
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

  String get displayName => displayNameSemantic ?? name;

  /// True when the user explicitly configured the effective semantic role.
  bool get isUserConfiguredRole => semanticRoleSource == 'user';

  DeviceEndpoint copyWith({
    String? name,
    DeviceKind? kind,
    Set<String>? capabilities,
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
  }) {
    return DeviceEndpoint(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      capabilities: capabilities ?? this.capabilities,
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
    this.deviceClass = 'unknown',
    this.deviceClassSource = 'none',
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
  final String deviceClass;
  final String deviceClassSource;

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
    String? deviceClass,
    String? deviceClassSource,
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
      deviceClass: deviceClass ?? this.deviceClass,
      deviceClassSource: deviceClassSource ?? this.deviceClassSource,
    );
  }
}

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

  List<PhysicalDevice> get unassigned =>
      userDevices.where((d) => d.needsConfiguration).toList();

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
