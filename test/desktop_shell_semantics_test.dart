import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/app/desktop_shell.dart';
import 'package:gamma_app/app/navigation_destinations.dart';
import 'package:gamma_app/data/api_client.dart';

/// Desktop regression: the persistent sidebar exposes the selected section
/// through accessibility semantics (selected + tap), keeping the behavior
/// the old rail provided without a custom accessibility layer.
void main() {
  testWidgets('desktop sidebar exposes selected section semantically', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopShell(
            destinations: appDestinations,
            currentIndex: 1,
            onSelected: (_) {},
            windowClass: AppWindowClass.expanded,
            api: ApiClient(baseUrl: 'http://127.0.0.1:8420'),
            page: const Text('workspace'),
          ),
        ),
      ),
    );

    final selected = tester.getSemantics(find.bySemanticsLabel('Dispositivos'));
    expect(selected.label, contains('Dispositivos'));
    expect(
      selected,
      matchesSemantics(
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Inicio')),
      matchesSemantics(
        isSelected: false,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
  });
}
