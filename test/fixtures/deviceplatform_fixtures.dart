// Sanitized, provider-neutral DevicePlatform DTO fixtures for repository tests.
// Identifiers are generic (gateway_1, device_1, child_1, ...) and contain no
// real device/account/home data.

const _powerCapability = <String, dynamic>{
  'capability': 'POWER',
  'readable': true,
  'writable': true,
  'range': null,
  'enum_values': null,
  'confidence': 'HIGH',
  'evidence': ['USER_CONFIRMED'],
};

const _unknownCapability = <String, dynamic>{
  'capability': 'SOMETHING_NEW',
  'readable': false,
  'writable': false,
  'range': null,
  'enum_values': null,
  'confidence': 'UNKNOWN',
  'evidence': <String>[],
};

const _relay1Endpoint = <String, dynamic>{
  'endpoint_id': 'relay_1',
  'display_name': 'Canal 1',
  'controlled_area_id': null,
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relay2Endpoint = <String, dynamic>{
  'endpoint_id': 'relay_2',
  'display_name': 'Canal 2',
  'controlled_area_id': null,
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relay3Endpoint = <String, dynamic>{
  'endpoint_id': 'relay_3',
  'display_name': 'Canal 3',
  'controlled_area_id': null,
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _light1Endpoint = <String, dynamic>{
  'endpoint_id': 'light',
  'display_name': 'Luz 1',
  'controlled_area_id': null,
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _light2Endpoint = <String, dynamic>{
  'endpoint_id': 'light',
  'display_name': 'Luz 2',
  'controlled_area_id': null,
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relayCocinaEndpoint = <String, dynamic>{
  'endpoint_id': 'relay_1',
  'display_name': 'Relé cocina',
  'controlled_area_id': 'cocina',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _lightSalaEndpoint = <String, dynamic>{
  'endpoint_id': 'light',
  'display_name': 'Luz sala',
  'controlled_area_id': 'sala',
  'enabled': true,
  'exposed_to_resolver': true,
  'binding_id': 'b_child_4_light_POWER',
  'binding_entity': 'luz_sala',
  'capabilities': [_powerCapability, _unknownCapability],
};

const _gatewayBase = <String, dynamic>{
  'device_id': 'gateway_1',
  'provider_id': 'tuya',
  'display_name': 'Gateway principal',
  'manufacturer': 'MockCo',
  'model': 'GW-1',
  'product_id': null,
  'category': null,
  'physical_area_id': null,
  'parent_device_id': null,
  'is_subdevice': false,
  'is_gateway': true,
  'provisioning_state': 'ENRICHED',
  'enabled': true,
  'endpoints': <Map<String, dynamic>>[],
};

const _directBase = <String, dynamic>{
  'device_id': 'device_1',
  'provider_id': 'tuya',
  'display_name': 'Interruptor triple',
  'manufacturer': 'MockCo',
  'model': 'SW-3G',
  'product_id': null,
  'category': null,
  'physical_area_id': null,
  'parent_device_id': null,
  'is_subdevice': false,
  'is_gateway': false,
  'provisioning_state': 'ENRICHED',
  'enabled': true,
  'endpoints': [_relay1Endpoint, _relay2Endpoint, _relay3Endpoint],
};

const _child1Base = <String, dynamic>{
  'device_id': 'child_1',
  'provider_id': 'tuya',
  'display_name': 'Luz 1',
  'manufacturer': 'MockCo',
  'model': 'BULB-1',
  'product_id': null,
  'category': null,
  'physical_area_id': null,
  'parent_device_id': null,
  'is_subdevice': true,
  'is_gateway': false,
  'provisioning_state': 'ENRICHED',
  'enabled': true,
  'endpoints': [_light1Endpoint],
};

const _child2Base = <String, dynamic>{
  'device_id': 'child_2',
  'provider_id': 'tuya',
  'display_name': 'Luz 2',
  'manufacturer': 'MockCo',
  'model': 'BULB-2',
  'product_id': null,
  'category': null,
  'physical_area_id': null,
  'parent_device_id': null,
  'is_subdevice': true,
  'is_gateway': false,
  'provisioning_state': 'ENRICHED',
  'enabled': true,
  'endpoints': [_light2Endpoint],
};

const _child3Base = <String, dynamic>{
  'device_id': 'child_3',
  'provider_id': 'tuya',
  'display_name': 'Relé cocina',
  'manufacturer': 'MockCo',
  'model': 'SW-1G',
  'product_id': null,
  'category': null,
  'physical_area_id': 'pasillo',
  'parent_device_id': null,
  'is_subdevice': true,
  'is_gateway': false,
  'provisioning_state': 'PARTIALLY_CONFIGURED',
  'enabled': true,
  'endpoints': [_relayCocinaEndpoint],
};

const _child4Base = <String, dynamic>{
  'device_id': 'child_4',
  'provider_id': 'tuya',
  'display_name': 'Luz sala',
  'manufacturer': 'MockCo',
  'model': 'BULB-RGB',
  'product_id': null,
  'category': null,
  'physical_area_id': 'sala',
  'parent_device_id': null,
  'is_subdevice': true,
  'is_gateway': false,
  'provisioning_state': 'CONFIGURED',
  'enabled': true,
  'endpoints': [_lightSalaEndpoint],
};

/// Inventory response matching the REAL pre-LAN Cloud-only state: 1 gateway +
/// 1 direct 3-gang switch + 4 subdevices (5 user-facing devices). Children
/// are known subdevices but their child->parent relation is NOT resolved yet
/// (parent_device_id is null); is_gateway is explicit, not inferred.
const deviceplatformInventoryCloudOnlyJson = <String, dynamic>{
  'devices': [
    _gatewayBase,
    _directBase,
    _child1Base,
    _child2Base,
    _child3Base,
    _child4Base,
  ],
};

/// Post-LAN enriched topology: same six records, children now resolve their
/// parent_device_id to the GAMMA gateway id. The partition must not change
/// just because the relation became resolved.
final Map<String, dynamic> deviceplatformInventoryResolvedJson =
    <String, dynamic>{
      'devices': [
        _gatewayBase,
        _directBase,
        {..._child1Base, 'parent_device_id': 'gateway_1'},
        {..._child2Base, 'parent_device_id': 'gateway_1'},
        {..._child3Base, 'parent_device_id': 'gateway_1'},
        {..._child4Base, 'parent_device_id': 'gateway_1'},
      ],
    };

// Backwards-compatible alias: F1's original fixture was the resolved shape.
final Map<String, dynamic> deviceplatformInventoryJson =
    deviceplatformInventoryResolvedJson;

/// Legacy area catalog reused only as the HomeArea directory.
const deviceplatformCatalogJson = <String, dynamic>{
  'locations': [
    {'name': 'pasillo', 'devices': []},
    {'name': 'cocina', 'devices': []},
    {'name': 'comedor', 'devices': []},
    {'name': 'sala', 'devices': []},
    {'name': 'patio', 'devices': []},
  ],
  'routines': [],
  'device_count': 0,
  'version': 1,
};

/// Provider health map keyed by provider_id.
const deviceplatformHealthJson = <String, dynamic>{
  'tuya': {
    'provider_id': 'tuya',
    'lan_ready': true,
    'cloud_ready': true,
    'status': 'LAN_READY',
    'detail': null,
  },
};

/// Discovery response, provider-scoped counters.
const deviceplatformDiscoveryJson = <String, dynamic>{
  'tuya': {
    'generation': 2,
    'candidates': 6,
    'enriched': 5,
    'new': 4,
    'missing': 0,
  },
};
