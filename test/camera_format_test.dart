import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/features/cameras/cameras_page.dart';

void main() {
  test('cameraState mapea online a etiqueta y color', () {
    expect(cameraState({'online': true}).$1, 'En línea');
    expect(cameraState({'online': false}).$1, 'Fuera de línea');
    expect(cameraState(null).$1, 'Sin estado');
    expect(cameraState({'online': true}).$2, const Color(0xFF238457));
  });

  test('formatEventTime convierte a hora local', () {
    final formatted = formatEventTime('2026-08-06T10:05:00Z');
    expect(formatted, contains('2026-08-06 '));
    expect(formatted, contains(':'));
    expect(formatEventTime('no-es-fecha'), 'no-es-fecha');
  });
}
