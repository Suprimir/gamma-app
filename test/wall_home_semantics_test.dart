import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/wall_home/wall_panel_home_page.dart';

/// F3-B Phase 8: touch and accessibility invariants. Semantics are product
/// behavior, not test-only wrappers.
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

  testWidgets('area card exposes one semantic button with readable label', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    final data = tester
        .getSemantics(find.byKey(const ValueKey('wall-area-sala')))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.label, contains('Sala'));
    expect(data.label, contains('1 control'));
  });

  testWidgets('attention card is a readable semantic button', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    final data = tester
        .getSemantics(find.widgetWithText(TextButton, 'Necesita atención'))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.label, contains('Necesita atención'));
    expect(data.label, contains('3 dispositivos por configurar'));
  });

  testWidgets('no duplicate semantic labels after card wrappers', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);

    // MergeSemantics folds the two Texts into one button node; the area name
    // must not appear twice inside the same semantic node.
    final salaLabels = _allSemantics(tester)
        .map((data) => data.label)
        .where((label) => label.contains('Sala'))
        .toSet();
    expect(salaLabels, hasLength(1));
  });

  testWidgets('no spurious selected flags inside the wall home body', (
    WidgetTester tester,
  ) async {
    await pumpWallHome(tester);
    final selected = _allSemantics(tester)
        .where((data) => data.flagsCollection.isSelected == Tristate.isTrue)
        .toList();
    expect(selected, isEmpty);
  });

  testWidgets('increased text scale does not clip area names', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpWallHome(tester);

    expect(tester.takeException(), isNull);
    for (final name in ['Sala', 'Cocina', 'Recámara']) {
      expect(find.text(name), findsOneWidget);
    }
  });
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');
}

List<SemanticsData> _allSemantics(WidgetTester tester) {
  final root = tester.getSemantics(find.byType(WallPanelHomePage));
  final result = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    result.add(node.getSemanticsData());
    node.visitChildren(visit);
    return true;
  }

  visit(root);
  return result;
}
