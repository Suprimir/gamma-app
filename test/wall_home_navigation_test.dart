import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-B Phases 5-6: Area card tap opens a safe read-only overview; attention
/// routes to the existing Devices flow with household copy.
void main() {
  Future<void> pumpWallHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
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

  testWidgets('tapping an Area card opens the read-only overview', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    final areaCard = find.byKey(const ValueKey('wall-area-cocina'));
    await tester.ensureVisible(areaCard);
    await tester.tap(areaCard);
    // The wall home keeps a continuous idle animation, so transitions use
    // bounded pumps instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The card opens the wall action menu; 'Ver dispositivos' drills into the
    // touch-first wall devices list for that area.
    expect(find.text('Ver dispositivos'), findsOneWidget);
    await tester.tap(find.text('Ver dispositivos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(WallDevicesPage), findsOneWidget);
    // Canonical control display names from the projection.
    expect(find.text('Plafón cocina'), findsOneWidget);
    expect(find.text('Luz cocina'), findsOneWidget);
    // The list stays filtered to the selected area.
    expect(find.text('Cocina'), findsWidgets);
  });

  testWidgets('overview has an obvious back path to home', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    final areaCard = find.byKey(const ValueKey('wall-area-cocina'));
    await tester.ensureVisible(areaCard);
    await tester.tap(areaCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ver dispositivos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WallDevicesPage), findsOneWidget);

    await tester.tap(find.text('Volver'));
    // No pumpAndSettle here: the wall home orb breathes forever by design,
    // so settle never completes. Fixed pumps cover the pop transition.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WallDevicesPage), findsNothing);
    expect(find.text('Mi casa'), findsOneWidget);
  });

  testWidgets(
    'attention card shows plural household copy and routes to Devices',
    (WidgetTester tester) async {
      await pumpWallHome(tester);

      expect(find.text('Necesita atención'), findsOneWidget);
      expect(find.text('3 dispositivos por configurar'), findsOneWidget);

      await tester.tap(find.text('Necesita atención'));
      await tester.pumpAndSettle();

      // Touch-first wall Devices flow receives the tap.
      expect(find.byType(WallDevicesPage), findsOneWidget);
    },
  );

  testWidgets('attention is hidden when nothing needs configuration', (
    WidgetTester tester,
  ) async {
    final repository = _ConfiguredOnlyRepository();
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

    expect(find.text('Necesita atención'), findsNothing);
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}

/// Everything configured: no pending devices, so no attention card.
class _ConfiguredOnlyRepository implements DeviceInventoryRepository {
  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async {
    return DeviceInventorySnapshot(
      areas: const [HomeArea(id: 'sala', name: 'Sala')],
      devices: [
        const PhysicalDevice(
          id: 'dev_ok',
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
      gateways: const [],
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
