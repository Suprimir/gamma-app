import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/settings/settings_page.dart';

class _FakeSettingsApi extends ApiClient {
  _FakeSettingsApi() : super(baseUrl: 'http://test');

  @override
  Future<Map<String, dynamic>> ttsSettings() async => {'edge_voice': ''};

  @override
  Future<Map<String, dynamic>> ttsVoices() async => {'edge': []};

  @override
  Future<Map<String, dynamic>> spotifySettings() async => {
    'authenticated': false,
    'client_id_configured': false,
  };

  @override
  Future<List<Map<String, dynamic>>> modules() async => [];

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(': missing preference leaves value auto', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AdaptiveSurfaceModeController();
    await controller.load();
    expect(controller.value, AppSurfaceMode.auto);
  });

  test(': corrupt stored string falls back to auto', () async {
    SharedPreferences.setMockInitialValues({'adaptive_surface_mode': 'bogus'});
    final controller = AdaptiveSurfaceModeController();
    await controller.load();
    expect(controller.value, AppSurfaceMode.auto);
  });

  test(': setMode persists for a new controller', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AdaptiveSurfaceModeController();
    await controller.setMode(AppSurfaceMode.wallPanel);
    final fresh = AdaptiveSurfaceModeController();
    await fresh.load();
    expect(fresh.value, AppSurfaceMode.wallPanel);
  });

  test(': setMode notifies listeners and updates value', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AdaptiveSurfaceModeController();
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.setMode(AppSurfaceMode.desktop);
    expect(controller.value, AppSurfaceMode.desktop);
    expect(notifications, 1);
  });

  testWidgets('Modo de interfaz selector updates controller', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = AdaptiveSurfaceModeController();
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            api: _FakeSettingsApi(),
            surfaceModeController: controller,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(
      find.text('Panel de pared'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Panel de pared'));
    await tester.pump();

    expect(controller.value, AppSurfaceMode.wallPanel);
    final tile = tester.widget<RadioListTile<AppSurfaceMode>>(
      find.byKey(const ValueKey('surface-mode-wallPanel')),
    );
    expect(tile.value, AppSurfaceMode.wallPanel);
    expect(
      tester
          .widget<RadioGroup<AppSurfaceMode>>(
            find.byType(RadioGroup<AppSurfaceMode>),
          )
          .groupValue,
      AppSurfaceMode.wallPanel,
    );
  });
}
