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
}
