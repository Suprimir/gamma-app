import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
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

/// Number of top-level navigation destinations currently flagged selected.
int _selectedDockCount(WidgetTester tester) {
  var count = 0;
  for (final label in _dockLabels) {
    final node = tester.getSemantics(find.text(label));
    if (node.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue) {
      count++;
    }
  }
  return count;
}

void main() {
  Future<void> pumpMobileShell(WidgetTester tester) async {
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
      tester.getSemantics(find.text('Inicio')),
      _dockSemantics(label: 'Inicio', isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Dispositivos')),
      _dockSemantics(label: 'Dispositivos', isSelected: false),
    );
    expect(_selectedDockCount(tester), 1);
  });

  testWidgets('A11Y-02: mobile selection moves on tap', (tester) async {
    await pumpMobileShell(tester);

    await tester.tap(find.text('Dispositivos'));
    await tester.pump();

    expect(
      tester.getSemantics(find.text('Inicio')),
      _dockSemantics(label: 'Inicio', isSelected: false),
    );
    expect(
      tester.getSemantics(find.text('Dispositivos')),
      _dockSemantics(label: 'Dispositivos', isSelected: true),
    );
    expect(_selectedDockCount(tester), 1);
  });

  testWidgets('A11Y-05: mobile dock exposes every readable label', (
    tester,
  ) async {
    await pumpMobileShell(tester);

    for (final label in _dockLabels) {
      expect(
        tester.getSemantics(find.text(label)),
        _dockSemantics(label: label, isSelected: label == 'Inicio'),
        reason: 'destination label must remain readable',
      );
    }
  });

  testWidgets('A11Y-06: mobile dock has exactly one selected node', (
    tester,
  ) async {
    await pumpMobileShell(tester);

    expect(_selectedDockCount(tester), 1);

    await tester.tap(find.text('Ajustes'));
    await tester.pump();
    expect(_selectedDockCount(tester), 1);
  });
}
