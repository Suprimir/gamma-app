import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

/// F3-C micro-closure II: RED convergence-race contract. A mutation response
/// (rename / semantic role) resolved by the backend AFTER the user moved the
/// selection must still converge into the shared snapshot. On HEAD
/// applyCanonicalDevice gates on the focused selection, so a response for the
/// previously-selected device is discarded once selection moved — the shared
/// state stays stale until an extra repository load. These tests are RED.
void main() {
  testWidgets('F3C-CONVERGENCE-RACE-01 rename response after selection moved', (
    tester,
  ) async {
    final repo = _RaceFakeRepo(devices: const [_raceTriple, _raceFan]);
    final controller = await pumpDesktop(tester, repo);
    expect(repo.loadCalls, 1);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    // Drive the real rename dialog; the fake holds the response in flight.
    await tester.tap(find.byTooltip('Cambiar nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Luz   Sala',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.pendingMutation, isNotNull);

    // Selection moves to the fan while the rename is still pending.
    controller.selectDevice('dev_fan_01');
    await tester.pump();

    // Backend resolves with the canonical renamed triple.
    final canonical = _raceTriple.copyWith(userName: 'Luz Sala');
    repo.pendingMutation!.complete(canonical);
    await tester.pump();
    await tester.pump();

    // Selection stays on the fan; the rename STILL converges the triple.
    expect(controller.selectedDeviceId, 'dev_fan_01');
    expect(
      controller.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_triple_01')
          .userName,
      'Luz Sala',
    );
    expect(
      controller.snapshot!.devices
          .firstWhere((device) => device.id == 'dev_fan_01')
          .userName,
      isNull,
    );
    // Convergence is not a refetch.
    expect(repo.loadCalls, 1);

    // Reselecting the triple reads the converged value, never the stale one.
    controller.selectDevice('dev_triple_01');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DeviceDetailView),
        matching: find.text('Luz Sala'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'F3C-CONVERGENCE-RACE-02 endpoint role response after selection moved',
    (tester) async {
      final repo = _RaceFakeRepo(devices: const [_raceTriple, _raceFan]);
      final controller = await pumpDesktop(tester, repo);
      expect(repo.loadCalls, 1);

      await tester.tap(
        find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      );
      await tester.pumpAndSettle();
      expect(controller.selectedDeviceId, 'dev_triple_01');

      // Set relay_1's semantic role; the fake holds the aggregate in flight.
      final dropdowns = find.byType(DropdownButtonFormField<String?>);
      expect(dropdowns, findsNWidgets(7));
      await tester.ensureVisible(dropdowns.at(2));
      await tester.tap(dropdowns.at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luz').last);
      await tester.pumpAndSettle();
      expect(repo.pendingMutation, isNotNull);

      // Selection moves to the fan while the role write is still pending.
      controller.selectDevice('dev_fan_01');
      await tester.pump();

      // Backend resolves with the canonical aggregate: relay_1 is now a fan.
      final relayFan = _raceTriple.endpoints.first.copyWith(
        semanticRole: 'fan',
      );
      final aggregate = _raceTriple.copyWith(
        endpoints: [
          for (final endpoint in _raceTriple.endpoints)
            endpoint.id == 'relay_1' ? relayFan : endpoint,
        ],
      );
      repo.pendingMutation!.complete(aggregate);
      await tester.pump();
      await tester.pump();

      // The aggregate converged despite the moved selection; siblings frozen.
      final converged = controller.snapshot!.devices.firstWhere(
        (device) => device.id == 'dev_triple_01',
      );
      expect(
        converged.endpoints.firstWhere((e) => e.id == 'relay_1').semanticRole,
        'fan',
      );
      expect(
        converged.endpoints.firstWhere((e) => e.id == 'relay_2').semanticRole,
        isNull,
      );
      expect(
        converged.endpoints.firstWhere((e) => e.id == 'relay_3').semanticRole,
        isNull,
      );
      expect(controller.selectedDeviceId, 'dev_fan_01');
      expect(repo.loadCalls, 1);

      // Reselecting the triple shows the converged role, not the stale one.
      controller.selectDevice('dev_triple_01');
      await tester.pumpAndSettle();
      final roleDropdowns = find.byType(DropdownButtonFormField<String?>);
      final roleButton = tester.widget<DropdownButton<String?>>(
        find.descendant(
          of: roleDropdowns.at(2),
          matching: find.byType(DropdownButton<String?>),
        ),
      );
      expect(roleButton.value, 'fan');
    },
  );

  testWidgets(
    'F3C-CONVERGENCE-FAILURE-RACE-01 mutation fails after selection moved',
    (tester) async {
      final repo = _RaceFakeRepo(devices: const [_raceTriple, _raceFan]);
      final controller = await pumpDesktop(tester, repo);

      await tester.tap(
        find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      );
      await tester.pumpAndSettle();
      expect(controller.selectedDeviceId, 'dev_triple_01');

      // Start the rename through the repository path the detail dialog uses;
      // the fake holds the response in flight (Completer).
      final mutation = repo.renameDevice('dev_triple_01', 'Luz sala');
      expect(repo.pendingMutation, isNotNull);

      controller.selectDevice('dev_fan_01');
      await tester.pump();

      // Backend rejects with a 422; the error must never fabricate a canonical
      // A' nor clobber the selection.
      repo.pendingMutation!.completeError(
        ApiException(422, {'detail': 'El nombre ya está en uso'}),
      );
      final error = await mutation.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(error, isA<ApiException>());
      await tester.pump();

      expect(controller.selectedDeviceId, 'dev_fan_01');
      expect(
        controller.snapshot!.devices
            .firstWhere((device) => device.id == 'dev_triple_01')
            .userName,
        isNull,
      );
      // Failure path never triggers a reload either.
      expect(repo.loadCalls, 1);
    },
  );
}

Future<AdaptiveFeatureController> pumpDesktop(
  WidgetTester tester,
  DeviceInventoryRepository repo, {
  Size size = const Size(1440, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = AdaptiveFeatureController(repo)..loadDevices();
  await tester.pumpWidget(
    MaterialApp(
      home: AppAdaptiveScope(
        windowClass: AppWindowClass.expanded,
        effectiveSurface: EffectiveAppSurface.desktop,
        controller: AdaptiveSurfaceModeController(),
        child: Scaffold(body: DesktopDevicesPage(controller: controller)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

const _raceTriple = PhysicalDevice(
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
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'patio',
      capabilities: {'on_off'},
    ),
  ],
);

const _raceFan = PhysicalDevice(
  id: 'dev_fan_01',
  name: 'Ventilador estudio',
  kind: DeviceKind.outlet,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS011F',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'pasillo',
  endpoints: [
    DeviceEndpoint(
      id: 'outlet',
      name: 'Ventilador',
      kind: DeviceKind.outlet,
      controlledAreaId: 'pasillo',
      capabilities: {'on_off'},
    ),
  ],
);

/// Fake whose mutation responses are held in flight by a [Completer] so the
/// test can move the selection and only then resolve the canonical response.
/// `load()` never mutates: convergence must come from applyCanonicalDevice.
class _RaceFakeRepo implements DeviceInventoryRepository {
  _RaceFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  final List<PhysicalDevice> devices;
  final List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  int loadCalls = 0;

  /// Completer backing the next rename/role mutation; the test completes it.
  Completer<PhysicalDevice>? pendingMutation;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCalls++;
    return DeviceInventorySnapshot(
      areas: List.unmodifiable(areas),
      devices: List.unmodifiable(devices),
      gateways: const [],
      lastDiscoveryLabel: '',
    );
  }

  @override
  Future<DeviceInventorySnapshot> discover() async => load();

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) {
    pendingMutation = Completer<PhysicalDevice>();
    return pendingMutation!.future;
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) {
    pendingMutation = Completer<PhysicalDevice>();
    return pendingMutation!.future;
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
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
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<HomeArea>> listAreas() async => List.unmodifiable(areas);

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
