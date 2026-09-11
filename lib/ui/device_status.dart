import 'package:flutter/material.dart';

import '../data/device_inventory.dart';
import 'app_colors.dart';

/// Health → label mapping per spec: online=Encendido, sleeping=Apagado, others=Desconectado.
String healthToLabel(DeviceHealthState health) => switch (health) {
  DeviceHealthState.online => 'Encendido',
  DeviceHealthState.sleeping => 'Apagado',
  _ => 'Desconectado',
};

/// Health → dot color.
Color healthToColor(DeviceHealthState health) => switch (health) {
  DeviceHealthState.online => AppColors.statusEncendido,
  DeviceHealthState.sleeping => AppColors.statusApagado,
  _ => AppColors.statusDesconectado,
};

/// Kind → icon badge background color.
Color kindBadgeColor(DeviceKind kind) => switch (kind) {
  DeviceKind.light => AppColors.kindLight,
  DeviceKind.switchController => AppColors.kindBlinds,
  DeviceKind.outlet => AppColors.kindBlinds,
  DeviceKind.gateway => AppColors.kindSensorGrey,
  DeviceKind.sensor => AppColors.kindSensorGrey,
  DeviceKind.unknown => AppColors.kindSensorGrey,
};

/// Kind → icon data.
IconData kindIcon(DeviceKind kind) => switch (kind) {
  DeviceKind.light => Icons.lightbulb_outline,
  DeviceKind.switchController => Icons.toggle_on_outlined,
  DeviceKind.outlet => Icons.power_outlined,
  DeviceKind.sensor => Icons.sensors_outlined,
  DeviceKind.gateway => Icons.hub_outlined,
  DeviceKind.unknown => Icons.device_unknown_outlined,
};

/// List-row icon for a concrete device: resolves the effective type from the
/// endpoint semantic role first, then the backend device class, then
/// capabilities (covers generically-detected fans/covers), and only falls
/// back to [kindIcon] when nothing more specific is known. Sensors resolve
/// to what they measure instead of the generic sensor glyph.
IconData deviceListIcon(PhysicalDevice device) {
  String? role;
  for (final endpoint in device.endpoints) {
    final candidate = endpoint.semanticRole?.toLowerCase();
    if (candidate != null && candidate.isNotEmpty) {
      role = candidate;
      break;
    }
  }
  if (role != null && role != 'sensor' && role != 'unknown') {
    final icon = _roleIcon(role);
    if (icon != null) return icon;
  }
  final deviceClass = device.deviceClass.toLowerCase();
  if (deviceClass.isNotEmpty &&
      deviceClass != 'unknown' &&
      deviceClass != 'sensor') {
    final icon = _roleIcon(deviceClass);
    if (icon != null) return icon;
  }
  if (device.kind == DeviceKind.sensor ||
      role == 'sensor' ||
      deviceClass == 'sensor') {
    return _sensorIcon(device);
  }
  final caps = <String>{
    for (final endpoint in device.endpoints)
      for (final c in endpoint.capabilities) c.trim().toUpperCase(),
  };
  if (caps.contains('SPEED')) return Icons.air;
  if (caps.contains('POSITION') || caps.contains('OPEN_CLOSE')) {
    return Icons.blinds_closed;
  }
  return kindIcon(device.kind);
}

/// Effective-type key → glyph. Null when the key carries no icon meaning
/// (sensors are resolved separately by what they measure).
IconData? _roleIcon(String key) => switch (key) {
  'light' => Icons.lightbulb_outline,
  'switch' => Icons.toggle_on_outlined,
  'outlet' => Icons.power_outlined,
  'fan' || 'extractor' => Icons.air,
  'climate' || 'ac' || 'thermostat' => Icons.ac_unit,
  'cover' ||
  'blind' ||
  'blinds' ||
  'shutter' ||
  'curtain' => Icons.blinds_closed,
  _ => null,
};

/// Sensor glyph by what the device measures (from endpoint capabilities).
IconData _sensorIcon(PhysicalDevice device) {
  final caps = <String>{
    for (final endpoint in device.endpoints)
      for (final c in endpoint.capabilities) c.trim().toUpperCase(),
  };
  if (caps.contains('MOTION')) return Icons.directions_run;
  if (caps.contains('TEMPERATURE_READ') || caps.contains('TEMPERATURE')) {
    return Icons.thermostat;
  }
  if (caps.contains('HUMIDITY_READ') || caps.contains('HUMIDITY')) {
    return Icons.water_drop_outlined;
  }
  return Icons.sensors_outlined;
}
