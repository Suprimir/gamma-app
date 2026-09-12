import 'device_inventory.dart';

/// One-shot notice shown when every executed action answered
/// `EXECUTION_DISABLED` (demo / writes-disabled backend).
const capabilityWritesDisabledNotice =
    'Escritura deshabilitada en el modo actual';

/// One-shot notice shown when every executed action was `unconfirmed`
/// (accepted but no typed response to confirm it).
const capabilityUnconfirmedNotice =
    'Orden enviada — sin confirmación del dispositivo';

/// Executes the pending capability-backed fields of one device against the
/// canonical command surface, in order:
///
/// `brightness` → `set_brightness`, `fanSpeed` (3-level UI) →
/// `set_speed` percent, `climateMode` → `set_mode`, `position` →
/// `set_position`, `colorTemperature` → `set_color_temperature`.
///
/// Each field targets the first writable endpoint exposing its capability;
/// fields whose endpoint is missing are skipped (nothing to command). The
/// returned [PhysicalDevice] carries every confirmed observation merged into
/// the matching endpoint. An [ApiException] rethrows immediately, so callers
/// keep whatever is still pending.
///
/// [onOutcome] receives each executed action outcome (used by callers that
/// combine this batch with their own actions before computing the notice).
Future<({PhysicalDevice device, String? notice})> commitCapabilityFields({
  required DeviceCommandRepository commands,
  required PhysicalDevice device,
  int? brightness,
  int? fanSpeed,
  String? climateMode,
  int? position,
  int? colorTemperature,
  void Function(String outcome)? onOutcome,
}) async {
  var current = device;
  final executed = <String>[];

  Future<void> run(String action, String capability, Object value) async {
    final endpoint = firstEndpointWithCapability(current, capability);
    if (endpoint == null) return;
    final result = await commands.executeAction(
      device.id,
      endpoint.id,
      action: action,
      value: value,
    );
    executed.add(result.outcome);
    onOutcome?.call(result.outcome);
    current = _mergeCapabilityObservation(current, endpoint.id, result);
  }

  if (brightness != null) {
    await run('set_brightness', 'BRIGHTNESS', brightness);
  }
  if (fanSpeed != null) {
    final percent = speedLevelToPercent(fanSpeed);
    await run('set_speed', 'SPEED', percent);
  }
  if (climateMode != null) {
    await run('set_mode', 'MODE', climateMode);
  }
  if (position != null) {
    await run('set_position', 'POSITION', position);
  }
  if (colorTemperature != null) {
    await run('set_color_temperature', 'COLOR_TEMPERATURE', colorTemperature);
  }

  return (device: current, notice: capabilityCommitNotice(executed));
}

/// Truthful one-shot notice for an executed batch: writes-disabled when every
/// outcome was `EXECUTION_DISABLED`, unconfirmed when every outcome was
/// `unconfirmed`, null otherwise (including an empty batch or mixed results).
String? capabilityCommitNotice(List<String> outcomes) {
  if (outcomes.isEmpty) return null;
  if (outcomes.every((outcome) => outcome == 'EXECUTION_DISABLED')) {
    return capabilityWritesDisabledNotice;
  }
  if (outcomes.every((outcome) => outcome == 'unconfirmed')) {
    return capabilityUnconfirmedNotice;
  }
  return null;
}

/// Merges the confirmed observation carried by [result] into the matching
/// endpoint of [device]. Unparsed/missing observations leave the device
/// untouched (never fabricate a value).
PhysicalDevice _mergeCapabilityObservation(
  PhysicalDevice device,
  String endpointId,
  CapabilityActionResult result,
) {
  final capability = result.capability;
  final value = result.observedValue;
  if (!result.responseParsed ||
      capability == null ||
      value == null ||
      result.observedQuality == null) {
    return device;
  }
  return device.copyWith(
    endpoints: [
      for (final endpoint in device.endpoints)
        if (endpoint.id == endpointId)
          endpoint.copyWith(
            observedCapabilities: Map.unmodifiable({
              ...endpoint.observedCapabilities,
              capability: EndpointCapabilityObservation(
                value: value,
                quality: result.observedQuality,
                observedAt: result.observedAt,
              ),
            }),
          )
        else
          endpoint,
    ],
  );
}
