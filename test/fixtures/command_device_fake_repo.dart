import 'package:gamma_app/data/device_inventory.dart';

/// Command-aware fake repository for power-command coverage.
///
/// Implements the read-oriented [DeviceInventoryRepository] plus the
/// segregated [DeviceCommandRepository] so surfaces and the controller take
/// the canonical command path. Only the members required by these tests do
/// real work; the rest follow the per-file fake convention and throw
/// [UnimplementedError].
class CommandDeviceFakeRepo
    implements DeviceInventoryRepository, DeviceCommandRepository {
  CommandDeviceFakeRepo({
    List<PhysicalDevice>? devices,
    List<HomeArea>? areas,
    this.powerResult,
    this.powerError,
    this.powerDelay,
    this.actionResult,
    this.actionError,
    this.actionDelay,
  }) : devices = List.of(devices ?? const []),
       areas = areas ?? const [HomeArea(id: 'sala', name: 'Sala')];

  List<PhysicalDevice> devices;
  List<HomeArea> areas;

  /// Result returned by [setEndpointPower]. When null, a confirmed echo of
  /// the requested value is returned.
  EndpointPowerResult? powerResult;

  /// When set, [setEndpointPower] throws it instead of returning a result.
  Object? powerError;

  /// Optional delay before answering a power command.
  Duration? powerDelay;

  /// Recorded `set_power` calls as (deviceId, endpointId, enabled).
  final powerCalls = <(String, String, bool)>[];

  /// Result returned by [executeAction]. When null, a confirmed echo of the
  /// requested value is returned.
  CapabilityActionResult? actionResult;

  /// When set, [executeAction] throws it instead of returning a result.
  Object? actionError;

  /// Per-call error queue for [executeAction]: entries are consumed in order;
  /// a null entry means "this call succeeds". Takes precedence over
  /// [actionError] while non-empty.
  final actionErrorQueue = <Object?>[];

  /// Optional delay before answering an action.
  Duration? actionDelay;

  /// Recorded `executeAction` calls as (deviceId, endpointId, action, value).
  final actionCalls = <(String, String, String, Object)>[];

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
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: List.unmodifiable(areas),
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<DeviceInventorySnapshot> discover() async => load();

  @override
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  ) async {
    powerCalls.add((deviceId, endpointId, enabled));
    final delay = powerDelay;
    if (delay != null) await Future<void>.delayed(delay);
    final error = powerError;
    if (error != null) throw error;
    final result =
        powerResult ??
        EndpointPowerResult(
          outcome: 'SUCCESS',
          changed: true,
          observedPower: enabled,
          observedQuality: 'confirmed',
          observedAt: '2026-09-11T00:00:00Z',
        );
    // Reflect a confirmed observation in the canonical list, so a reload
    // after the command keeps the honest state on every surface.
    if (result.responseParsed &&
        result.observedPower != null &&
        result.observedQuality != null) {
      final index = devices.indexWhere((device) => device.id == deviceId);
      if (index >= 0) {
        final device = devices[index];
        devices[index] = device.copyWith(
          endpoints: [
            for (final endpoint in device.endpoints)
              if (endpoint.id == endpointId)
                endpoint.copyWith(
                  observedPower: result.observedPower,
                  observedQuality: result.observedQuality,
                  observedAt: result.observedAt,
                )
              else
                endpoint,
          ],
        );
      }
    }
    return result;
  }

  @override
  Future<CapabilityActionResult> executeAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  }) async {
    actionCalls.add((deviceId, endpointId, action, value));
    final delay = actionDelay;
    if (delay != null) await Future<void>.delayed(delay);
    Object? error;
    if (actionErrorQueue.isNotEmpty) {
      error = actionErrorQueue.removeAt(0);
    } else {
      error = actionError;
    }
    if (error != null) throw error;
    final result =
        actionResult ??
        CapabilityActionResult(
          action: action,
          capability: _actionCapabilities[action],
          outcome: 'SUCCESS',
          changed: true,
          observedValue: value,
          observedQuality: 'confirmed',
          observedAt: '2026-09-11T00:00:00Z',
        );
    // Reflect a confirmed observation in the canonical list, so a reload
    // after the command keeps the honest state on every surface.
    final capability = result.capability;
    if (result.responseParsed &&
        capability != null &&
        result.observedValue != null &&
        result.observedQuality != null) {
      final index = devices.indexWhere((device) => device.id == deviceId);
      if (index >= 0) {
        final device = devices[index];
        devices[index] = device.copyWith(
          endpoints: [
            for (final endpoint in device.endpoints)
              if (endpoint.id == endpointId)
                endpoint.copyWith(
                  observedCapabilities: Map.unmodifiable({
                    ...endpoint.observedCapabilities,
                    capability: EndpointCapabilityObservation(
                      value: result.observedValue,
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
    }
    return result;
  }

  @override
  Future<IdentifyResult> identifyDevice(
    String deviceId, {
    String? endpointId,
  }) async => const IdentifyResult(supported: false);

  @override
  Future<PhysicalDevice> bindEntity(
    String deviceId, {
    required String endpointId,
    required String entityId,
    required String capability,
    String? controlledAreaId,
  }) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> unbindEntity(
    String deviceId,
    String bindingId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> refreshDevice(String deviceId) async =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    final index = devices.indexWhere((device) => device.id == deviceId);
    final updated = devices[index].copyWith(physicalAreaId: areaId);
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameDevice(
    String deviceId,
    String? userName,
  ) async => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async => throw UnimplementedError();

  @override
  Future<List<HomeArea>> listAreas() async => List.unmodifiable(areas);

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async => throw UnimplementedError();

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteArea(String areaId) async => throw UnimplementedError();

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}
