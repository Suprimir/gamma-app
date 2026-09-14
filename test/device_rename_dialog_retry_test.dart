import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

/// Close of the rename-conflict contract on the wall and mobile surfaces: the
/// dialog must stay open on submit failure, render the backend detail inline
/// and keep the typed value so the user never retypes. Only a successful retry
/// closes the dialog and converges the returned canonical device.
void main() {
  testWidgets(
    'wall rename conflict stays open with detail inline and retries',
    (tester) async {
      final repo = _RenameRetryFakeRepo(devices: const [_triple]);
      await _pumpWall(tester, repo);

      await tester.tap(find.byKey(const ValueKey('wall-device-dev_triple_01')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cambiar nombre'));
      await tester.pumpAndSettle();
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Luz');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // The 409 detail is surfaced verbatim inside the still-open dialog and
      // the typed value is preserved for correction.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_RenameRetryFakeRepo.conflictMessage), findsOneWidget);
      expect(tester.widget<TextField>(dialogField).controller!.text, 'Luz');
      expect(find.text('Nombre actualizado'), findsNothing);

      // Correcting in place succeeds: the dialog closes, the repo receives the
      // corrected name and the wall hero converges to it.
      await tester.enterText(dialogField, 'Luz sala');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repo.renameAttempts, [
        ('dev_triple_01', 'Luz'),
        ('dev_triple_01', 'Luz sala'),
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Nombre actualizado'), findsOneWidget);
      expect(find.text('Luz sala'), findsOneWidget);
    },
  );

  testWidgets(
    'mobile device rename conflict stays open with detail inline and retries',
    (tester) async {
      final repo = _RenameRetryFakeRepo(devices: const [_triple]);
      await _pumpMobile(tester, repo);

      await tester.tap(find.byIcon(CupertinoIcons.pencil_outline).first);
      await tester.pumpAndSettle();
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Luz');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // The backend detail stays inline, the typed value survives and the
      // canonical name is not converged by the failed attempt.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_RenameRetryFakeRepo.conflictMessage), findsOneWidget);
      expect(tester.widget<TextField>(dialogField).controller!.text, 'Luz');
      expect(find.text('Nombre actualizado'), findsNothing);

      await tester.enterText(dialogField, 'Luz sala');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repo.renameAttempts, [
        ('dev_triple_01', 'Luz'),
        ('dev_triple_01', 'Luz sala'),
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Nombre actualizado'), findsOneWidget);
      expect(find.text('Luz sala'), findsWidgets);
    },
  );
}

Future<void> _pumpWall(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WallDevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  // Controles is the wall default; the rename contract lives in the device
  // list/detail surface.
  await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
  await tester.pumpAndSettle();
}

Future<void> _pumpMobile(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DevicesPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-devices-list')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Interruptor triple'));
  await tester.pumpAndSettle();
  // Per-channel configuration is collapsed by default; expand it so the
  // rename affordances are built.
  await tester.tap(find.text('Configuración'));
  await tester.pumpAndSettle();
}

const _triple = PhysicalDevice(
  id: 'dev_triple_01',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS0013',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'pasillo',
  endpoints: [
    DeviceEndpoint(
      id: 'relay_1',
      name: 'Canal 1',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'comedor',
      capabilities: {'on_off'},
    ),
  ],
);

/// Fake that rejects the first device rename with the backend duplicate-name
/// conflict and succeeds afterwards.
class _RenameRetryFakeRepo implements DeviceInventoryRepository {
  _RenameRetryFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<PhysicalDevice> devices;

  final renameAttempts = <(String, String?)>[];
  int _deviceRenameAttempts = 0;

  static const conflictMessage =
      "Ya existe otro dispositivo con el nombre 'Luz' en la misma ubicación";

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async => _snapshot();

  @override
  Future<DeviceInventorySnapshot> discover() async => _snapshot();

  DeviceInventorySnapshot _snapshot() => DeviceInventorySnapshot(
    areas: const [
      HomeArea(id: 'sala', name: 'Sala'),
      HomeArea(id: 'comedor', name: 'Comedor'),
      HomeArea(id: 'pasillo', name: 'Pasillo'),
    ],
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    renameAttempts.add((deviceId, userName));
    _deviceRenameAttempts++;
    if (_deviceRenameAttempts == 1) {
      throw ApiException(409, {'detail': conflictMessage});
    }
    final index = devices.indexWhere((device) => device.id == deviceId);
    final updated = devices[index].copyWith(userName: userName);
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<HomeArea>> listAreas() async => const [];

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteArea(String areaId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}
