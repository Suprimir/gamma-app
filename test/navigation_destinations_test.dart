import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/app/navigation_destinations.dart';

void main() {
  test('appDestinations holds exactly the five canonical destinations', () {
    expect(appDestinations, hasLength(5));
    for (var i = 0; i < appDestinations.length; i++) {
      expect(appDestinations[i].index, i);
    }
    expect(appDestinations.map((d) => d.label), [
      'Inicio',
      'Dispositivos',
      'Rutinas',
      'Ajustes',
      'Cámaras',
    ]);
  });

  test('every destination is complete and builds a page', () {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:8420');
    for (final d in appDestinations) {
      expect(d.index, isNotNull);
      expect(d.label, isNotNull);
      expect(d.label, isNotEmpty);
      expect(d.icon, isNotNull);
      expect(d.selectedIcon, isNotNull);
      expect(d.buildPage, isNotNull);
      expect(d.buildPage(api, Duration.zero, null), isNotNull);
    }
  });
}
