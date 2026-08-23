import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_area_overview_page.dart';
import 'package:gamma_app/features/devices/wall_devices_page.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-B final closure — Gap B: real keyboard activation of wall interactive
/// cards. Focus is moved with the actual focus system and activated with real
/// key events; no `tester.tap()` is used in these proofs.
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

  /// Focuses the real button behind an Area card using the actual focus
  /// system, then activates it with [key] and pumps the route transition.
  Future<void> activateAreaCard(
    WidgetTester tester,
    String areaName,
    LogicalKeyboardKey key,
  ) async {
    final textContext = tester.element(find.text(areaName));
    Focus.of(textContext).requestFocus();
    await tester.pump();
    expect(Focus.of(textContext).hasFocus, isTrue);

    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('KEYBOARD-01: Area card activates with Enter', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    await activateAreaCard(tester, 'Cocina', LogicalKeyboardKey.enter);

    expect(find.byType(WallAreaOverviewPage), findsOneWidget);
    expect(find.text('Plafón cocina'), findsOneWidget);
  });

  testWidgets('KEYBOARD-02: Area card activates with Space', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    await activateAreaCard(tester, 'Sala', LogicalKeyboardKey.space);

    expect(find.byType(WallAreaOverviewPage), findsOneWidget);
  });

  testWidgets('KEYBOARD-03: attention card activates with Enter', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    final textContext = tester.element(find.text('Necesita atención'));
    Focus.of(textContext).requestFocus();
    await tester.pump();
    expect(Focus.of(textContext).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Routes to the touch-first wall Devices configuration flow.
    expect(find.byType(WallDevicesPage), findsOneWidget);
  });

  testWidgets('KEYBOARD-04: no mouse/touch dependency in the proof', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    await activateAreaCard(tester, 'Patio', LogicalKeyboardKey.enter);

    expect(find.byType(WallAreaOverviewPage), findsOneWidget);
    // The test performed no tester.tap(); activation came from the key event.
    expect(find.byType(WallAreaOverviewPage), findsOneWidget);
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}
