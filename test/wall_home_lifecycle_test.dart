import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_home_clock.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-B Phase 11: lifecycle/performance hardening. Wall display may run
/// continuously, so the clock must be isolated and nothing else may rebuild
/// or poll on a timer.
void main() {
  testWidgets('clock tick does not rebuild the wall home body', (
    WidgetTester tester,
  ) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final gridBefore = tester.widget<GridView>(find.byType(GridView));
    // Tick the clock a minute forward: the content widget must not be
    // recreated (only the clock subtree rebuilds).
    await tester.pump(const Duration(minutes: 1));
    final gridAfter = tester.widget<GridView>(find.byType(GridView));
    expect(identical(gridBefore, gridAfter), isTrue);
  });

  testWidgets('initial load issues exactly one repository call', (
    WidgetTester tester,
  ) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.loadCount, 1);
  });

  testWidgets('area cards use stable identity keys', (
    WidgetTester tester,
  ) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('wall-area-sala')), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-cocina')), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-area-pasillo')), findsOneWidget);
  });

  testWidgets('clock timer is disposed with the page', (
    WidgetTester tester,
  ) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(WallHomeClock), findsOneWidget);

    // Remove the page; the pending minute timer must be cancelled.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}

class _CountingRepository implements DeviceInventoryRepository {
  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  int loadCount = 0;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCount++;
    return const DeviceInventorySnapshot(
      areas: [
        HomeArea(id: 'sala', name: 'Sala'),
        HomeArea(id: 'cocina', name: 'Cocina'),
        HomeArea(id: 'pasillo', name: 'Pasillo'),
      ],
      devices: [
        PhysicalDevice(
          id: 'dev_1',
          name: 'Luz sala',
          kind: DeviceKind.light,
          provider: 'p',
          providerDeviceId: 'pid',
          model: 'm',
          provisioningState: DeviceProvisioningState.configured,
          online: true,
          health: DeviceHealthState.online,
          endpoints: [
            DeviceEndpoint(
              id: 'light',
              name: 'Luz sala',
              kind: DeviceKind.light,
              controlledAreaId: 'sala',
              capabilities: {'on_off'},
            ),
          ],
        ),
      ],
      gateways: [],
      lastDiscoveryLabel: '',
    );
  }

  @override
  Future<DeviceInventorySnapshot> discover() => load();

  @override
  Future<PhysicalDevice> assignPhysicalArea(String deviceId, String? areaId) =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) => throw UnimplementedError();

  @override
  Future<List<HomeArea>> listAreas() async => const [
    HomeArea(id: 'sala', name: 'Sala'),
    HomeArea(id: 'cocina', name: 'Cocina'),
    HomeArea(id: 'pasillo', name: 'Pasillo'),
  ];

  @override
  Future<HomeArea> createArea(String name, {List<String> aliases = const []}) =>
      throw UnimplementedError();

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteArea(String areaId) => throw UnimplementedError();

  @override
  Future<void> identify(String deviceId, {String? endpointId}) =>
      throw UnimplementedError();
}
