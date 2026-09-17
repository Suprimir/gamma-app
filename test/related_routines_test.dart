import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/features/routines/related_routines.dart';

void main() {
  test('counts one per routine whose canonical device_id matches', () {
    final routines = <Map<String, dynamic>>[
      {
        'id': 'r1',
        'acciones': [
          {'device_id': 'dev_1', 'intent': 'TURN_ON'},
          {'device_id': 'dev_2', 'intent': 'TURN_OFF'},
        ],
      },
      {
        'id': 'r2',
        'acciones': [
          {'device_id': 'dev_1', 'intent': 'TURN_OFF'},
        ],
      },
      {
        'id': 'r3',
        'acciones': [
          {'device_id': 'dev_3', 'intent': 'TURN_ON'},
        ],
      },
    ];

    expect(countRelatedRoutines(routines, 'dev_1'), 2);
    expect(countRelatedRoutines(routines, 'dev_3'), 1);
    expect(countRelatedRoutines(routines, 'dev_unknown'), 0);
  });

  test('composite endpoint targets count for their device', () {
    final routines = <Map<String, dynamic>>[
      {
        'id': 'r1',
        'acciones': [
          {'device_id': 'dev_6:relay_1', 'intent': 'TURN_ON'},
          {'device_id': 'dev_6:relay_2', 'intent': 'TURN_ON'},
        ],
      },
      {
        'id': 'r2',
        'acciones': [
          {'device_id': 'dev_66:relay_1', 'intent': 'TURN_OFF'},
        ],
      },
    ];

    // Ambos endpoints pertenecen a dev_6 y la rutina cuenta una sola vez.
    expect(countRelatedRoutines(routines, 'dev_6'), 1);
    // dev_66 no debe confundirse con dev_6 pese al prefijo textual.
    expect(countRelatedRoutines(routines, 'dev_66'), 1);
    expect(countRelatedRoutines(routines, 'dev_7'), 0);
  });

  test('duplicate actions for the same device count the routine once', () {
    final routines = <Map<String, dynamic>>[
      {
        'id': 'r1',
        'acciones': [
          {'device_id': 'dev_1'},
          {'device_id': 'dev_1'},
        ],
      },
    ];

    expect(countRelatedRoutines(routines, 'dev_1'), 1);
  });

  test('legacy token form and malformed actions never match', () {
    final routines = <Map<String, dynamic>>[
      {
        'id': 'r1',
        'acciones': [
          {'device': 'dev_1', 'intent': 'TURN_ON'},
        ],
      },
      {'id': 'r2', 'acciones': 'not-a-list'},
      {'id': 'r3'},
      {
        'id': 'r4',
        'acciones': [
          'not-a-map',
          {'device_id': 42},
        ],
      },
    ];

    expect(countRelatedRoutines(routines, 'dev_1'), 0);
    expect(countRelatedRoutines(routines, '42'), 0);
  });

  test('empty device id or empty routines resolve to zero', () {
    expect(countRelatedRoutines(const [], 'dev_1'), 0);
    expect(countRelatedRoutines(const [], ''), 0);
  });
}
