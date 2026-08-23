import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

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
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-device-dev_fan_01')));
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_fan_01');
    final detail = find.byType(DeviceDetailView);
    expect(
      find.descendant(of: detail, matching: find.text('Ventilador estudio')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('Ventilador')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('Canal 1')),
      findsNothing,
    );
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
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    expect(find.text('ENDPOINTS / CANALES'), findsOneWidget);
  });

  testWidgets('Space activates too', (tester) async {
    final repo = _DesktopFakeRepo(devices: const [_triple, _fan]);
    final controller = await pumpDesktop(tester, repo);

    await _focusRow(tester, 'dev_fan_01');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(controller.selectedDeviceId, 'dev_fan_01');
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
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
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
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

    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);

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

    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Canal 3'), findsOneWidget);
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

    // Label above selector geometry (CODESTYLE #5): the area label sits
    // above the selector, never between surfaces.
    expect(find.byKey(const Key('physical-area-dropdown')), findsOneWidget);
    final labelRect = tester.getRect(find.text('Ubicación física'));
    final selector = find.descendant(
      of: find.byKey(const Key('physical-area-dropdown')),
      matching: find.byType(DropdownButtonFormField<String?>),
    );
    expect(selector, findsOneWidget);
    final dropdownRect = tester.getRect(selector);
    expect(labelRect.bottom, lessThanOrEqualTo(dropdownRect.top));

    // DeviceClass stays read-only (no editing control) and independent of
    // SemanticRole: the class label renders as metadata, never as a selector.
    expect(find.text('Tipo de dispositivo'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Tipo de dispositivo'),
        matching: find.byType(DropdownButtonFormField<String?>),
      ),
      findsNothing,
    );

    // Canonical mutation authority: rename writes the request and the UI
    // converges to the canonical DTO returned by the fake.
    controller.selectDevice('dev_fan_01');
    await tester.pumpAndSettle();
    final updated = await repo.renameDevice('dev_fan_01', 'Ventilador sala');
    await controller.loadDevices();
    await tester.pumpAndSettle();
    expect(repo.renamedDevices, contains(('dev_fan_01', 'Ventilador sala')));
    expect(updated.userName, 'Ventilador sala');
    expect(find.text('Ventilador sala'), findsWidgets);
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
