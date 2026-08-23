import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';

/// Lightweight desktop regression: Material NavigationRail already exposes
/// the selected destination through accessibility semantics. This guards that
/// desktop navigation keeps behaving correctly without any custom
/// accessibility layer around it.
void main() {
  testWidgets('desktop rail exposes selected destination semantically', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopShell(
            destinations: appDestinations,
            currentIndex: 1,
            onSelected: (_) {},
            windowClass: AppWindowClass.expanded,
            page: const Text('workspace'),
          ),
        ),
      ),
    );

    final selected = tester.getSemantics(find.text('Dispositivos'));
    expect(selected.label, contains('Dispositivos'));
    expect(
      selected,
      matchesSemantics(
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasSelectedState: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Inicio')),
      matchesSemantics(
        isSelected: false,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasSelectedState: true,
      ),
    );
  });
}
