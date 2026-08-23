import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-B Phase 7: loading, empty, initial error + retry, and refresh failure
/// that keeps the previous snapshot. No mocks as fallback, no raw errors.
void main() {
  testWidgets('initial loading is stable, not blank', (
    WidgetTester tester,
  ) async {
    final repository = _DelayedRepository(const Duration(minutes: 5));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Mi casa'), findsNothing); // content not yet shown

    // Flush the pending delayed load so the fake clock leaves no timer.
    await tester.pump(const Duration(minutes: 6));
  });

  testWidgets('initial failure shows household copy with retry', (
    WidgetTester tester,
  ) async {
    final repository = _FailingRepository();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No se pudo cargar la casa'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    // No raw exception text in the normal UI.
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('retry after initial failure loads the home', (
    WidgetTester tester,
  ) async {
    final repository = _FailingThenOkRepository();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(api: _FakeApi(), repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No se pudo cargar la casa'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No se pudo cargar la casa'), findsNothing);
    expect(find.text('Mi casa'), findsOneWidget);
  });

  testWidgets(
    'AREA-AUTH-03/04: empty home shows the message and no legacy cards',
    (WidgetTester tester) async {
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
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Aún no hay habitaciones configuradas'), findsOneWidget);
      expect(find.text('Ver dispositivos'), findsOneWidget);
      // A canonical empty Area set must never materialize legacy rooms.
      expect(find.text('Sala legacy'), findsNothing);
      expect(find.text('Cocina legacy'), findsNothing);
    },
  );

  testWidgets(
    'refresh failure keeps the previous snapshot and shows a banner',
    (WidgetTester tester) async {
      final repository = _FlakyRepository();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: WallPanelHomePage(api: _FakeApi(), repository: repository),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Mi casa'), findsOneWidget);
      expect(find.text('Sala'), findsOneWidget);

      // Second load fails; the snapshot must remain visible.
      await repository.failNextLoad();
      await tester.fling(find.text('Mi casa'), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Mi casa'), findsOneWidget);
      expect(find.text('Sala'), findsOneWidget);
      expect(find.text('No se pudo actualizar'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    },
  );
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}

const _loadedSnapshot = DeviceInventorySnapshot(
  areas: [HomeArea(id: 'sala', name: 'Sala')],
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

class _DelayedRepository implements DeviceInventoryRepository {
  _DelayedRepository(this.delay);

  final Duration delay;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async {
    await Future<void>.delayed(delay);
    return _loadedSnapshot;
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
  Future<List<HomeArea>> listAreas() async => _loadedSnapshot.areas;

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

class _FailingRepository implements DeviceInventoryRepository {
  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async =>
      throw Exception('SocketException: connection refused');

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

class _FailingThenOkRepository extends _FailingRepository {
  var _calls = 0;

  @override
  Future<DeviceInventorySnapshot> load() async {
    _calls++;
    if (_calls == 1) return super.load();
    return _loadedSnapshot;
  }
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

class _FlakyRepository implements DeviceInventoryRepository {
  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  var _failNext = false;

  Future<void> failNextLoad() async => _failNext = true;

  @override
  Future<DeviceInventorySnapshot> load() async {
    if (_failNext) {
      _failNext = false;
      throw Exception('refresh failed');
    }
    return _loadedSnapshot;
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
  Future<List<HomeArea>> listAreas() async => _loadedSnapshot.areas;

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
