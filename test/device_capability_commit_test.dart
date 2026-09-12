import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_capability_commit.dart';
import 'package:gamma_app/data/device_inventory.dart';

/// Minimal recording command surface for the shared commit helper.
class _RecordingCommands implements DeviceCommandRepository {
  _RecordingCommands({this.resultBuilder, this.errorQueue = const []});

  final CapabilityActionResult Function(String action, Object value)?
  resultBuilder;

  /// Per-call errors consumed in order; a null entry means "this call
  /// succeeds".
  final List<Object?> errorQueue;
  final calls = <(String, String, String, Object)>[];
  var _index = 0;

  static String? _capabilityFor(String action) => const {
    'set_power': 'POWER',
    'set_brightness': 'BRIGHTNESS',
    'set_position': 'POSITION',
    'set_color': 'COLOR',
    'set_color_temperature': 'COLOR_TEMPERATURE',
    'set_speed': 'SPEED',
    'set_mode': 'MODE',
  }[action];

  @override
  Future<CapabilityActionResult> executeAction(
    String deviceId,
    String endpointId, {
    required String action,
    required Object value,
  }) async {
    calls.add((deviceId, endpointId, action, value));
    final index = _index++;
    if (index < errorQueue.length && errorQueue[index] != null) {
      throw errorQueue[index]!;
    }
    final builder = resultBuilder;
    if (builder != null) return builder(action, value);
    return CapabilityActionResult(
      action: action,
      capability: _capabilityFor(action),
      outcome: 'SUCCESS',
      changed: true,
      observedValue: value,
      observedQuality: 'confirmed',
      observedAt: '2026-09-11T00:00:00Z',
    );
  }

  @override
  Future<EndpointPowerResult> setEndpointPower(
    String deviceId,
    String endpointId,
    bool enabled,
  ) async => throw UnimplementedError();

  @override
  Future<IdentifyResult> identifyDevice(
    String deviceId, {
    String? endpointId,
  }) async => throw UnimplementedError();

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
}

const _capDevice = PhysicalDevice(
  id: 'dev_1',
  name: 'Equipo',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'M1',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'BRIGHTNESS', 'COLOR_TEMPERATURE'},
    ),
    DeviceEndpoint(
      id: 'fan',
      name: 'Ventilador',
      kind: DeviceKind.unknown,
      capabilities: {'SPEED'},
    ),
    DeviceEndpoint(
      id: 'mode',
      name: 'Modo',
      kind: DeviceKind.unknown,
      capabilities: {'MODE'},
    ),
    DeviceEndpoint(
      id: 'blind',
      name: 'Persiana',
      kind: DeviceKind.unknown,
      capabilities: {'POSITION'},
    ),
  ],
);

void main() {
  test('executes fields in canonical order with mapped values', () async {
    final commands = _RecordingCommands();

    final result = await commitCapabilityFields(
      commands: commands,
      device: _capDevice,
      brightness: 70,
      fanSpeed: 2,
      climateMode: 'manual',
      position: 40,
      colorTemperature: 30,
    );

    expect(commands.calls, [
      ('dev_1', 'light', 'set_brightness', 70),
      ('dev_1', 'fan', 'set_speed', 67),
      ('dev_1', 'mode', 'set_mode', 'manual'),
      ('dev_1', 'blind', 'set_position', 40),
      ('dev_1', 'light', 'set_color_temperature', 30),
    ]);
    expect(result.notice, isNull);
    final light = result.device.endpoints.firstWhere((e) => e.id == 'light');
    expect(confirmedCapabilityValue(light, 'BRIGHTNESS'), 70);
    expect(confirmedCapabilityValue(light, 'COLOR_TEMPERATURE'), 30);
  });

  test('skips fields whose endpoint is missing', () async {
    final commands = _RecordingCommands();
    final device = _capDevice.copyWith(
      endpoints: const [
        DeviceEndpoint(
          id: 'light',
          name: 'Luz',
          kind: DeviceKind.light,
          capabilities: {'BRIGHTNESS'},
        ),
      ],
    );

    final result = await commitCapabilityFields(
      commands: commands,
      device: device,
      brightness: 50,
      fanSpeed: 2,
      position: 40,
    );

    expect(commands.calls, [('dev_1', 'light', 'set_brightness', 50)]);
    expect(result.device.position, isNull);
  });

  test('skips non-writable descriptors and picks the next endpoint', () async {
    final commands = _RecordingCommands();
    final device = _capDevice.copyWith(
      endpoints: const [
        DeviceEndpoint(
          id: 'readonly',
          name: 'Solo lectura',
          kind: DeviceKind.light,
          capabilities: {'BRIGHTNESS'},
          capabilityDetails: {
            'BRIGHTNESS': DeviceCapability(
              name: 'BRIGHTNESS',
              readable: true,
              writable: false,
            ),
          },
        ),
        DeviceEndpoint(
          id: 'writable',
          name: 'Luz',
          kind: DeviceKind.light,
          capabilities: {'BRIGHTNESS'},
          capabilityDetails: {
            'BRIGHTNESS': DeviceCapability(
              name: 'BRIGHTNESS',
              readable: true,
              writable: true,
            ),
          },
        ),
      ],
    );

    await commitCapabilityFields(
      commands: commands,
      device: device,
      brightness: 50,
    );

    expect(commands.calls, [('dev_1', 'writable', 'set_brightness', 50)]);
  });

  test('rethrows ApiException immediately and stops later fields', () async {
    final commands = _RecordingCommands(
      errorQueue: [
        null,
        ApiException(503, {'detail': 'backend down'}),
      ],
    );

    await expectLater(
      commitCapabilityFields(
        commands: commands,
        device: _capDevice,
        brightness: 70,
        fanSpeed: 2,
        position: 40,
      ),
      throwsA(isA<ApiException>()),
    );

    // Brightness executed, fan speed failed, position never ran.
    expect(commands.calls, hasLength(2));
    expect(commands.calls.last.$3, 'set_speed');
  });

  test('an unparsed response never fabricates an observation', () async {
    final commands = _RecordingCommands(
      resultBuilder: (action, value) => CapabilityActionResult(
        action: action,
        outcome: 'unconfirmed',
        responseParsed: false,
      ),
    );

    final result = await commitCapabilityFields(
      commands: commands,
      device: _capDevice,
      brightness: 70,
    );

    expect(result.device.endpoints.first.observedCapabilities, isEmpty);
    expect(result.notice, capabilityUnconfirmedNotice);
  });

  test('onOutcome reports every executed outcome', () async {
    final commands = _RecordingCommands();
    final outcomes = <String>[];

    await commitCapabilityFields(
      commands: commands,
      device: _capDevice,
      brightness: 70,
      fanSpeed: 2,
      onOutcome: outcomes.add,
    );

    expect(outcomes, ['SUCCESS', 'SUCCESS']);
  });

  test('notice is truthful for disabled, unconfirmed and mixed batches', () {
    expect(capabilityCommitNotice([]), isNull);
    expect(
      capabilityCommitNotice(['EXECUTION_DISABLED', 'EXECUTION_DISABLED']),
      capabilityWritesDisabledNotice,
    );
    expect(
      capabilityCommitNotice(['unconfirmed']),
      capabilityUnconfirmedNotice,
    );
    expect(capabilityCommitNotice(['SUCCESS', 'EXECUTION_DISABLED']), isNull);
    expect(
      capabilityCommitNotice(['EXECUTION_DISABLED', 'unconfirmed']),
      isNull,
    );
  });
}
