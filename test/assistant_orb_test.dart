import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/ui/assistant_orb.dart';

Widget _wrap(LoopState state, {bool reduced = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: AssistantOrb(state: state, onTap: () {}),
      ),
    ),
  );
}

void main() {
  for (final state in LoopState.values) {
    testWidgets('orb en estado $state renderiza sin excepciones', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(state));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('G'), findsOneWidget);
    });
  }

  testWidgets('reduced motion deja el orbe estatico', (tester) async {
    await tester.pumpWidget(_wrap(LoopState.listening, reduced: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('G'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el anillo del orbe se anima en cada estado activo', (
    tester,
  ) async {
    for (final state in [
      LoopState.listening,
      LoopState.processing,
      LoopState.speaking,
    ]) {
      await tester.pumpWidget(_wrap(state));
      await tester.pump(const Duration(milliseconds: 100));
      final first = _ringT(tester);
      await tester.pump(const Duration(milliseconds: 250));
      final second = _ringT(tester);
      expect(second, isNot(first), reason: 'el anillo no avanza en $state');
    }
    await tester.pumpWidget(const SizedBox());
  });
}

double _ringT(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byType(AssistantOrb),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  return (paint.painter as dynamic).t as double;
}
