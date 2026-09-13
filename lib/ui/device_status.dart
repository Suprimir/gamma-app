import 'package:flutter/material.dart';

import '../data/api_client.dart';
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

/// Household Spanish label for an endpoint's confirmed power display state.
String endpointPowerLabel(PowerDisplayState state) => switch (state) {
  PowerDisplayState.on => 'Encendido',
  PowerDisplayState.off => 'Apagado',
  PowerDisplayState.unknown => 'Sin datos',
};

/// Household availability label for device details: connectivity language
/// instead of the power vocabulary used by list rows. Sleeping keeps the
/// wall wording ('En espera'); an unvalidated state is never invented as a
/// failure ('Sin datos').
String deviceConnectionLabel(DeviceHealthState health) => switch (health) {
  DeviceHealthState.online => 'En línea',
  DeviceHealthState.offline ||
  DeviceHealthState.unreachable ||
  DeviceHealthState.authError => 'Sin acceso',
  DeviceHealthState.sleeping => 'En espera',
  DeviceHealthState.unknown => 'Sin datos',
};

/// Household name for one channel: the GAMMA user name wins, then the
/// backend-computed display name; a stable ordinal is the last fallback.
String endpointChannelName(DeviceEndpoint endpoint) {
  final userName = endpoint.userName?.trim();
  if (userName != null && userName.isNotEmpty) return userName;
  final displayName = endpoint.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final ordinal = endpoint.stableOrdinal;
  return ordinal == null ? 'Canal' : 'Canal ${ordinal + 1}';
}

/// Joined user-named power channels for a device card subtitle: up to two
/// names separated by ' · ', with ' +N' when more named channels remain.
/// Null when the device exposes fewer than two power channels or no channel
/// carries a user name yet (cards then keep their generic control count).
String? powerChannelNamesSummary(PhysicalDevice device) {
  final channels = powerEndpoints(device);
  if (channels.length <= 1) return null;
  final names = <String>[];
  for (final endpoint in channels) {
    final name = endpoint.userName?.trim();
    if (name != null && name.isNotEmpty) names.add(name);
  }
  if (names.isEmpty) return null;
  final shown = names.take(2).join(' · ');
  final remaining = names.length - 2;
  return remaining > 0 ? '$shown +$remaining' : shown;
}

/// One power channel resolved with its owning device. The channel is the
/// control unit; the device keeps its identity (card/detail).
typedef PowerChannel = ({PhysicalDevice device, DeviceEndpoint endpoint});

/// A named bucket of channels rendered as one 'Controles' group.
typedef PowerChannelGroup = ({String name, List<PowerChannel> channels});

/// Effective area id of a channel: the endpoint-controlled area wins over the
/// device's physical area (one channel can command a different room).
String? powerChannelAreaId(PowerChannel channel) =>
    channel.endpoint.controlledAreaId ?? channel.device.physicalAreaId;

/// Every power channel exposed by [devices], in canonical order.
List<PowerChannel> powerChannelsOf(Iterable<PhysicalDevice> devices) => [
  for (final device in devices)
    for (final endpoint in device.endpoints)
      if (hasPowerCapability(endpoint)) (device: device, endpoint: endpoint),
];

/// Groups [channels] by effective area name, keeping the [areas] grid order
/// and leaving 'Sin ubicación' last. Unknown area ids keep first-seen order
/// between the known areas and the no-area bucket, so they are never hidden
/// under the wrong room.
List<PowerChannelGroup> groupPowerChannels(
  List<PowerChannel> channels,
  List<HomeArea> areas,
) {
  final nameById = {for (final area in areas) area.id: area.name};
  final grouped = <String?, List<PowerChannel>>{};
  for (final channel in channels) {
    grouped.putIfAbsent(powerChannelAreaId(channel), () => []).add(channel);
  }
  final groups = <PowerChannelGroup>[];
  for (final area in areas) {
    final bucket = grouped.remove(area.id);
    if (bucket != null) groups.add((name: area.name, channels: bucket));
  }
  for (final id in grouped.keys.whereType<String>().toList()) {
    final bucket = grouped.remove(id);
    if (bucket != null) {
      groups.add((name: nameById[id] ?? id, channels: bucket));
    }
  }
  final withoutArea = grouped.remove(null);
  if (withoutArea != null) {
    groups.add((name: 'Sin ubicación', channels: withoutArea));
  }
  return groups;
}

/// Compact read-only chip with one endpoint's confirmed power state
/// ('Encendido' / 'Apagado' / 'Sin datos'). Renders nothing when the endpoint
/// exposes no power channel. [onColor]/[offColor] let each surface keep its
/// own palette (mobile/desktop status colors, wall green/red).
class EndpointPowerBadge extends StatelessWidget {
  const EndpointPowerBadge({
    super.key,
    required this.endpoint,
    this.onColor = AppColors.statusEncendido,
    this.offColor = AppColors.statusApagado,
    this.fontSize = 11.5,
  });

  final DeviceEndpoint endpoint;
  final Color onColor;
  final Color offColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (!hasPowerCapability(endpoint)) return const SizedBox.shrink();
    final state = endpointPowerDisplayState(endpoint);
    final color = switch (state) {
      PowerDisplayState.on => onColor,
      PowerDisplayState.off => offColor,
      PowerDisplayState.unknown => AppColors.textFaint,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          endpointPowerLabel(state),
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Subtle 'Sin credenciales' chip for device detail headers: shown while the
/// provider still has credential setup pending (`pending_key == true`).
/// Callers gate it on the device flag; devices with credentials render
/// nothing.
class PendingCredentialsBadge extends StatelessWidget {
  const PendingCredentialsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.key_off_outlined, size: 13, color: AppColors.textDim),
          SizedBox(width: 4),
          Text(
            'Sin credenciales',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Household Spanish copy for a canonical endpoint power outcome.
/// [requested] is the value the user asked for (only used on success).
String powerOutcomeMessage(
  EndpointPowerResult result, {
  required bool requested,
}) {
  return switch (result.outcome) {
    'SUCCESS' => requested ? 'Encendido' : 'Apagado',
    'NO_CHANGE' => 'Sin cambios',
    'EXECUTION_DISABLED' => 'Escritura deshabilitada en el modo actual',
    'UNSUPPORTED' => 'El canal no soporta encendido',
    'UNAVAILABLE' => 'Dispositivo no disponible',
    'TIMEOUT' => 'Sin respuesta del dispositivo',
    'FAILED' => 'No se pudo ejecutar la acción',
    'unconfirmed' => 'Orden enviada — sin confirmación del dispositivo',
    _ => 'No se pudo ejecutar la acción',
  };
}

/// Short, honest copy for a thrown power-command failure.
String powerFailureMessage(Object error) {
  final detail = switch (error) {
    ApiException(:final statusCode) => 'error del servidor ($statusCode)',
    UnsupportedError(:final message) => message,
    _ => error.toString(),
  };
  return 'No se pudo ejecutar: $detail';
}

/// Runs identify through the segregated command layer when the repository
/// supports it; otherwise keeps the legacy [DeviceInventoryRepository.identify]
/// fallback for plain fakes and reports a plain success.
///
/// The command-layer [IdentifyResult] is returned as-is so call sites can
/// render the honest provider answer (`supported == false`) instead of
/// fabricating success. Failures propagate unchanged.
Future<IdentifyResult> identifyDeviceWithFallback(
  DeviceInventoryRepository repository,
  String deviceId, {
  String? endpointId,
}) async {
  final commands = asDeviceCommandRepository(repository);
  if (commands != null) {
    return commands.identifyDevice(deviceId, endpointId: endpointId);
  }
  await repository.identify(deviceId, endpointId: endpointId);
  return const IdentifyResult(supported: true);
}

/// Honest copy for an identify the provider does not support, with the
/// provider reason appended when present.
String identifyUnsupportedMessage(IdentifyResult result) {
  final reason = result.reason?.trim();
  return reason == null || reason.isEmpty
      ? 'El proveedor no soporta identificación'
      : 'El proveedor no soporta identificación: $reason';
}

/// Human-safe message for a failed device mutation: the backend `detail` when
/// present, otherwise the server status or the raw error.
String deviceMutationErrorMessage(Object error) {
  final body = error is ApiException ? error.body : null;
  final detail = body is Map ? body['detail'] : null;
  if (detail != null) return detail.toString();
  if (error is ApiException) return 'Error del servidor (${error.statusCode}).';
  return error.toString();
}

/// Legacy static climate modes used before capability descriptors existed.
const legacyClimateModeOptions = <String>['cold', 'heat', 'auto', 'fan'];

/// Options for the climate-mode control. Preference order:
/// 1. the MODE endpoint's descriptor `enumValues` (canonical domain),
/// 2. the backend default domain (`auto|manual`) when commands are available,
/// 3. the legacy static list (mock/fake repositories).
///
/// [selected] is always present in the result: an out-of-domain state is
/// rendered as its own selected chip instead of being silently dropped.
List<String> capabilityModeOptions({
  required DeviceEndpoint? endpoint,
  required bool commandsAvailable,
  required String selected,
}) {
  final enumValues = endpoint?.capabilityDetails['MODE']?.enumValues;
  final options = <String>[
    if (enumValues != null && enumValues.isNotEmpty)
      ...enumValues
    else if (commandsAvailable) ...const ['auto', 'manual'] else
      ...legacyClimateModeOptions,
  ];
  if (!options.contains(selected)) options.add(selected);
  return options;
}

/// Spanish household label for a climate-mode value; raw fallback so an
/// unknown backend mode is never hidden.
String capabilityModeLabel(String mode) => switch (mode) {
  'auto' => 'Auto',
  'manual' => 'Manual',
  'cold' || 'cool' => 'Frío',
  'heat' => 'Calor',
  'fan' => 'Ventilación',
  'dry' => 'Seco',
  _ => mode,
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

/// Channel glyph: the endpoint semantic role wins (same keys as
/// [deviceListIcon]); when the role carries no icon meaning (or is still
/// 'unknown'), the declared capabilities decide so a generically-detected
/// blind/fan/light is still recognizable; a generic toggle is the last
/// resort.
IconData endpointChannelIcon(DeviceEndpoint endpoint) {
  final role = endpoint.semanticRole?.toLowerCase().trim();
  if (role != null && role.isNotEmpty && role != 'unknown') {
    final icon = _roleIcon(role);
    if (icon != null) return icon;
  }
  final caps = <String>{
    for (final c in endpoint.capabilities) c.trim().toUpperCase(),
  };
  if (caps.contains('POSITION') || caps.contains('OPEN_CLOSE')) {
    return Icons.blinds_closed;
  }
  if (caps.contains('SPEED')) return Icons.air;
  if (caps.contains('BRIGHTNESS')) return Icons.lightbulb_outline;
  if (caps.contains('POWER')) return Icons.toggle_on_outlined;
  return Icons.toggle_on_outlined;
}

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
