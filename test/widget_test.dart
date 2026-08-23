import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/main.dart';

void main() {
  testWidgets('app shell shows the navigation destinations', (
    WidgetTester tester,
  ) async {
    MediaKit.ensureInitialized();
    await tester.pumpWidget(
      GammaApp(api: ApiClient(baseUrl: 'http://127.0.0.1:8420')),
    );
    await tester.pump();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Módulos'), findsNothing);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Cámaras'), findsOneWidget);
    expect(find.text('Rutinas'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);

    expect(find.text('G'), findsOneWidget);

    await tester.tap(find.text('Cámaras'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
