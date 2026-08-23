import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/app/lazy_page_host.dart';

class _FakePage extends StatefulWidget {
  const _FakePage({super.key});

  @override
  State<_FakePage> createState() => _FakePageState();
}

class _FakePageState extends State<_FakePage> {
  int counter = 0;

  @override
  Widget build(BuildContext context) {
    return Text('page');
  }
}

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required List<void Function()> builders,
    required List<GlobalKey<_FakePageState>> keys,
    required ValueNotifier<int> index,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (context, value, _) => LazyPageHost(
              index: value,
              builders: [
                for (var i = 0; i < builders.length; i++)
                  () {
                    builders[i]();
                    return _FakePage(key: keys[i]);
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('F3A-L01: only index 0 is built at startup', (tester) async {
    final invocations = List.generate(5, (_) => 0);
    final keys = List.generate(5, (_) => GlobalKey<_FakePageState>());
    final index = ValueNotifier<int>(0);

    await pumpHost(
      tester,
      builders: [for (var i = 0; i < 5; i++) () => invocations[i]++],
      keys: keys,
      index: index,
    );

    expect(invocations[0], 1);
    expect(invocations.sublist(1), everyElement(0));
    expect(find.byType(LazyPageHost), findsOneWidget);
  });

  testWidgets('F3A-L02: switching to index 1 builds it exactly once', (
    tester,
  ) async {
    final invocations = List.generate(5, (_) => 0);
    final keys = List.generate(5, (_) => GlobalKey<_FakePageState>());
    final index = ValueNotifier<int>(0);

    await pumpHost(
      tester,
      builders: [for (var i = 0; i < 5; i++) () => invocations[i]++],
      keys: keys,
      index: index,
    );
    index.value = 1;
    await tester.pump();

    expect(invocations[1], 1);
    expect(keys[1].currentState, isNotNull);
  });

  testWidgets('F3A-L03: returning to index 0 preserves State', (tester) async {
    final invocations = List.generate(2, (_) => 0);
    final keys = List.generate(2, (_) => GlobalKey<_FakePageState>());
    final index = ValueNotifier<int>(0);

    await pumpHost(
      tester,
      builders: [for (var i = 0; i < 2; i++) () => invocations[i]++],
      keys: keys,
      index: index,
    );

    final stateA = keys[0].currentState!;
    stateA.counter++;
    index.value = 1;
    await tester.pump();
    index.value = 0;
    await tester.pump();

    expect(keys[0].currentState, same(stateA));
    expect(stateA.counter, 1);
  });

  testWidgets('F3A-L04: returning to index 1 does not rebuild it', (
    tester,
  ) async {
    final invocations = List.generate(2, (_) => 0);
    final keys = List.generate(2, (_) => GlobalKey<_FakePageState>());
    final index = ValueNotifier<int>(0);

    await pumpHost(
      tester,
      builders: [for (var i = 0; i < 2; i++) () => invocations[i]++],
      keys: keys,
      index: index,
    );
    index.value = 1;
    await tester.pump();
    final stateB = keys[1].currentState!;
    stateB.counter++;
    index.value = 0;
    await tester.pump();
    index.value = 1;
    await tester.pump();

    expect(invocations[1], 1);
    expect(keys[1].currentState, same(stateB));
    expect(stateB.counter, 1);
  });

  testWidgets('F3A-L05: unvisited indexes are never built', (tester) async {
    final invocations = List.generate(5, (_) => 0);
    final keys = List.generate(5, (_) => GlobalKey<_FakePageState>());
    final index = ValueNotifier<int>(0);

    await pumpHost(
      tester,
      builders: [for (var i = 0; i < 5; i++) () => invocations[i]++],
      keys: keys,
      index: index,
    );
    index.value = 1;
    await tester.pump();
    index.value = 2;
    await tester.pump();

    expect(invocations[3], 0);
    expect(invocations[4], 0);
    expect(keys[3].currentState, isNull);
    expect(keys[4].currentState, isNull);
  });
}
