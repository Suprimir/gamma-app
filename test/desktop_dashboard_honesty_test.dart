import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/dashboard/desktop_dashboard_page.dart';

/// Widget coverage for the desktop home honesty rules:
/// - a failed backend never renders the in-memory mock inventory;
/// - the camera "en línea" count/dot come from `/cameras/status`, and a
///   failed status call degrades to '—' instead of a fabricated green.
void main() {
  setUp(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDashboard(WidgetTester tester, ApiClient api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DesktopDashboardPage(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
  }

  testWidgets('backend failure shows the error state, never mock devices', (
    tester,
  ) async {
    await pumpDashboard(tester, _FakeDashboardApi(inventoryFails: true));

    expect(find.text('No se pudo cargar el inicio'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    // Mock-only inventory name: it must never reach production surfaces.
    expect(find.text('Interruptor triple'), findsNothing);
    expect(find.text('Plafón cocina'), findsNothing);
  });

  testWidgets('camera online count comes from /cameras/status', (tester) async {
    await pumpDashboard(
      tester,
      _FakeDashboardApi(
        cameraItems: const [
          {'camera_id': 'cam_1', 'name': 'Patio'},
          {'camera_id': 'cam_2', 'name': 'Sala'},
        ],
        cameraStatuses: const [
          {'camera_id': 'cam_1', 'online': true},
          {'camera_id': 'cam_2', 'online': false},
        ],
      ),
    );

    // Two configured cameras, one explicitly online: the legacy
    // `camera['enabled']` fallback would have counted both.
    expect(find.text('1 en línea'), findsOneWidget);
    expect(find.text('Cámaras conectadas'), findsOneWidget);
    // The green pill is backed by the online status, not by configuration.
    expect(find.text('2 en línea'), findsNothing);
  });

  testWidgets('failed camera status shows an unknown neutral count', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      _FakeDashboardApi(
        cameraItems: const [
          {'camera_id': 'cam_1', 'name': 'Patio'},
          {'camera_id': 'cam_2', 'name': 'Sala'},
        ],
        cameraStatusFails: true,
      ),
    );

    expect(find.text('— en línea'), findsOneWidget);
    expect(find.text('—'), findsWidgets); // status card camera row
    expect(find.text('2 en línea'), findsNothing);
  });
}

class _FakeDashboardApi extends ApiClient {
  _FakeDashboardApi({
    this.inventoryFails = false,
    this.cameraStatusFails = false,
    this.cameraItems = const [],
    this.cameraStatuses = const [],
  }) : super(baseUrl: 'http://127.0.0.1:8420');

  final bool inventoryFails;
  final bool cameraStatusFails;
  final List<Map<String, dynamic>> cameraItems;
  final List<Map<String, dynamic>> cameraStatuses;

  @override
  Future<Map<String, dynamic>> deviceInventory({bool pending = false}) async {
    if (inventoryFails) throw StateError('backend offline');
    return {'devices': []};
  }

  @override
  Future<Map<String, dynamic>> catalog() async {
    if (inventoryFails) throw StateError('backend offline');
    return {'locations': [], 'routines': [], 'device_count': 0, 'version': 1};
  }

  @override
  Future<Map<String, dynamic>> deviceProviderHealth() async {
    if (inventoryFails) throw StateError('backend offline');
    return {'providers': []};
  }

  @override
  Future<List<Map<String, dynamic>>> areas() async {
    if (inventoryFails) throw StateError('backend offline');
    return const [];
  }

  @override
  Future<({List<Map<String, dynamic>> cameras, bool enabled})>
  cameraModule() async => (cameras: cameraItems, enabled: true);

  @override
  Future<Map<String, dynamic>> cameraStatus() async {
    if (cameraStatusFails) throw StateError('camera status offline');
    return {'statuses': cameraStatuses};
  }

  @override
  Future<List<Map<String, dynamic>>> routines() async => const [];

  @override
  Future<Map<String, dynamic>> spotifySettings() async => const {
    'authenticated': false,
  };

  @override
  Future<Map<String, dynamic>> spotifyPlaylists({int limit = 50}) async =>
      const {'playlists': []};
}
