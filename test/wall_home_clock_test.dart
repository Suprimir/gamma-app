import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/features/wall_home/wall_home_clock.dart';

/// F3-B final closure — Gap C: the clock must align to real local minute
/// boundaries, not one minute after widget creation.
void main() {
  testWidgets('clock renders time and Spanish date from the injected clock', (
    WidgetTester tester,
  ) async {
    final now = DateTime(2026, 8, 15, 8, 42);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallHomeClock(now: _frozenClock(now))),
      ),
    );

    expect(find.text('08:42'), findsOneWidget);
    expect(find.text('Sábado, 15 de agosto'), findsOneWidget);
  });

  testWidgets(
    'CLOCK-01/02: starting at 08:42:53 updates at 08:43:00, not 08:43:53',
    (WidgetTester tester) async {
      var current = DateTime(2026, 8, 15, 8, 42, 53);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WallHomeClock(now: () => current)),
        ),
      );
      expect(find.text('08:42'), findsOneWidget);

      // 6 seconds in: still within the 08:42 minute.
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('08:42'), findsOneWidget);

      // The boundary (08:43:00) is 7 seconds from 08:42:53.
      current = DateTime(2026, 8, 15, 8, 43);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('08:43'), findsOneWidget);
    },
  );

  testWidgets('CLOCK-03: later minutes keep aligning to boundaries', (
    WidgetTester tester,
  ) async {
    var current = DateTime(2026, 8, 15, 8, 42, 53);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallHomeClock(now: () => current)),
      ),
    );

    current = DateTime(2026, 8, 15, 8, 43);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('08:43'), findsOneWidget);

    // Next boundary is 08:44:00.
    current = DateTime(2026, 8, 15, 8, 44);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('08:44'), findsOneWidget);
  });

  testWidgets('CLOCK-04: no startup drift from an offset start', (
    WidgetTester tester,
  ) async {
    var current = DateTime(2026, 8, 15, 12, 15, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallHomeClock(now: () => current)),
      ),
    );
    expect(find.text('12:15'), findsOneWidget);

    // 49 seconds in: still 12:15. The update must land at 12:16:00 (50s),
    // not at 12:16:10 and not after a full 60s periodic tick.
    await tester.pump(const Duration(seconds: 49));
    expect(find.text('12:15'), findsOneWidget);

    current = DateTime(2026, 8, 15, 12, 16);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('12:16'), findsOneWidget);
  });

  testWidgets('CLOCK-05: dispose before the next tick is safe', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WallHomeClock(
            now: _frozenClock(DateTime(2026, 8, 15, 8, 42, 53)),
          ),
        ),
      ),
    );
    expect(find.text('08:42'), findsOneWidget);

    // Dispose the clock before the boundary tick.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('clock updates without rebuilding the host', (
    WidgetTester tester,
  ) async {
    var current = DateTime(2026, 8, 15, 8, 42, 53);
    Widget host = const SizedBox(key: Key('host'));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              host,
              WallHomeClock(now: () => current),
            ],
          ),
        ),
      ),
    );
    expect(find.text('08:42'), findsOneWidget);

    current = DateTime(2026, 8, 15, 8, 43);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('08:43'), findsOneWidget);

    // The clock updates in place; no host rebuild required.
    expect(tester.widget(find.byKey(const Key('host'))), same(host));
  });
}

DateTime Function() _frozenClock(DateTime value) =>
    () => value;
