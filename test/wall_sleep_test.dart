import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// Wall sleep mode: inactivity shows a FULLSCREEN clock overlay, any tap
/// wakes.
///
/// The overlay is an [OverlayEntry] (not an in-tree fill) so it covers the
/// whole window including the shell side rail — visibility is asserted
/// through presence in the tree plus fullscreen size.
void main() {
  Future<void> pumpSleepyWallHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallPanelHomePage(
          api: _FakeApi(),
          repository: MockDeviceInventoryRepository(),
          idleTimeout: const Duration(seconds: 10),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Finder sleepOverlay() => find.byKey(const ValueKey('wall-sleep-overlay'));

  bool isAsleep(WidgetTester tester) => sleepOverlay().evaluate().isNotEmpty;

  testWidgets('sleep overlay appears after idle timeout and wakes on tap', (
    WidgetTester tester,
  ) async {
    await pumpSleepyWallHome(tester);

    expect(find.text('Mi casa'), findsOneWidget);
    expect(isAsleep(tester), isFalse);

    await tester.pump(const Duration(seconds: 10));
    // Timer fires setState + post-frame Overlay insert; settle both.
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isTrue);
    // Fullscreen: covers the shell rail too, not just the page area.
    expect(tester.getSize(sleepOverlay()), const Size(1280, 800));
    expect(
      find.text('Deslizá hacia arriba o tocá para continuar'),
      findsOneWidget,
    );

    await tester.tap(sleepOverlay());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isFalse);
    expect(find.text('Mi casa'), findsOneWidget);

    // Dispose the page so the re-armed idle timer is cancelled.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('swipe up on sleep dismisses with tablet-like gesture', (
    WidgetTester tester,
  ) async {
    await pumpSleepyWallHome(tester);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isTrue);

    await tester.fling(sleepOverlay(), const Offset(0, -300), 1000);
    await tester.pump();
    // 260ms slide-up exit + entry removal.
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isFalse);
    expect(find.text('Mi casa'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('touch resets the idle countdown', (WidgetTester tester) async {
    await pumpSleepyWallHome(tester);

    await tester.pump(const Duration(seconds: 9));
    await tester.tap(find.text('Mi casa'));
    await tester.pump(const Duration(seconds: 9));
    expect(isAsleep(tester), isFalse);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isTrue);

    await tester.tap(sleepOverlay());
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('sleep is disabled without idleTimeout', (
    WidgetTester tester,
  ) async {
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
    await tester.pump(const Duration(seconds: 30));
    expect(isAsleep(tester), isFalse);
  });

  testWidgets('dragging up from the home gesture strip pulls sleep up', (
    WidgetTester tester,
  ) async {
    await pumpSleepyWallHome(tester);
    await tester.pump(const Duration(seconds: 1));

    final strip = find.byKey(const ValueKey('wall-sleep-gesture-strip'));
    expect(strip, findsOneWidget);

    // Long upward drag: the sheet follows the finger, release past the
    // threshold settles into fullscreen sleep.
    await tester.drag(strip, const Offset(0, -500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('short drag from the gesture strip snaps back without sleep', (
    WidgetTester tester,
  ) async {
    await pumpSleepyWallHome(tester);
    await tester.pump(const Duration(seconds: 1));

    await tester.drag(
      find.byKey(const ValueKey('wall-sleep-gesture-strip')),
      const Offset(0, -40),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(isAsleep(tester), isFalse);
    expect(find.text('Mi casa'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}
