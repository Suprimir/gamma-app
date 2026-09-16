import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/app/desktop_drawer.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

const _powerCapability = <String, dynamic>{
  'capability': 'POWER',
  'readable': true,
  'writable': true,
  'range': null,
  'enum_values': null,
  'confidence': 'HIGH',
  'evidence': <String>[],
};

const _relay1 = <String, dynamic>{
  'endpoint_id': 'relay_1',
  'display_name': 'Canal 1',
  'controlled_area_id': 'sala',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relay2 = <String, dynamic>{
  'endpoint_id': 'relay_2',
  'display_name': 'Canal 2',
  'controlled_area_id': 'comedor',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _relay3 = <String, dynamic>{
  'endpoint_id': 'relay_3',
  'display_name': 'Canal 3',
  'controlled_area_id': 'patio',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

const _outletEndpoint = <String, dynamic>{
  'endpoint_id': 'outlet',
  'display_name': 'Ventilador',
  'controlled_area_id': 'pasillo',
  'enabled': true,
  'exposed_to_resolver': false,
  'binding_id': null,
  'binding_entity': null,
  'capabilities': [_powerCapability],
};

/// Canonical inventory fixture: a physical 3-gang switch in Pasillo
/// controlling Sala/Comedor/Patio plus a fan, with area names for all rooms.
const _inventoryDevices = <Map<String, dynamic>>[
  {
    'device_id': 'dev_triple_01',
    'provider_id': 'tuya',
    'display_name': 'Interruptor triple',
    'manufacturer': 'MockCo',
    'model': 'TS0013',
    'product_id': null,
    'category': null,
    'physical_area_id': 'pasillo',
    'parent_device_id': null,
    'is_subdevice': false,
    'is_gateway': false,
    'provisioning_state': 'CONFIGURED',
    'enabled': true,
    'device_class': 'switch',
    'device_class_source': 'provider',
    'endpoints': [_relay1, _relay2, _relay3],
  },
  {
    'device_id': 'dev_fan_01',
    'provider_id': 'tuya',
    'display_name': 'Ventilador estudio',
    'manufacturer': 'MockCo',
    'model': 'TS011F',
    'product_id': null,
    'category': null,
    'physical_area_id': 'pasillo',
    'parent_device_id': null,
    'is_subdevice': false,
    'is_gateway': false,
    'provisioning_state': 'CONFIGURED',
    'enabled': true,
    'device_class': 'outlet',
    'device_class_source': 'provider',
    'endpoints': [_outletEndpoint],
  },
];

const _areaDtos = <Map<String, dynamic>>[
  {'id': 'sala', 'name': 'Sala', 'aliases': <String>[]},
  {'id': 'comedor', 'name': 'Comedor', 'aliases': <String>[]},
  {'id': 'patio', 'name': 'Patio', 'aliases': <String>[]},
  {'id': 'pasillo', 'name': 'Pasillo', 'aliases': <String>[]},
];

/// Fakes the full DevicePlatform HTTP contract the production AppShell
/// repository needs. `inventoryLoadCalls` counts device-inventory fetches —
/// the deterministic proxy for "a repository load happened". `areaCalls`
/// counts area fetches. The same fake serves desktop AND wall content.
class _DeferredDeviceApi extends ApiClient {
  _DeferredDeviceApi() : super(baseUrl: 'http://deferred.test');

  int inventoryLoadCalls = 0;
  int areaCalls = 0;

  List<Map<String, dynamic>> inventory = [
    for (final device in _inventoryDevices) Map<String, dynamic>.of(device),
  ];

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    inventoryLoadCalls++;
    return {
      'devices': [
        for (final device in inventory) Map<String, dynamic>.of(device),
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> catalog() async => {
    'locations': const <Map<String, dynamic>>[],
    'routines': const <Map<String, dynamic>>[],
    'device_count': 0,
    'version': 1,
  };

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async => {
    'tuya': {
      'provider_id': 'tuya',
      'lan_ready': true,
      'cloud_ready': true,
      'status': 'LAN_READY',
      'detail': null,
    },
  };

  @override
  Future<List<Map<String, dynamic>>> areas() async {
    areaCalls++;
    return [for (final area in _areaDtos) area];
  }

  @override
  Future<Map<String, dynamic>> discoverDevices() async {
    return {
      'tuya': {
        'generation': 2,
        'candidates': 2,
        'enriched': 2,
        'new': 0,
        'missing': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> renameDevice(
    String deviceId,
    String? userName,
  ) async {
    final index = inventory.indexWhere((d) => d['device_id'] == deviceId);
    final normalized = userName?.trim().replaceAll(RegExp(r'\s+'), ' ');
    final updated = Map<String, dynamic>.of(inventory[index])
      ..['user_name'] = normalized;
    inventory[index] = updated;
    return updated;
  }

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

/// Canonical AppShell harness: explicit surface mode, linux platform, real
/// AppShell routing through the five destinations.
Future<AdaptiveSurfaceModeController> _pumpShellDeferred(
  WidgetTester tester,
  _DeferredDeviceApi api,
  AppSurfaceMode mode,
) async {
  MediaKit.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AdaptiveSurfaceModeController();
  await controller.load();
  await controller.setMode(mode);
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(api: api, surfaceModeController: controller),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

/// Locates a top-level destination on whichever shell is mounted. The mobile
/// dock only renders a visible `Text` for the active destination and the
/// desktop sidebar is icon-only, so both expose the name on a semantics
/// wrapper; the wall rail still renders every label.
Finder _destination(String label) {
  if (find.byType(FloatingDock).evaluate().isNotEmpty) {
    return find.descendant(
      of: find.byType(FloatingDock),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    );
  }
  if (find.byType(WallPanelShell).evaluate().isNotEmpty) {
    return find.descendant(
      of: find.byKey(const ValueKey('wall-panel-side-rail')),
      matching: find.text(label),
    );
  }
  return find.descendant(
    of: find.byType(DesktopSidebar),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
}

void main() {
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  // Bounded settle: desktop/mobile mount DashboardPage (voice loop), whose
  // media streams never idle; pumpAndSettle would spin until its timeout.
  Future<void> settleDeferred(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  // Taps a top-level destination through whichever shell is mounted.
  Future<void> tapDeferred(WidgetTester tester, String label) async {
    await tester.tap(_destination(label));
    await settleDeferred(tester);
  }

  // Controles is the wall default; the card list is one tap away.
  Future<void> showWallDeviceList(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
    await settleDeferred(tester);
  }

  testWidgets('visited devices offstage wall switch does not crash or load', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _DeferredDeviceApi();
    final surface = await _pumpShellDeferred(
      tester,
      api,
      AppSurfaceMode.desktop,
    );

    // Desktop Home load, then one Devices controller load plus its bulk sweep.
    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, 3);

    // Return to Inicio: Dispositivos stays mounted, now offstage.
    await tapDeferred(tester, 'Inicio');

    // Baseline for the surface switch: only composition may add loads.
    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settleDeferred(tester);
    await settleDeferred(tester);

    // RED on HEAD: the offstage WallDevicesPage reaches `snapshot!` with a
    // null snapshot and throws a null-check TypeError during build.
    expect(tester.takeException(), isNull);

    // Home is the ACTIVE destination on wall, so WallPanelHomePage performs
    // its single active load here; the offstage Devices adds 0.
    expect(api.inventoryLoadCalls, 1);
    expect(find.byType(WallPanelShell), findsOneWidget);

    // Activation loads the wall Devices once (load + bulk sweep).
    final beforeDevices = api.inventoryLoadCalls;
    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls - beforeDevices, 2);
    await showWallDeviceList(tester);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('activation after offstage creation loads exactly once', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _DeferredDeviceApi();
    final surface = await _pumpShellDeferred(
      tester,
      api,
      AppSurfaceMode.desktop,
    );

    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, 3);
    await tapDeferred(tester, 'Inicio');

    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settleDeferred(tester);
    await settleDeferred(tester);

    // RED on HEAD: the offstage wall Devices null-dereferences on build.
    expect(tester.takeException(), isNull);
    expect(api.inventoryLoadCalls, 1);

    // Activation loads the preserved offstage wall Devices once (load +
    // bulk sweep).
    final before = api.inventoryLoadCalls;
    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls - before, 2);
    await showWallDeviceList(tester);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Tap-away/tap-back keeps the loaded Devices controller alive offstage:
    // the Devices controller adds nothing, while the wall Home refreshes once
    // on re-activation by design.
    final frozen = api.inventoryLoadCalls;
    await tapDeferred(tester, 'Inicio');
    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, frozen + 1);
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('rebuilds and resize do not add loads after activation', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _DeferredDeviceApi();
    final surface = await _pumpShellDeferred(
      tester,
      api,
      AppSurfaceMode.desktop,
    );

    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, 3);
    await tapDeferred(tester, 'Inicio');

    api.inventoryLoadCalls = 0;
    await surface.setMode(AppSurfaceMode.wallPanel);
    await settleDeferred(tester);
    await settleDeferred(tester);

    // RED on HEAD: the offstage wall Devices null-dereferences on build.
    expect(tester.takeException(), isNull);
    expect(api.inventoryLoadCalls, 1);

    await tapDeferred(tester, 'Dispositivos');
    expect(api.inventoryLoadCalls, 3);

    // Bare rebuilds add no loads.
    final frozen = api.inventoryLoadCalls;
    await settleDeferred(tester);
    await settleDeferred(tester);
    expect(api.inventoryLoadCalls, frozen);

    // Pure geometry changes (still a non-compact wall panel) add no loads.
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await settleDeferred(tester);
    await settleDeferred(tester);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await settleDeferred(tester);
    await settleDeferred(tester);
    expect(api.inventoryLoadCalls, frozen);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'desktop->wall->desktop->wall keeps canonical state and no duplicate inactive loads',
    (tester) async {
      useLinuxPlatform();
      final api = _DeferredDeviceApi();
      final surface = await _pumpShellDeferred(
        tester,
        api,
        AppSurfaceMode.desktop,
      );

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 3);
      await tapDeferred(tester, 'Inicio');

      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);

      // RED on HEAD: the offstage wall Devices null-dereferences on build.
      expect(tester.takeException(), isNull);
      expect(api.inventoryLoadCalls, 1);

      await tapDeferred(tester, 'Dispositivos');
      expect(api.inventoryLoadCalls, 3);
      await showWallDeviceList(tester);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );

      // Back to desktop: both controllers are already loaded, no new fetch.
      await surface.setMode(AppSurfaceMode.desktop);
      await settleDeferred(tester);
      await settleDeferred(tester);
      expect(api.inventoryLoadCalls, 3);
      expect(tester.takeException(), isNull);

      // Second wall switch with Dispositivos ACTIVE: the fresh wall Devices
      // performs one bounded controller load (load + bulk sweep); the
      // offstage Home adds nothing.
      api.inventoryLoadCalls = 0;
      await surface.setMode(AppSurfaceMode.wallPanel);
      await settleDeferred(tester);
      await settleDeferred(tester);
      expect(api.inventoryLoadCalls, 2);
      await showWallDeviceList(tester);
      expect(
        find.byKey(const ValueKey('wall-device-dev_triple_01')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
