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
import 'package:gamma_app/features/devices/desktop_devices_page.dart';
import 'package:gamma_app/app/floating_dock.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

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

/// Fakes the full DevicePlatform HTTP contract the AppShell DevicesPage
/// repository needs: canonical inventory + catalog + provider health + areas.
/// `loadCalls` counts device-inventory fetches (the proxy for "a repository
/// load happened"); `areaCalls` counts /api/v1/areas fetches.
class _FinalDeviceApi extends ApiClient {
  _FinalDeviceApi() : super(baseUrl: 'http://final.test');

  int loadCalls = 0;
  int areaCalls = 0;

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    loadCalls++;
    return {'devices': _inventoryDevices};
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
    return const [
      {'id': 'sala', 'name': 'Sala', 'aliases': <String>[]},
      {'id': 'comedor', 'name': 'Comedor', 'aliases': <String>[]},
      {'id': 'patio', 'name': 'Patio', 'aliases': <String>[]},
      {'id': 'pasillo', 'name': 'Pasillo', 'aliases': <String>[]},
    ];
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
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

/// Canonical AppShell harness: explicit surface mode, linux platform, real
/// AppShell routing through the five destinations. The Devices destination is
/// reached only by tapping the shell (dock or rail), like production.
Future<AdaptiveSurfaceModeController> _pumpShell(
  WidgetTester tester,
  _FinalDeviceApi api,
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

void main() {
  // Explicit modes win regardless of platform, but the canonical AppShell
  // tests pin linux; keep the invariant: reset the override inside the body.
  void useLinuxPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  }

  // Bounded settle: desktop/mobile mount DashboardPage (voice loop), whose
  // media streams never idle; pumpAndSettle would spin until its timeout.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> tapDispositivos(WidgetTester tester) async {
    await tester.tap(_destination('Dispositivos'));
    await settle(tester);
  }

  testWidgets('wall panel top-level dispositivos opens wall devices', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

    await tapDispositivos(tester);
    await tester.pumpAndSettle();

    // The wall surface must mount the touch-first wall page, never the
    // mobile composition or the desktop master/detail. Controles is the wall
    // default; the device cards live in the list view one tap away.
    expect(find.byType(WallDevicesPage), findsOneWidget);
    expect(find.text('ESPACIOS'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wall-devices-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('wall-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wall-device-dev_fan_01')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop top-level dispositivos opens desktop master detail', (
    tester,
  ) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.desktop);

    await tapDispositivos(tester);

    expect(find.byType(DesktopDevicesPage), findsOneWidget);
    expect(find.text('Selecciona un dispositivo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-device-dev_triple_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile top-level dispositivos keeps sequential flow', (
    tester,
  ) async {
    useLinuxPlatform();
    // The square widget-test font renders the active 'Dispositivos' dock pill
    // wider than the dock's fixed cap; a reduced scale keeps this assertion
    // free of test-font overflow without touching production layout.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.mobile);

    await tapDispositivos(tester);

    expect(find.byType(DesktopDevicesPage), findsNothing);
    expect(find.byType(WallDevicesPage), findsNothing);
    // The mobile landing is controls-first: device management hangs off the
    // header entry rather than the retired 'ESPACIOS'/'INFRAESTRUCTURA' grid.
    expect(find.byKey(const ValueKey('open-devices-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-offline-list')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop dispositivos reaches desktop areas', (tester) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.desktop);

    await tapDispositivos(tester);

    // Areas are managed inline from the master list now: the location picker
    // lists the canonical areas with edit/delete and the add entry.
    expect(find.byKey(const Key('desktop-location-filter')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-location-filter')));
    await settle(tester);

    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Agregar área'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wall dispositivos reaches wall areas', (tester) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

    await tapDispositivos(tester);
    await tester.pumpAndSettle();

    // Areas are managed inline from the wall devices page: the location
    // control opens a touch dialog listing the canonical areas with
    // edit/delete actions.
    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();

    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.text('Sala'), findsWidgets);
    expect(find.byTooltip('Editar área'), findsWidgets);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wall top-level does not double-fetch inventory', (tester) async {
    useLinuxPlatform();
    final api = _FinalDeviceApi();
    await _pumpShell(tester, api, AppSurfaceMode.wallPanel);

    // The wall home (index 0) already fetched once; entering Dispositivos
    // mounts exactly ONE controller. Each controller load owns one inventory
    // fetch plus its one-shot bulk state sweep reload, so a single controller
    // adds two; a second, independently-owned controller would add four.
    final before = api.loadCalls;
    await tapDispositivos(tester);
    await tester.pumpAndSettle();

    expect(api.loadCalls, before + 2);

    debugDefaultTargetPlatformOverride = null;
  });
}
