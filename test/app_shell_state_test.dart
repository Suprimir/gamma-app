import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/app_shell.dart';
import 'package:gamma_app/features/dashboard/dashboard_page.dart';
import 'package:gamma_app/features/devices/devices_page.dart';
import 'package:gamma_app/app/lazy_page_host.dart';

void main() {
  testWidgets('F3A-L06: shell keeps visited pages alive across tab switches', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
      ),
    );
    await tester.pump();

    expect(find.byType(LazyPageHost), findsOneWidget);
    expect(
      tester.widget<LazyPageHost>(find.byType(LazyPageHost)).key,
      isA<GlobalKey>(),
    );
    expect(find.byType(DevicesPage), findsNothing);

    await tester.tap(find.text('Dispositivos'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DevicesPage), findsOneWidget);

    await tester.tap(find.text('Inicio'));
    await tester.pump();
    expect(find.byType(DashboardPage), findsOneWidget);

    await tester.tap(find.text('Dispositivos'));
    await tester.pump();
    expect(find.byType(DevicesPage), findsOneWidget);
  });
}
