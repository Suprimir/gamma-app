import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';
import 'package:gamma_app/app/wall_panel_shell.dart';

/// F3-B Phase 10: responsive wall matrix. Wall keeps its own layout at every
/// logical size; desktop at the same width stays desktop; mobile stays mobile.
void main() {
  Future<void> pumpMode(
    WidgetTester tester,
    Size size,
    AppSurfaceMode mode,
  ) async {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'adaptive_surface_mode': mode.name,
    });
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'compact explicit wall preference uses the safe mobile fallback',
    (WidgetTester tester) async {
      await pumpMode(tester, const Size(500, 700), AppSurfaceMode.wallPanel);

      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(WallPanelShell), findsNothing);
      expect(find.byType(WallPanelHomePage), findsNothing);
    },
  );

  testWidgets('medium wall renders the wall shell and home', (
    WidgetTester tester,
  ) async {
    await pumpMode(tester, const Size(800, 600), AppSurfaceMode.wallPanel);

    expect(find.byType(WallPanelShell), findsOneWidget);
    expect(find.byType(WallPanelHomePage), findsOneWidget);
  });

  testWidgets('expanded wall renders the wall shell and home', (
    WidgetTester tester,
  ) async {
    await pumpMode(tester, const Size(1000, 700), AppSurfaceMode.wallPanel);

    expect(find.byType(WallPanelShell), findsOneWidget);
    expect(find.byType(WallPanelHomePage), findsOneWidget);
  });

  testWidgets('large wall renders the wall shell and home', (
    WidgetTester tester,
  ) async {
    await pumpMode(tester, const Size(1920, 1080), AppSurfaceMode.wallPanel);

    expect(find.byType(WallPanelShell), findsOneWidget);
    expect(find.byType(WallPanelHomePage), findsOneWidget);
  });

  testWidgets('desktop at the same width is not a wall layout', (
    WidgetTester tester,
  ) async {
    await pumpMode(tester, const Size(1920, 1080), AppSurfaceMode.desktop);

    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(WallPanelShell), findsNothing);
    expect(find.byType(WallPanelHomePage), findsNothing);
  });

  testWidgets('compact mobile is unaffected', (WidgetTester tester) async {
    await pumpMode(tester, const Size(390, 844), AppSurfaceMode.mobile);

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(WallPanelShell), findsNothing);
    expect(find.byType(WallPanelHomePage), findsNothing);
  });
}
