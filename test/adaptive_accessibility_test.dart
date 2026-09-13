import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/ui/app_colors.dart';
import 'package:gamma_app/features/areas/desktop_areas_page.dart';
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_areas_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';

import 'fixtures/areas_fake_repo.dart';

/// F3-C Phase 10: accessibility of the adaptive surfaces — selected-row
/// semantics, real-keyboard activation with a visible focus border, wall
/// touch targets, no duplicate semantic nodes and labeled form controls.
void main() {
  testWidgets('desktop selected semantics exactly one and moves', (
    tester,
  ) async {
    final repo = _A11yFakeRepo(devices: const [_a11yTriple, _a11yFan]);
    await pumpDesktop(tester, repo);

    final tripleRow = find.byKey(
      const ValueKey('desktop-device-dev_triple_01'),
    );
    final fanRow = find.byKey(const ValueKey('desktop-device-dev_fan_01'));

    await tester.tap(tripleRow);
    await tester.pumpAndSettle();

    expect(_rowSelected(tester, tripleRow, 'Interruptor triple'), isTrue);
    expect(_rowSelected(tester, fanRow, 'Ventilador estudio'), isFalse);
    expect(_selectedRowCount(tester), 1);

    // Switching selection moves the single selected flag.
    await tester.tap(fanRow);
    await tester.pumpAndSettle();

    expect(_rowSelected(tester, fanRow, 'Ventilador estudio'), isTrue);
    expect(_rowSelected(tester, tripleRow, 'Interruptor triple'), isFalse);
    expect(_selectedRowCount(tester), 1);
  });

  testWidgets('area selected semantics exactly one', (tester) async {
    final repo = AreasFakeRepo(
      areas: const [
        HomeArea(id: 'area_SALA', name: 'Sala'),
        HomeArea(id: 'area_COCINA', name: 'Cocina'),
      ],
    );
    await pumpDesktopAreas(tester, repo);

    final salaRow = find.byKey(const ValueKey('desktop-area-area_SALA'));
    final cocinaRow = find.byKey(const ValueKey('desktop-area-area_COCINA'));

    await tester.tap(salaRow);
    await tester.pumpAndSettle();

    expect(_rowSelected(tester, salaRow, 'Sala'), isTrue);
    expect(_rowSelected(tester, cocinaRow, 'Cocina'), isFalse);
    expect(_selectedRowCount(tester), 1);
  });

  testWidgets('real keyboard activation exposes focus border', (tester) async {
    final repo = _A11yFakeRepo(devices: const [_a11yTriple, _a11yFan]);
    final controller = await pumpDesktop(tester, repo);

    await _focusRow(tester, 'dev_triple_01');
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(FocusManager.instance.primaryFocus!.hasFocus, isTrue);
    expect(_rowBorderColor(tester, 'dev_triple_01'), AppColors.accentStrong);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_triple_01');

    await _focusRow(tester, 'dev_fan_01');
    expect(FocusManager.instance.primaryFocus!.hasFocus, isTrue);
    expect(_rowBorderColor(tester, 'dev_fan_01'), AppColors.accentStrong);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(controller.selectedDeviceId, 'dev_fan_01');
  });

  testWidgets('wall device and area cards meet touch targets', (tester) async {
    final repo = _A11yFakeRepo(devices: const [_a11yTriple, _a11yFan]);
    await pumpWallDevices(tester, repo);

    for (final id in ['dev_triple_01', 'dev_fan_01']) {
      final size = tester.getSize(find.byKey(ValueKey('wall-device-$id')));
      expect(size.height, greaterThanOrEqualTo(72), reason: id);
      expect(size.width, greaterThanOrEqualTo(64), reason: id);
    }

    await pumpWallAreas(
      tester,
      AreasFakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala'),
          HomeArea(id: 'area_COCINA', name: 'Cocina'),
        ],
      ),
    );
    for (final id in ['area_SALA', 'area_COCINA']) {
      final size = tester.getSize(find.byKey(ValueKey('wall-area-$id')));
      expect(size.height, greaterThanOrEqualTo(72), reason: id);
      expect(size.width, greaterThanOrEqualTo(64), reason: id);
    }
  });

  testWidgets('single selected node and single label', (tester) async {
    final repo = _A11yFakeRepo(devices: const [_a11yTriple, _a11yFan]);
    await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(selected, findsOneWidget);

    final labeled = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Interruptor triple',
    );
    expect(labeled, findsOneWidget);

    final node = _rowNode(
      tester,
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      'Interruptor triple',
    );
    expect(
      _rowSelected(
        tester,
        find.byKey(const ValueKey('desktop-device-dev_triple_01')),
        'Interruptor triple',
      ),
      isTrue,
    );
    expect(node.label, contains('Interruptor triple'));
  });

  testWidgets('labeled form controls in device detail', (tester) async {
    final repo = _A11yFakeRepo(devices: const [_a11yTriple]);
    await pumpDesktop(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
    );
    await tester.pumpAndSettle();

    // Physical-area selector: the visible label sits above the dropdown in
    // the same Column (never floating or detached).
    final areaSelector = find.byKey(const Key('physical-area-dropdown'));
    final areaLabel = find.descendant(
      of: areaSelector,
      matching: find.text('Ubicación física'),
    );
    final areaDropdown = find.descendant(
      of: areaSelector,
      matching: find.byType(DropdownButtonFormField<String?>),
    );
    expect(areaLabel, findsOneWidget);
    expect(areaDropdown, findsOneWidget);
    expect(
      tester.getRect(areaLabel).bottom,
      lessThanOrEqualTo(tester.getRect(areaDropdown).top),
    );

    // Every role selector ('Qué controla') has its label directly above its
    // dropdown in the same Column.
    final roleLabels = find.text('Qué controla');
    expect(roleLabels, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      final label = roleLabels.at(i);
      final column = find
          .ancestor(of: label, matching: find.byType(Column))
          .first;
      final dropdown = find.descendant(
        of: column,
        matching: find.byType(DropdownButtonFormField<String?>),
      );
      expect(dropdown, findsOneWidget);
      expect(
        tester.getRect(label).bottom,
        lessThanOrEqualTo(tester.getRect(dropdown).top),
      );
    }
  });
}

int _selectedRowCount(WidgetTester tester) {
  return tester
      .widgetList(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      )
      .length;
}

/// The merged semantics node of a row: resolved through the row title text
/// (the keyed row widget's own render object walks up to the focus-only
/// wrapper node, so the label/selected node lives under its text).
SemanticsNode _rowNode(WidgetTester tester, Finder row, String title) {
  return tester.getSemantics(
    find.descendant(of: row, matching: find.text(title)),
  );
}

bool _rowSelected(WidgetTester tester, Finder row, String title) {
  return _rowNode(
        tester,
        row,
        title,
      ).getSemanticsData().flagsCollection.isSelected ==
      Tristate.isTrue;
}

Color _rowBorderColor(WidgetTester tester, String deviceId) {
  final ink = tester.widget<Ink>(
    find
        .descendant(
          of: find.byKey(ValueKey('desktop-device-$deviceId')),
          matching: find.byType(Ink),
        )
        .first,
  );
  final decoration = ink.decoration as BoxDecoration;
  return (decoration.border as Border).top.color;
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
  // The focus-change listener marks the row dirty; a second pump applies the
  // visible focus border.
  await tester.pump();
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, focus.focusNode);
}

Future<AdaptiveFeatureController> pumpDesktop(
  WidgetTester tester,
  DeviceInventoryRepository repo, {
  Size size = const Size(1440, 2200),
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

Future<AdaptiveFeatureController> pumpDesktopAreas(
  WidgetTester tester,
  DeviceInventoryRepository repo, {
  Size size = const Size(1440, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = AdaptiveFeatureController(repo)..loadAreas();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppAdaptiveScope(
          windowClass: AppWindowClass.expanded,
          effectiveSurface: EffectiveAppSurface.desktop,
          controller: AdaptiveSurfaceModeController(),
          child: DesktopAreasPage(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  return controller;
}

Future<void> pumpWallDevices(
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
  // Controles is the wall default; card size proofs live in Dispositivos.
  await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
  await tester.pumpAndSettle();
}

Future<void> pumpWallAreas(
  WidgetTester tester,
  DeviceInventoryRepository repo,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WallAreasPage(
          api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
          repository: repo,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
}

const _a11yTriple = PhysicalDevice(
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

const _a11yFan = PhysicalDevice(
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

class _A11yFakeRepo implements DeviceInventoryRepository {
  _A11yFakeRepo({List<PhysicalDevice>? devices})
    : devices = List.of(devices ?? const []);

  List<HomeArea> areas = const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'comedor', name: 'Comedor'),
    HomeArea(id: 'patio', name: 'Patio'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  List<PhysicalDevice> devices;
  final roleWrites = <(String, String, String?)>[];

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
