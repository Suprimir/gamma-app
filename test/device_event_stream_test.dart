import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// Nivel 2 client side: while an SSE client is connected the backend sweeps
/// observed states and emits `devices_state_updated` (data `{at, refreshed,
/// scanned}`). The app reloads its canonical snapshot on that event through a
/// passive subscription — no client-side timers or polling.
void main() {
  group('AdaptiveFeatureController live updates', () {
    test('devices_state_updated triggers one canonical reload', () async {
      final repo = _EventStreamFakeRepo();
      final controller = AdaptiveFeatureController(repo);

      await controller.loadDevices();
      expect(repo.loadCount, 1);

      repo.emit('devices_state_updated', {
        'at': '2026-09-13T00:00:00Z',
        'refreshed': 2,
        'scanned': 4,
      });
      await pumpEventQueue();

      expect(repo.loadCount, 2);

      // Every subsequent frame reloads again: the server owns the cadence.
      repo.emit('devices_state_updated', const {});
      await pumpEventQueue();
      expect(repo.loadCount, 3);

      controller.dispose();
      await repo.close();
    });

    test('enveloped frame (core bus) also triggers the reload', () async {
      final repo = _EventStreamFakeRepo();
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      // Raw shape yielded by ApiClient.events() for an enveloped payload: the
      // real name/payload live one level deeper under `data`.
      repo.emitEnvelope({
        'id': 'evt_1',
        'event': 'devices_state_updated',
        'data': {'at': '2026-09-13T00:00:00Z', 'refreshed': 1, 'scanned': 1},
        'timestamp': 1234,
      });
      await pumpEventQueue();

      expect(repo.loadCount, 2);

      controller.dispose();
      await repo.close();
    });

    test('other events never reload the snapshot', () async {
      final repo = _EventStreamFakeRepo();
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();

      repo.emit('voice_finished', {'ok': true});
      repo.emit('status_updated', {'ok': true});
      await pumpEventQueue();

      expect(repo.loadCount, 1);

      controller.dispose();
      await repo.close();
    });

    test('dispose cancels the subscription and ignores late frames', () async {
      final repo = _EventStreamFakeRepo();
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      expect(repo.hasListener, isTrue);

      controller.dispose();
      await pumpEventQueue();
      expect(repo.hasListener, isFalse);

      repo.emit('devices_state_updated', const {});
      await pumpEventQueue();

      expect(repo.loadCount, 1);
      await repo.close();
    });

    test('plain fakes without the interface never subscribe', () async {
      final repo = _PlainFakeRepo();
      final controller = AdaptiveFeatureController(repo);

      expect(asDeviceEventStreamRepository(repo), isNull);

      await controller.loadDevices();
      await pumpEventQueue();

      expect(repo.loadCount, 1);
      expect(controller.snapshot, isNotNull);
      controller.dispose();
    });
  });

  group('WallPanelHomePage live updates', () {
    testWidgets('devices_state_updated reloads the wall snapshot', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _EventStreamFakeRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: WallPanelHomePage(api: _FakeApi(), repository: repo),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.loadCount, 1);

      repo.emit('devices_state_updated', {'refreshed': 1, 'scanned': 1});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(repo.loadCount, 2);

      // Unmount cancels the subscription: no pending timers, no late frames.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(repo.hasListener, isFalse);
    });

    testWidgets('plain wall fakes stay subscription-free', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _PlainFakeRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: WallPanelHomePage(api: _FakeApi(), repository: repo),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(repo.loadCount, 1);
      // No timers or subscriptions exist: the test framework would fail on a
      // pending timer at teardown.
      await tester.pump(const Duration(seconds: 5));
      expect(repo.loadCount, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}

const _eventStreamSnapshot = DeviceInventorySnapshot(
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

/// Plain inventory fake without the live-update surface: the controller must
/// never subscribe to it (no timers, no behavior change).
class _PlainFakeRepo implements DeviceInventoryRepository {
  int loadCount = 0;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCount++;
    return _eventStreamSnapshot;
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

/// Inventory fake that opts into [DeviceEventStreamRepository] with a
/// broadcast controller, mirroring the segregated pattern used by the sweep
/// fake in `device_refresh_lifecycle_test.dart`.
class _EventStreamFakeRepo extends _PlainFakeRepo
    implements DeviceEventStreamRepository {
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  bool get hasListener => _events.hasListener;

  @override
  Stream<Map<String, dynamic>> deviceEvents() => _events.stream;

  /// Pushes one raw frame in the shape yielded by `ApiClient.events()`.
  void emit(String name, Map<String, dynamic> data) {
    _events.add({'event': name, 'data': data});
  }

  /// Pushes a raw bus envelope as the stream frame (production nesting).
  void emitEnvelope(Map<String, dynamic> envelope) {
    _events.add({'event': envelope['event'], 'data': envelope});
  }

  Future<void> close() => _events.close();
}
