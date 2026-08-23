import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-B Phase 4: the wall Home renders the room-first Area grid from the
/// canonical projection, with wall-scale tiles and household copy.
void main() {
  Future<void> pumpWallHome(WidgetTester tester, {double width = 1280}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(
          api: _FakeApi(),
          repository: MockDeviceInventoryRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders Mi casa heading and area cards from the projection', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    expect(find.text('Mi casa'), findsOneWidget);
    // Canonical area names appear as room cards.
    for (final name in [
      'Sala',
      'Cocina',
      'Comedor',
      'Recámara',
      'Pasillo',
      'Patio',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    // Counts follow controlled_area_id: Pasillo physically hosts the switch
    // but controls zero endpoints there; Recámara has no devices either.
    expect(find.text('0 controles'), findsNWidgets(2));
    expect(
      find.text('2 controles'),
      findsOneWidget,
    ); // Cocina (plafon + relay_1)
  });

  testWidgets('area cards are large wall tiles with >= 72 dp height', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    final card = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(TextButton),
    );
    expect(card, findsWidgets);
    final first = tester.getSize(card.first);
    expect(first.height, greaterThanOrEqualTo(72));
  });

  testWidgets('empty projection shows the plain empty message', (
    WidgetTester tester,
  ) async {
    final repository = _EmptyRepository();
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

    expect(find.text('Aún no hay habitaciones configuradas'), findsOneWidget);
  });

  testWidgets('medium wall width lays out two useful columns', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester, width: 700);
    final grid = find.byType(GridView);
    expect(grid, findsOneWidget);
    // A 700-logical-px wall (medium, 600..<840) yields 2 columns.
    expect(_gridColumnCount(tester), 2);
  });

  testWidgets('expanded wall width lays out three columns', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester, width: 1280);
    expect(_gridColumnCount(tester), 3);
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}

class _EmptyRepository implements DeviceInventoryRepository {
  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async => const DeviceInventorySnapshot(
    areas: [],
    devices: [],
    gateways: [],
    lastDiscoveryLabel: '',
  );

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
  Future<List<HomeArea>> listAreas() async => [];

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

int _gridColumnCount(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
  final width = tester.getSize(find.byType(GridView)).width;
  final crossAxisCount =
      (width / (delegate.maxCrossAxisExtent + delegate.crossAxisSpacing))
          .ceil()
          .clamp(1, 100);
  return crossAxisCount;
}
