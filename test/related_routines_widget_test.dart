import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/desktop_device_detail_pane.dart';

import 'fixtures/command_device_fake_repo.dart';

/// The desktop "Rutinas relacionadas" card must show a real count from
/// `GET /api/v1/routines` when an API client is available, 'Sin datos' when
/// the fetch fails, and keep the legacy '0 rutinas' when there is no API.
void main() {
  Future<AdaptiveFeatureController> pumpPane(
    WidgetTester tester, {
    ApiClient? api,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = CommandDeviceFakeRepo(devices: const [_paneLight]);
    final controller = AdaptiveFeatureController(repo);
    await controller.loadDevices();
    controller.selectDevice('dev_pane_01');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopDeviceDetailPane(
            device: controller.selectedDevice!,
            areas: controller.snapshot!.areas,
            gateways: controller.snapshot!.gateways,
            controller: controller,
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('counts only routines with a matching canonical device_id', (
    tester,
  ) async {
    final api = _RoutinesApi([
      {
        'id': 'r1',
        'acciones': [
          {'device_id': 'dev_pane_01'},
        ],
      },
      {
        'id': 'r2',
        'acciones': [
          {'device_id': 'dev_other'},
          {'device_id': 'dev_pane_01'},
        ],
      },
      {
        'id': 'r3',
        'acciones': [
          {'device_id': 'dev_other'},
        ],
      },
    ]);

    await pumpPane(tester, api: api);

    expect(find.text('Rutinas relacionadas'), findsOneWidget);
    expect(find.text('2 rutinas'), findsOneWidget);
    expect(find.text('0 rutinas'), findsNothing);
  });

  testWidgets('failed routines fetch shows Sin datos, never a fake zero', (
    tester,
  ) async {
    await pumpPane(tester, api: _RoutinesApi(const [], fail: true));

    expect(find.text('Rutinas relacionadas'), findsOneWidget);
    // 'Sin datos' is also the honest power label, so assert it appears while
    // no count is fabricated.
    expect(find.text('Sin datos'), findsWidgets);
    expect(find.text('0 rutinas'), findsNothing);
    expect(find.text('1 rutina'), findsNothing);
  });

  testWidgets('no api keeps the legacy 0 rutinas rendering', (tester) async {
    await pumpPane(tester);

    expect(find.text('0 rutinas'), findsOneWidget);
  });
}

class _RoutinesApi extends ApiClient {
  _RoutinesApi(this.items, {this.fail = false})
    : super(baseUrl: 'http://127.0.0.1:8420');

  final List<Map<String, dynamic>> items;
  final bool fail;

  @override
  Future<List<Map<String, dynamic>>> routines() async {
    if (fail) throw StateError('routines offline');
    return items;
  }
}

const _paneLight = PhysicalDevice(
  id: 'dev_pane_01',
  name: 'Luz escritorio',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: 'tuya-pane',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);
