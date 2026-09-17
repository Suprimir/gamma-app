import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/features/routines/routine_actions.dart';

const catalog = <Map<String, dynamic>>[
  {
    'name': 'salon',
    'devices': [
      {
        'id': 'luz_salon',
        'capabilities': ['TURN_ON', 'TURN_OFF', 'SET_VALUE'],
      },
      {
        'id': 'vent_salon',
        'capabilities': ['TURN_ON', 'TURN_OFF'],
      },
    ],
  },
  {
    'name': 'cocina',
    'devices': [
      {
        'id': 'luz_cocina',
        'capabilities': ['TURN_ON', 'TURN_OFF'],
      },
    ],
  },
];

Map<String, dynamic> domotic(
  String intent, {
  String? location,
  String? device,
  int? value,
}) {
  return {
    'scope': 'SINGLE',
    'intent': intent,
    'location': ?location,
    'device': ?device,
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
    test('domótico SINGLE con nivel', () {
      expect(
        actionSummary(
          domotic(
            'SET_VALUE',
            location: 'salon',
            device: 'luz_salon',
            value: 40,
          ),
        ),
        'Ajusta Luz salon en Salon al 40%',
      );
    });

    test('LOCATION_ALL y HOUSE_ALL', () {
      expect(
        actionSummary({
          'intent': 'TURN_OFF',
          'scope': 'LOCATION_ALL',
          'location': 'cocina',
        }),
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
      actionCategory(domotic('TURN_ON', location: 'a', device: 'b')),
      'device',
    );
    expect(actionCategory({'intent': 'FETCH_NEWS'}), 'news');
    expect(actionSub({'intent': 'MEDIA_CONTROL'}), 'Spotify');
    expect(
      actionSub({'intent': 'TURN_ON', 'scope': 'HOUSE_ALL'}),
      'Toda la casa',
    );
  });

  group('nuevas categorías (clima, espera, anuncio, encadenar)', () {
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
        conflictReason(heat22, cool22, catalog),
        'Contradice el modo anterior',
      );
      expect(
        conflictReason(cool24, cool22, catalog),
        'Contradice la temperatura anterior',
      );
      expect(conflictReason(cool22, cool22, catalog), isNull);
      expect(conflictReason(coolOtherZone, cool22, catalog), isNull);
    });
  });

  test('deviceCapabilities respeta el catálogo y cae a on/off', () {
    expect(deviceCapabilities('salon', 'luz_salon', catalog), [
      'TURN_ON',
      'TURN_OFF',
      'SET_VALUE',
    ]);
    expect(deviceCapabilities('cocina', 'luz_cocina', catalog), [
      'TURN_ON',
      'TURN_OFF',
    ]);
  });

  group('conflictReason', () {
    test('TURN_ON contradice TURN_OFF en el mismo objetivo', () {
      final on = domotic('TURN_ON', location: 'salon', device: 'luz_salon');
      final off = domotic('TURN_OFF', location: 'salon', device: 'luz_salon');
      expect(conflictReason(on, off, catalog), 'Contradice «Apagar»');
      expect(conflictReason(off, on, catalog), 'Contradice «Encender»');
    });

    test('objetivos distintos no generan conflicto', () {
      final on = domotic('TURN_ON', location: 'salon', device: 'luz_salon');
      final off = domotic('TURN_OFF', location: 'cocina', device: 'luz_cocina');
      expect(conflictReason(on, off, catalog), isNull);
    });

    test('SET_VALUE con nivel distinto contradice', () {
      final low = domotic(
        'SET_VALUE',
        location: 'salon',
        device: 'luz_salon',
        value: 10,
      );
      final high = domotic(
        'SET_VALUE',
        location: 'salon',
        device: 'luz_salon',
        value: 80,
      );
      expect(conflictReason(low, high, catalog), 'Contradice el nivel 80%');
    });

    test('TURN_ON + SET_VALUE no contradice', () {
      final on = domotic('TURN_ON', location: 'salon', device: 'luz_salon');
      final value = domotic(
        'SET_VALUE',
        location: 'salon',
        device: 'luz_salon',
        value: 50,
      );
      expect(conflictReason(on, value, catalog), isNull);
    });

    test('HOUSE_ALL abarca todos los dispositivos', () {
      final candidate = {'intent': 'TURN_OFF', 'scope': 'HOUSE_ALL'};
      final existing = domotic(
        'TURN_ON',
        location: 'salon',
        device: 'luz_salon',
      );
      expect(
        conflictReason(candidate, existing, catalog),
        'Contradice «Encender»',
      );
    });

    test('spotify play vs pausa y selección distinta', () {
      final play = spotify('play', uri: 'https://x/1');
      final pause = spotify('pause');
      expect(
        conflictReason(play, pause, catalog),
        'Contradice la pausa anterior',
      );
      expect(
        conflictReason(pause, play, catalog),
        'Contradice la reproducción anterior',
      );
      expect(
        conflictReason(spotify('play', uri: 'https://x/2'), play, catalog),
        'Reemplaza la selección anterior',
      );
      expect(
        conflictReason(
          spotify('volume', vol: '20'),
          spotify('volume', vol: '80'),
          catalog,
        ),
        'Contradice el volumen anterior',
      );
    });
  });

  group('findConflicts', () {
    test('index y label de la acción en conflicto', () {
      final candidate = domotic(
        'TURN_ON',
        location: 'salon',
        device: 'luz_salon',
      );
      final existing = [
        domotic('TURN_OFF', location: 'salon', device: 'luz_salon'),
        domotic('TURN_OFF', location: 'cocina', device: 'luz_cocina'),
      ];
      final conflicts = findConflicts(candidate, existing, catalog);
      expect(conflicts, hasLength(1));
      expect(conflicts[0]['index'], '1');
      expect(conflicts[0]['label'], contains('Luz salon'));
    });
  });

  group('inventoryCatalogView', () {
    Map<String, dynamic> endpoint(
      String id, {
      List<Map<String, dynamic>> capabilities = const [],
      String? controlledAreaId,
    }) {
      return {
        'endpoint_id': id,
        'controlled_area_id': controlledAreaId,
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

    test('mapea POWER a on/off y BRIGHTNESS a nivel', () {
      final view = inventoryCatalogView(
        areas: areas,
        devices: [
          {
            'device_id': 'luz_salon',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'ep1',
                capabilities: [cap('POWER', writable: true)],
              ),
              endpoint(
                'ep2',
                capabilities: [
                  cap('POWER', writable: true),
                  cap('BRIGHTNESS', writable: true),
                ],
              ),
            ],
          },
        ],
      );
      expect(view.map((e) => e['name']), ['salon', 'cocina']);
      final devices = view.first['devices'] as List;
      expect(devices.single['id'], 'luz_salon');
      expect(devices.single['capabilities'], [
        'TURN_ON',
        'TURN_OFF',
        'SET_VALUE',
      ]);
    });

    test('writable false excluye; sin metadatos se asume elegible', () {
      final view = inventoryCatalogView(
        areas: areas,
        devices: [
          {
            'device_id': 'sensor',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'ep1',
                capabilities: [cap('POWER', writable: false)],
              ),
            ],
          },
          {
            'device_id': 'legacy',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint('ep1', capabilities: [cap('POWER')]),
            ],
          },
        ],
      );
      final devices = view.first['devices'] as List;
      final byId = {for (final d in devices) d['id']: d['capabilities']};
      expect(byId['sensor'], isEmpty);
      expect(byId['legacy'], ['TURN_ON', 'TURN_OFF']);
    });

    test('agrupa por área controlada y omite áreas desconocidas', () {
      final view = inventoryCatalogView(
        areas: areas,
        devices: [
          {
            'device_id': 'luz_movil',
            'endpoints': [
              endpoint('ep1', controlledAreaId: 'cocina'),
            ],
          },
          {
            'device_id': 'fantasma',
            'physical_area_id': 'sotano',
            'endpoints': [],
          },
          {
            'device_id': 'sin_area',
            'endpoints': [],
          },
          'no-es-un-mapa',
        ],
      );
      final cocina = view
          .firstWhere((e) => e['name'] == 'cocina')['devices'] as List;
      expect(cocina.map((d) => d['id']), ['luz_movil']);
      final salon = view
          .firstWhere((e) => e['name'] == 'salon')['devices'] as List;
      expect(salon, isEmpty);
    });

    test('extremo a extremo con deviceCapabilities', () {
      final view = inventoryCatalogView(
        areas: areas,
        devices: [
          {
            'device_id': 'luz_salon',
            'physical_area_id': 'salon',
            'endpoints': [
              endpoint(
                'ep1',
                capabilities: [
                  cap('POWER', writable: true),
                  cap('BRIGHTNESS', writable: true),
                ],
              ),
            ],
          },
        ],
      );
      expect(deviceCapabilities('salon', 'luz_salon', view), [
        'TURN_ON',
        'TURN_OFF',
        'SET_VALUE',
      ]);
      // Dispositivo ausente de la vista: fallback conservador intacto.
      expect(deviceCapabilities('salon', 'otro', view), [
        'TURN_ON',
        'TURN_OFF',
      ]);
    });
  });
}
