import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/app/mobile_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';

/// Drives the shell index so taps move the active destination, mirroring how
/// AppShell updates `currentIndex` in production.
class _ShellHarness extends StatefulWidget {
  const _ShellHarness({required this.buildShell});

  final Widget Function(int index, ValueChanged<int> onSelected) buildShell;

  @override
  State<_ShellHarness> createState() => _ShellHarnessState();
}

class _ShellHarnessState extends State<_ShellHarness> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return widget.buildShell(_index, (i) => setState(() => _index = i));
  }
}

const _dockLabels = ['Inicio', 'Dispositivos', 'Rutinas', 'Ajustes', 'Cámaras'];

/// Full expected semantic shape of one dock destination: readable label,
/// button role, selectable-state present, focusable/tappable, and the
/// requested selected value.
Matcher _dockSemantics({required String label, required bool isSelected}) =>
    matchesSemantics(
      label: label,
      isButton: true,
      isSelected: isSelected,
      hasSelectedState: true,
      isFocusable: true,
      hasTapAction: true,
      hasFocusAction: true,
    );

/// Locates a dock destination through its accessible name. The redesigned dock
/// only renders a visible `Text` for the active destination, so the locator
/// must not depend on `find.text`; the semantics label stays available on the
/// `Semantics` wrapper for every destination.
Finder _dockItem(String label) => find.bySemanticsLabel(label).first;

/// Resolves the merged semantics node of a dock destination by its label.
SemanticsNode _dockNode(WidgetTester tester, String label) =>
    tester.getSemantics(_dockItem(label));

/// Number of top-level navigation destinations currently flagged selected.
int _selectedDockCount(WidgetTester tester) {
  var count = 0;
  for (final label in _dockLabels) {
    final node = _dockNode(tester, label);
    if (node.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue) {
      count++;
    }
  }
  return count;
}

void main() {
  // Semantics must be enabled before consulting `find.bySemanticsLabel`; the
  // handle is disposed at the end of each test (the framework verifies it).
  late SemanticsHandle semanticsHandle;

  Future<void> pumpMobileShell(WidgetTester tester) async {
    semanticsHandle = tester.ensureSemantics();
    // The square widget-test font renders the active 'Dispositivos' pill wider
    // than the dock's fixed cap; a reduced scale keeps the semantics harness
    // free of test-font overflow without touching the production layout.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ShellHarness(
            buildShell: (index, onSelected) => MobileShell(
              destinations: appDestinations,
              currentIndex: index,
              onSelected: onSelected,
              page: const Text('page-area'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('A11Y-01: mobile initial destination is selected semantically', (
    tester,
  ) async {
    await pumpMobileShell(tester);

    expect(
      _dockNode(tester, 'Inicio'),
      _dockSemantics(label: 'Inicio', isSelected: true),
    );
    expect(
      _dockNode(tester, 'Dispositivos'),
      _dockSemantics(label: 'Dispositivos', isSelected: false),
    );
    expect(_selectedDockCount(tester), 1);
    semanticsHandle.dispose();
  });

  testWidgets('A11Y-02: mobile selection moves on tap', (tester) async {
    await pumpMobileShell(tester);

    await tester.tap(_dockItem('Dispositivos'));
    await tester.pump();

    expect(
      _dockNode(tester, 'Inicio'),
      _dockSemantics(label: 'Inicio', isSelected: false),
    );
    expect(
      _dockNode(tester, 'Dispositivos'),
      _dockSemantics(label: 'Dispositivos', isSelected: true),
    );
    expect(_selectedDockCount(tester), 1);
    semanticsHandle.dispose();
  });

  testWidgets('A11Y-05: mobile dock exposes every readable label', (
    tester,
  ) async {
    await pumpMobileShell(tester);

    for (final label in _dockLabels) {
      expect(
        _dockNode(tester, label),
        _dockSemantics(label: label, isSelected: label == 'Inicio'),
        reason: 'destination label must remain readable',
      );
    }
    semanticsHandle.dispose();
  });

  testWidgets('A11Y-06: mobile dock has exactly one selected node', (
    tester,
  ) async {
    await pumpMobileShell(tester);

    expect(_selectedDockCount(tester), 1);

    await tester.tap(_dockItem('Ajustes'));
    await tester.pump();
    expect(_selectedDockCount(tester), 1);
    semanticsHandle.dispose();
  });
}
