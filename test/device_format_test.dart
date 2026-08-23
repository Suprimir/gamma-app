import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/features/devices/devices_page.dart';

void main() {
  test('formatLocationName aplica alias, quita sufijos y capitaliza', () {
    expect(formatLocationName('sala'), 'Sala');
    expect(formatLocationName('sala_1'), 'Sala');
    expect(formatLocationName('bano'), 'Baño');
    expect(formatLocationName('recamara_2'), 'Recámara');
    expect(formatLocationName('despacho'), 'Despacho');
    expect(formatLocationName(''), 'Sin ubicación');
  });

  test('formatLocationName no muestra IDs canonicos de AreaStore', () {
    // The catalog returns display_name for canonical areas; if a raw
    // area_<hex> id leaks through, render a neutral label, never the id.
    expect(formatLocationName('area_36a6b7741f884de9'), 'Área');
    expect(formatLocationName('area_f74c0374e991427f'), 'Área');
  });

  test('deviceTypeMeta mapea familia a icono y label', () {
    expect(deviceTypeMeta('luz_sala_1'), (icon: Icons.lightbulb, label: 'Luz'));
    expect(deviceTypeMeta('foco_2'), (icon: Icons.lightbulb, label: 'Luz'));
    expect(deviceTypeMeta('enchufe_1'), (icon: Icons.power, label: 'Enchufe'));
    expect(deviceTypeMeta('ventilador_1'), (
      icon: Icons.air,
      label: 'Ventilador',
    ));
    expect(deviceTypeMeta('sensor_1'), (
      icon: Icons.thermostat,
      label: 'Sensor',
    ));
    expect(deviceTypeMeta('camara_3'), (icon: Icons.videocam, label: 'Cámara'));
    expect(deviceTypeMeta('x1_abc'), (
      icon: Icons.devices,
      label: 'Dispositivo',
    ));
  });

  test('locationIcon mapea nombres de ubicacion', () {
    expect(locationIcon('cocina'), Icons.soup_kitchen);
    expect(locationIcon('recamara_1'), Icons.bed);
    expect(locationIcon('bano'), Icons.bathtub);
    expect(locationIcon('patio'), Icons.park);
    expect(locationIcon('sala'), Icons.home);
  });

  test('formatDeviceName genera nombre legible', () {
    expect(formatDeviceName('luz_sala_1'), 'Luz sala');
    expect(formatDeviceName('camara_3'), 'Cámara 3');
    expect(formatDeviceName('enchufe'), 'Enchufe');
  });
}
