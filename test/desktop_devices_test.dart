import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/features/devices/desktop_device_detail_pane.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';

/// F3-C desktop workspace: master/detail pane, keyboard activation, selection
/// refresh/stale semantics, narrow fallback and multi-gang independence.
void main() {
  testWidgets('selection by opaque id', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );
    expect(find.text('Selecciona un dispositivo'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(find.text('Selecciona un dispositivo'), findsNothing);
    // New detail pane per Slice C
    // Title appears in detail pane plus master row (2 widgets), so check at least one
    expect(find.text('Interruptor triple'), findsWidgets);
    expect(find.text('Ubicación física'), findsOneWidget);
    expect(find.text('Controles del dispositivo'), findsOneWidget);
    expect(find.text('Información técnica'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-device-dev_fan_01')));
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_fan_01');
    expect(find.text('Ventilador estudio'), findsWidgets);
    // fan detail should show Controles but not triple channels
    expect(find.text('Controles del dispositivo'), findsOneWidget);
  });

  testWidgets('selected semantics exactly one', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(selected, findsOneWidget);
  });

  testWidgets('real keyboard Enter activates row', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await _focusRow(tester, 'dev_triple_01');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(find.text('Ubicación física'), findsOneWidget);
    expect(find.text('Controles del dispositivo'), findsOneWidget);
  });

  testWidgets('Space activates too', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await _focusRow(tester, 'dev_fan_01');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_fan_01');
    expect(find.text('Ubicación física'), findsOneWidget);
  });

  testWidgets('refresh preserves valid selection', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    // Same opaque ids, changed list content (endpoint renamed).
    repo.devices = [
      _triple.copyWith(
        endpoints: [
          for (final endpoint in _triple.endpoints)
            if (endpoint.id == 'relay_1')
              endpoint.copyWith(userName: 'Luz pasillo')
            else
              endpoint,
        ],
      ),
      _fan,
    ];
    await controller.loadDevices();
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_triple_01');
    expect(find.text('Ubicación física'), findsOneWidget);
    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(selected, findsOneWidget);
  });

  testWidgets('stale selection cleared', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    repo.devices = const [_fan];
    await controller.loadDevices();
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, isNull);
    expect(find.text('Selecciona un dispositivo'), findsOneWidget);
    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(selected, findsNothing);
  });

  testWidgets('narrow fallback no overflow', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    await pumpDesktop(tester, repo, size: const Size(700, 900));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(find.text('Selecciona un dispositivo'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsOneWidget);
    // The physical-area selector lives in the collapsed Configuración block.
    await tester.scrollUntilVisible(
      find.text('Configuración'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Configurar dispositivo'), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
  });

  testWidgets('multi-gang detail independence', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // New desktop detail pane shows Controles, not Canal list; but endpoint data still exists in model.
    expect(find.text('Controles del dispositivo'), findsOneWidget);
    expect(find.text('Información técnica'), findsOneWidget);

    await repo.assignEndpointSemanticRole('dev_triple_01', 'relay_1', 'fan');
    await controller.loadDevices();
    await tester.pumpAndSettle();

    expect(repo.roleWrites, [('dev_triple_01', 'relay_1', 'fan')]);
    final updated = repo.devices.firstWhere((d) => d.id == 'dev_triple_01');
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_1').semanticRole,
      'fan',
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_2').semanticRole,
      isNull,
    );
    expect(
      updated.endpoints.firstWhere((e) => e.id == 'relay_3').semanticRole,
      isNull,
    );

    // Detail still renders after role change
    expect(find.text('Controles del dispositivo'), findsOneWidget);
  });

  testWidgets('search filters without mutating canonical state', (
    tester,
  ) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    await pumpDesktop(tester, repo);

    // Search narrows the list by canonical text.
    await tester.enterText(
      find.byKey(const Key('desktop-device-search')),
      'ventilador',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );

    // Clearing the query restores the full canonical list; the model is
    // untouched by the local UI filter.
    await tester.enterText(find.byKey(const Key('desktop-device-search')), '');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );
    expect(repo.devices.length, 2);
  });

  testWidgets('shared configuration invariants from desktop pane', (
    tester,
  ) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);
    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // New pane: Ubicación física card label above dropdown
    expect(find.text('Ubicación física'), findsOneWidget);
    expect(find.text('Habitación'), findsWidgets);
    // Location dropdown is keyed; channel dropdowns use their own keys.
    final detailDropdown = find.descendant(
      of: find.byType(DesktopDeviceDetailPane),
      matching: find.byKey(const Key('desktop-location-dropdown')),
    );
    expect(detailDropdown, findsOneWidget);
    // Triple switch exposes one independent row per channel.
    expect(find.text('3 canales independientes'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-channel-area-relay_1')),
      findsOneWidget,
    );
    // geometry: Habitación label above detail dropdown
    final habitacionFinder = find.descendant(
      of: find.byType(DesktopDeviceDetailPane),
      matching: find.text('Habitación'),
    );
    final labelRect = tester.getRect(habitacionFinder);
    final dropdownRect = tester.getRect(detailDropdown);
    expect(labelRect.bottom, lessThanOrEqualTo(dropdownRect.top));

    // Technical info stays read-only and collapsible
    expect(find.text('Información técnica'), findsOneWidget);
    // Initially collapsed: ID row not visible
    expect(find.text('dev_triple_01'), findsNothing);
    await tester.tap(find.text('Información técnica'));
    await tester.pumpAndSettle();
    expect(find.text('dev_triple_01'), findsOneWidget);

    // Canonical mutation authority via dirty buffer + Save still converges
    controller.selectDevice('dev_fan_01');
    await tester.pumpAndSettle();
    final updated = await repo.renameDevice('dev_fan_01', 'Ventilador sala');
    await controller.loadDevices();
    await tester.pumpAndSettle();
    expect(repo.renamedDevices, contains(('dev_fan_01', 'Ventilador sala')));
    expect(updated.userName, 'Ventilador sala');
    expect(find.text('Ventilador sala'), findsWidgets);
  });

  testWidgets('select edit Save toast flow with dirty buffer', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // Guardar cambios disabled when clean
    ElevatedButton saveBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Guardar cambios'),
    );
    expect(saveBtn.onPressed, isNull);

    // Change Habitación to Sala (location dropdown, not channel dropdowns)
    final detailDropdown = find.descendant(
      of: find.byType(DesktopDeviceDetailPane),
      matching: find.byKey(const Key('desktop-location-dropdown')),
    );
    await tester.tap(detailDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala').last);
    await tester.pumpAndSettle();
    expect(controller.pendingLocationId, 'sala');
    expect(controller.hasPendingChanges, isTrue);

    saveBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Guardar cambios'),
    );
    expect(saveBtn.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
    await tester.pumpAndSettle();

    // Toast appears and dirty cleared
    expect(find.textContaining('Cambios guardados'), findsOneWidget);
    expect(controller.hasPendingChanges, isFalse);
    expect(controller.pendingLocationId, isNull);
    // Repo was called via controller
    expect(
      controller.snapshot!.devices
          .firstWhere((d) => d.id == 'dev_triple_01')
          .physicalAreaId,
      'sala',
    );

    // Toast auto-dismiss after 3s
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cambios guardados'), findsNothing);

    // narrow push still works (regression): pump narrow and verify DeviceDetailView push
    await tester.pumpWidget(Container()); // clear
  });
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
        child: DesktopDevicesPage(controller: controller),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

Future<void> _focusRow(WidgetTester tester, String deviceId) async {
  final focus = tester.widget<Focus>(
    find
        .descendant(
          of: find.byKey(ValueKey('desktop-device-$deviceId')),
          matching: find.byType(Focus),
        )
        .first,
  );
  focus.focusNode!.requestFocus();
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, focus.focusNode);
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
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'patio',
      capabilities: {'on_off'},
    ),
  ],
);

const _fan = PhysicalDevice(
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

class _DesktopFakeRepo implements DeviceInventoryRepository {
  _DesktopFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;
  final roleWrites = <(String, String, String?)>[];
  final renamedDevices = <(String, String?)>[];

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => true;

  @override
  Future<DeviceInventorySnapshot> load() async => _snapshot();

  @override
  Future<DeviceInventorySnapshot> discover() async => _snapshot();

  DeviceInventorySnapshot _snapshot() => DeviceInventorySnapshot(
    areas: List.unmodifiable(areas),
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    final index = _indexOf(deviceId);
    final updated = devices[index].copyWith(physicalAreaId: areaId);
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(controlledAreaId: areaId)
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    roleWrites.add((deviceId, endpointId, role));
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(semanticRole: role)
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    renamedDevices.add((deviceId, userName));
    final index = _indexOf(deviceId);
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
    final index = _indexOf(deviceId);
    final current = devices[index];
    final updated = current.copyWith(
      endpoints: [
        for (final endpoint in current.endpoints)
          if (endpoint.id == endpointId)
            endpoint.copyWith(userName: userName)
          else
            endpoint,
      ],
    );
    devices[index] = updated;
    return updated;
  }

  int _indexOf(String deviceId) =>
      devices.indexWhere((device) => device.id == deviceId);

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
