import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/features/routines/routine_actions.dart';

/// Objetivos endpoint-canonical como los proyecta `inventoryTargetView`.
const targets = <RoutineTarget>[
  RoutineTarget(
    id: 'dev_1:relay_1',
    deviceId: 'dev_1',
    endpointId: 'relay_1',
    areaId: 'salon',
    label: 'Salón · Luz',
    capabilities: ['TURN_ON', 'TURN_OFF', 'SET_VALUE'],
  ),
  RoutineTarget(
    id: 'dev_2:relay_1',
    deviceId: 'dev_2',
    endpointId: 'relay_1',
    areaId: 'salon',
    label: 'Salón · Ventilador',
    capabilities: ['TURN_ON', 'TURN_OFF'],
  ),
  RoutineTarget(
    id: 'dev_3:relay_1',
    deviceId: 'dev_3',
    endpointId: 'relay_1',
    areaId: 'cocina',
    label: 'Cocina · Luz',
    capabilities: ['TURN_ON', 'TURN_OFF'],
  ),
];

const labels = RoutineLabels(
  targets: targets,
  areas: [
    {'id': 'salon', 'name': 'Salón'},
    {'id': 'cocina', 'name': 'Cocina'},
  ],
);

Map<String, dynamic> domotic(
  String intent, {
  String? deviceId,
  String? location,
  int? value,
}) {
  return {
    'scope': 'SINGLE',
    'intent': intent,
    'device_id': ?deviceId,
    'location': ?location,
    'value': ?value,
  };
}

Map<String, dynamic> spotify(String op, {String? uri, String? vol}) {
  return {
    'scope': 'MEDIA_CONTROL',
    'intent': 'MEDIA_CONTROL',
    'operation': op,
    'spotify_uri': ?uri,
    'argument': ?vol,
  };
}

void main() {
  group('actionSummary', () {
    test('domótico SINGLE canónico resuelve nombre y nivel', () {
      expect(
        actionSummary(
          domotic('SET_VALUE', deviceId: 'dev_1:relay_1', value: 40),
          labels: labels,
        ),
        'Ajusta Salón · Luz al 40%',
      );
    });

    test('acción legacy con token sigue mostrándose', () {
      expect(
        actionSummary({
          'scope': 'SINGLE',
          'intent': 'SET_VALUE',
          'location': 'salon',
          'device': 'luz_salon',
          'value': 40,
        }),
        'Ajusta Luz salon en Salon al 40%',
      );
    });

    test('LOCATION_ALL y HOUSE_ALL', () {
      expect(
        actionSummary(
          {'intent': 'TURN_OFF', 'scope': 'LOCATION_ALL', 'location': 'cocina'},
          labels: labels,
        ),
        'Apaga todos los dispositivos en Cocina',
      );
      expect(
        actionSummary({'intent': 'TURN_ON', 'scope': 'HOUSE_ALL'}),
        'Enciende toda la casa',
      );
    });

    test('música play con query y volumen', () {
      expect(
        actionSummary(
          spotify('play', uri: 'https://x/1')
            ..['query'] = 'The Wall'
            ..['spotify_type'] = 'album',
        ),
        'Reproduce música: «The Wall»',
      );
      expect(
        actionSummary(spotify('volume', vol: '30')),
        'Ajusta el volumen al 30%',
      );
    });

    test('cámara snapshot y noticias', () {
      expect(
        actionSummary({
          'scope': 'CAMERA_CONTROL',
          'intent': 'CAMERA_CONTROL',
          'operation': 'snapshot',
          'query': 'patio',
        }),
        'Toma una foto (patio)',
      );
      expect(
        actionSummary({'scope': 'FETCH_NEWS', 'intent': 'FETCH_NEWS'}),
        'Lee las noticias del día',
      );
    });
  });

  test('actionCategory y actionSub', () {
    expect(
      actionCategory(domotic('TURN_ON', deviceId: 'dev_1:relay_1')),
      'device',
    );
    expect(actionCategory({'intent': 'FETCH_NEWS'}), 'news');
    expect(actionSub({'intent': 'MEDIA_CONTROL'}), 'Spotify');
    expect(
      actionSub({'intent': 'TURN_ON', 'scope': 'HOUSE_ALL'}),
      'Toda la casa',
    );
  });

  group('categorías legacy (clima, espera, anuncio, encadenar)', () {
    // Ya no se ofrecen en la paleta (el whitelist del backend no las admite),
    // pero se siguen renderizando de forma tolerante por si existieran.
    test('categoría y subtítulo', () {
      expect(actionCategory({'intent': 'CLIMATE_CONTROL'}), 'climate');
      expect(actionCategory({'intent': 'WAIT'}), 'wait');
      expect(actionCategory({'intent': 'ANNOUNCE'}), 'announce');
      expect(actionCategory({'intent': 'RUN_ROUTINE'}), 'runroutine');
      expect(actionSub({'intent': 'CLIMATE_CONTROL'}), 'Clima');
      expect(actionSub({'intent': 'WAIT'}), 'Espera');
      expect(actionSub({'intent': 'ANNOUNCE'}), 'Anuncio');
      expect(actionSub({'intent': 'RUN_ROUTINE'}), 'Rutina');
    });

    test('resúmenes', () {
      expect(
        actionSummary({
          'intent': 'CLIMATE_CONTROL',
          'location': 'cocina',
          'mode': 'cool',
          'value': 22,
        }),
        'Clima en Cocina: Frío a 22°',
      );
      expect(
        actionSummary({'intent': 'CLIMATE_CONTROL', 'mode': 'off'}),
        'Apaga el clima en toda la casa',
      );
      expect(
        actionSummary({
          'intent': 'WAIT',
          'value': 5,
          'value_semantic': 'minutos',
        }),
        'Esperar 5 minutos',
      );
      expect(
        actionSummary({'intent': 'ANNOUNCE', 'query': 'La comida está lista'}),
        'Anuncia en toda la casa: «La comida está lista»',
      );
      expect(
        actionSummary({'intent': 'RUN_ROUTINE', 'query': 'Modo cine'}),
        'Ejecuta la rutina «Modo cine»',
      );
    });

    test('clima contradice modo y temperatura en la misma zona', () {
      final cool22 = {
        'intent': 'CLIMATE_CONTROL',
        'location': 'cocina',
        'mode': 'cool',
        'value': 22,
      };
      final heat22 = {
        'intent': 'CLIMATE_CONTROL',
        'location': 'cocina',
        'mode': 'heat',
        'value': 22,
      };
      final cool24 = {
        'intent': 'CLIMATE_CONTROL',
        'location': 'cocina',
        'mode': 'cool',
        'value': 24,
      };
      final coolOtherZone = {
        'intent': 'CLIMATE_CONTROL',
        'location': 'salon',
        'mode': 'heat',
        'value': 22,
      };
      expect(
        conflictReason(heat22, cool22, targets),
        'Contradice el modo anterior',
      );
      expect(
        conflictReason(cool24, cool22, targets),
        'Contradice la temperatura anterior',
      );
      expect(conflictReason(cool22, cool22, targets), isNull);
      expect(conflictReason(coolOtherZone, cool22, targets), isNull);
    });
  });

  group('targetCapabilities', () {
    test('respeta las capabilities del objetivo', () {
      expect(targetCapabilities('dev_1:relay_1', targets), [
        'TURN_ON',
        'TURN_OFF',
        'SET_VALUE',
      ]);
      expect(targetCapabilities('dev_3:relay_1', targets), [
        'TURN_ON',
        'TURN_OFF',
      ]);
    });

    test('objetivo ausente cae al fallback conservador', () {
      expect(targetCapabilities('dev_x:relay_1', targets), [
        'TURN_ON',
        'TURN_OFF',
      ]);
    });
  });

  group('conflictReason', () {
    test('TURN_ON contradice TURN_OFF en el mismo objetivo', () {
      final on = domotic('TURN_ON', deviceId: 'dev_1:relay_1');
      final off = domotic('TURN_OFF', deviceId: 'dev_1:relay_1');
      expect(conflictReason(on, off, targets), 'Contradice «Apagar»');
      expect(conflictReason(off, on, targets), 'Contradice «Encender»');
    });

    test('objetivos distintos no generan conflicto', () {
      final on = domotic('TURN_ON', deviceId: 'dev_1:relay_1');
      final off = domotic('TURN_OFF', deviceId: 'dev_3:relay_1');
      expect(conflictReason(on, off, targets), isNull);
    });

    test('SET_VALUE con nivel distinto contradice', () {
      final low = domotic('SET_VALUE', deviceId: 'dev_1:relay_1', value: 10);
      final high = domotic('SET_VALUE', deviceId: 'dev_1:relay_1', value: 80);
      expect(conflictReason(low, high, targets), 'Contradice el nivel 80%');
    });

    test('TURN_ON + SET_VALUE no contradice', () {
      final on = domotic('TURN_ON', deviceId: 'dev_1:relay_1');
      final value = domotic('SET_VALUE', deviceId: 'dev_1:relay_1', value: 50);
      expect(conflictReason(on, value, targets), isNull);
    });

    test('HOUSE_ALL abarca todos los objetivos', () {
      final candidate = {'intent': 'TURN_OFF', 'scope': 'HOUSE_ALL'};
      final existing = domotic('TURN_ON', deviceId: 'dev_1:relay_1');
      expect(conflictReason(candidate, existing, targets), 'Contradice «Encender»');
    });

    test('LOCATION_ALL abarca solo su área', () {
      final candidate = {
        'intent': 'TURN_OFF',
        'scope': 'LOCATION_ALL',
        'location': 'cocina',
      };
      expect(
        conflictReason(candidate, domotic('TURN_ON', deviceId: 'dev_3:relay_1'), targets),
        'Contradice «Encender»',
      );
      expect(
        conflictReason(candidate, domotic('TURN_ON', deviceId: 'dev_1:relay_1'), targets),
        isNull,
      );
    });

    test('spotify play vs pausa y selección distinta', () {
      final play = spotify('play', uri: 'https://x/1');
      final pause = spotify('pause');
      expect(
        conflictReason(play, pause, targets),
        'Contradice la pausa anterior',
      );
      expect(
        conflictReason(pause, play, targets),
        'Contradice la reproducción anterior',
      );
      expect(
        conflictReason(spotify('play', uri: 'https://x/2'), play, targets),
        'Reemplaza la selección anterior',
      );
      expect(
        conflictReason(
          spotify('volume', vol: '20'),
          spotify('volume', vol: '80'),
          targets,
        ),
        'Contradice el volumen anterior',
      );
    });
  });

  group('findConflicts', () {
    test('index y label de la acción en conflicto', () {
      final candidate = domotic('TURN_ON', deviceId: 'dev_1:relay_1');
      final existing = [
        domotic('TURN_OFF', deviceId: 'dev_1:relay_1'),
        domotic('TURN_OFF', deviceId: 'dev_3:relay_1'),
      ];
      final conflicts = findConflicts(
        candidate,
        existing,
        targets,
        labels: labels,
      );
      expect(conflicts, hasLength(1));
      expect(conflicts[0]['index'], '1');
      expect(conflicts[0]['label'], contains('Salón · Luz'));
    });
  });

  group('inventoryTargetView', () {
    Map<String, dynamic> endpoint(
      String id, {
      bool? enabled,
      bool? exposedToResolver,
      List<Map<String, dynamic>> capabilities = const [],
      String? controlledAreaId,
      String? displayNameGlobal,
    }) {
      return {
        'endpoint_id': id,
        'enabled': enabled,
        'exposed_to_resolver': exposedToResolver,
        'controlled_area_id': controlledAreaId,
        'display_name_global': displayNameGlobal,
        'capabilities': capabilities,
      };
    }

    Map<String, dynamic> cap(String name, {bool? writable}) {
      return {'capability': name, 'writable': writable};
    }

    const areas = [
      {'id': 'salon', 'name': 'Salón'},
      {'id': 'cocina', 'name': 'Cocina'},
    ];

    test('proyecta objetivos endpoint-canonical con id y label', () {
      final view = inventoryTargetView(
        areas: areas,
        devices: [
          {
            'device_id': 'dev_6',
            'display_name': 'Descasó y patio',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'relay_1',
                enabled: true,
                exposedToResolver: true,
                displayNameGlobal: 'Salón · Luz',
                capabilities: [cap('POWER', writable: true)],
              ),
              endpoint(
                'relay_2',
                enabled: true,
                exposedToResolver: true,
                controlledAreaId: 'cocina',
                displayNameGlobal: 'Cocina · Luz descanso',
                capabilities: [
                  cap('POWER', writable: true),
                  cap('BRIGHTNESS', writable: true),
                ],
              ),
            ],
          },
        ],
      );
      expect(view.map((t) => t.id), ['dev_6:relay_1', 'dev_6:relay_2']);
      expect(view[0].areaId, 'salon');
      expect(view[0].label, 'Salón · Luz');
      expect(view[0].capabilities, ['TURN_ON', 'TURN_OFF']);
      expect(view[1].areaId, 'cocina');
      expect(view[1].capabilities, ['TURN_ON', 'TURN_OFF', 'SET_VALUE']);
    });

    test('excluye endpoints no elegibles para el resolver', () {
      final view = inventoryTargetView(
        areas: areas,
        devices: [
          {
            'device_id': 'dev_1',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'disabled',
                enabled: false,
                exposedToResolver: true,
                capabilities: [cap('POWER', writable: true)],
              ),
              endpoint(
                'hidden',
                enabled: true,
                exposedToResolver: false,
                capabilities: [cap('POWER', writable: true)],
              ),
              endpoint(
                'ok',
                enabled: true,
                exposedToResolver: true,
                capabilities: [cap('POWER', writable: true)],
              ),
            ],
          },
        ],
      );
      expect(view.map((t) => t.id), ['dev_1:ok']);
    });

    test('writable false excluye la capability; sin metadatos asume on/off', () {
      final view = inventoryTargetView(
        areas: areas,
        devices: [
          {
            'device_id': 'dev_sensor',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'readonly',
                capabilities: [cap('POWER', writable: false)],
              ),
            ],
          },
          {
            'device_id': 'dev_legacy',
            'physical_area_id': 'salon',
            'endpoints': [endpoint('relay_1', capabilities: [cap('POWER')])],
          },
        ],
      );
      // El sensor de solo lectura queda fuera; el legacy sin metadatos entra
      // con el fallback conservador.
      expect(view.map((t) => t.id), ['dev_legacy:relay_1']);
      expect(view.single.capabilities, ['TURN_ON', 'TURN_OFF']);
    });

    test('usa área controlada, omite áreas desconocidas y entradas rotas', () {
      final view = inventoryTargetView(
        areas: areas,
        devices: [
          {
            'device_id': 'dev_movil',
            'endpoints': [
              endpoint(
                'relay_1',
                controlledAreaId: 'cocina',
                capabilities: [cap('POWER', writable: true)],
              ),
            ],
          },
          {
            'device_id': 'dev_fantasma',
            'physical_area_id': 'sotano',
            'endpoints': [
              endpoint('relay_1', capabilities: [cap('POWER', writable: true)]),
            ],
          },
          {
            'device_id': 'dev_sin_area',
            'endpoints': [
              endpoint('relay_1', capabilities: [cap('POWER', writable: true)]),
            ],
          },
          'no-es-un-mapa',
        ],
      );
      expect(view.map((t) => t.id), ['dev_movil:relay_1']);
      expect(view.single.areaId, 'cocina');
    });

    test('extremo a extremo con targetCapabilities', () {
      final view = inventoryTargetView(
        areas: areas,
        devices: [
          {
            'device_id': 'dev_1',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'relay_1',
                capabilities: [
                  cap('POWER', writable: true),
                  cap('BRIGHTNESS', writable: true),
                ],
              ),
            ],
          },
        ],
      );
      expect(targetCapabilities('dev_1:relay_1', view), [
        'TURN_ON',
        'TURN_OFF',
        'SET_VALUE',
      ]);
      // Objetivo ausente de la vista: fallback conservador intacto.
      expect(targetCapabilities('dev_9:relay_1', view), ['TURN_ON', 'TURN_OFF']);
    });

    test('RoutineLabels resuelve objetivo y área', () {
      expect(labels.targetLabel('dev_1:relay_1'), 'Salón · Luz');
      expect(labels.targetLabel('dev_x:relay_1'), isNull);
      expect(labels.areaLabel('cocina'), 'Cocina');
      expect(labels.areaLabel('area_unknown'), isNull);
    });
  });
}
