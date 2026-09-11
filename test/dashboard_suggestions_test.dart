import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/dashboard/dashboard_page.dart';

/// Suggestion chips must actually talk to the assistant (POST /turns),
/// showing the returned speech and surfacing errors in the existing state.
void main() {
  setUp(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpHome(WidgetTester tester, ApiClient api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DashboardPage(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('chip tap issues a turn with the session and shows the speech', (
    tester,
  ) async {
    final api = _RecordingTurnApi();
    await pumpHome(tester, api);

    final chip = find.text('Prende la luz del living');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.turnCalls, hasLength(1));
    expect(api.turnCalls.single.$1, 'Prende la luz del living');
    expect(api.turnCalls.single.$2, isNotNull);
    expect(api.turnCalls.single.$2, isNotEmpty);
    expect(find.text('Respuesta del asistente'), findsOneWidget);
  });

  testWidgets('chip tap failure surfaces the existing error state', (
    tester,
  ) async {
    final api = _RecordingTurnApi(fail: true);
    await pumpHome(tester, api);

    await tester.tap(find.text('Poné el aire en 24°'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.turnCalls, hasLength(1));
    expect(find.textContaining('Error'), findsOneWidget);
  });
}

class _RecordingTurnApi extends ApiClient {
  _RecordingTurnApi({this.fail = false})
    : super(baseUrl: 'http://127.0.0.1:8420');

  final bool fail;
  final turnCalls = <(String, String?)>[];

  @override
  Future<Map<String, dynamic>> turn(
    String text, {
    String? sessionId,
    String? clientId,
    String? speakerName,
  }) async {
    turnCalls.add((text, sessionId));
    if (fail) throw StateError('turn offline');
    return {'speech': 'Respuesta del asistente'};
  }
}
