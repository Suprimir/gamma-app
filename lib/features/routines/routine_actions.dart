import 'package:flutter/cupertino.dart' show CupertinoIcons, IconData;

import '../devices/devices_page.dart' show formatDeviceName, formatLocationName;

/// Categoría de una acción + contenido de su tarjeta en la paleta y en el
/// resumen. Copia fiel de `ACTION_CATEGORIES` del web.
class RoutineCategory {
  const RoutineCategory({
    required this.name,
    required this.icon,
    required this.label,
    required this.description,
  });

  final String name;
  final IconData icon;
  final String label;
  final String description;
}

/// Catálogo de categorías indexado por nombre (device/location/house/...).
const routineCategories = <String, RoutineCategory>{
  'device': RoutineCategory(
    name: 'device',
    icon: CupertinoIcons.lightbulb,
    label: 'Controla un dispositivo',
    description: 'Enciende, apaga o ajusta una luz o enchufe',
  ),
  'location': RoutineCategory(
    name: 'location',
    icon: CupertinoIcons.map,
    label: 'Una ubicación',
    description:
        'Enciende o apaga los dispositivos de una zona o de toda la casa',
  ),
  'house': RoutineCategory(
    name: 'house',
    icon: CupertinoIcons.house,
    label: 'Toda la casa',
    description: 'Enciende o apaga todos los dispositivos',
  ),
  'music': RoutineCategory(
    name: 'music',
    icon: CupertinoIcons.music_note,
    label: 'Reproduce en Spotify',
    description: 'Pon música por artista, canción o playlist',
  ),
  'news': RoutineCategory(
    name: 'news',
    icon: CupertinoIcons.news,
    label: 'Lee las noticias',
    description: 'GAMMA cuenta las noticias del día',
  ),
  'camera': RoutineCategory(
    name: 'camera',
    icon: CupertinoIcons.videocam,
    label: 'Toma una foto',
    description: 'Captura una imagen o consulta una cámara',
  ),
  'climate': RoutineCategory(
    name: 'climate',
    icon: CupertinoIcons.thermometer,
    label: 'Ajustar clima',
    description: 'Frío, calor o apagado por zona',
  ),
  'wait': RoutineCategory(
    name: 'wait',
    icon: CupertinoIcons.clock,
    label: 'Esperar',
    description: 'Pausa la secuencia unos segundos o minutos',
  ),
  'announce': RoutineCategory(
    name: 'announce',
    icon: CupertinoIcons.volume_up,
    label: 'Anuncio de voz',
    description: 'GAMMA dice un mensaje en voz alta',
  ),
  'runroutine': RoutineCategory(
    name: 'runroutine',
    icon: CupertinoIcons.play_circle,
    label: 'Ejecutar otra rutina',
    description: 'Encadena una rutina existente',
  ),
};

/// Orden de la paleta del editor. `house` no es una tarjeta: «Toda la casa»
/// se elige dentro de «Una ubicación» y solo se usa para renderizar acciones
/// antiguas con scope HOUSE_ALL.
const paletteCategoryOrder = [
  'device',
  'location',
  'music',
  'news',
  'camera',
  'climate',
  'wait',
  'announce',
  'runroutine',
];

/// Nombre del módulo que habilita cada tarjeta (null = siempre disponible).
const moduleEnablers = <String, String>{
  'music': 'spotify',
  'news': 'news',
  'camera': 'cameras',
};

/// Etiquetas de las capacidades de dispositivos en el config de domótica.
// ponytail: el web usa "Enciende"/"Apaga" (INTENT_LABELS); la UI pedida pide
// "Encender"/"Apagar" de forma explícita, así que se respeta esa instrucción.
const intentLabels = <String, String>{
  'TURN_ON': 'Encender',
  'TURN_OFF': 'Apagar',
  'SET_VALUE': 'Ajusta nivel',
};

const domoticIntents = {'TURN_ON', 'TURN_OFF', 'SET_VALUE'};

/// Mapeo capacidad canónica (inventory) → intents domóticos del editor.
///
/// El editor razona en intents ([domoticIntents]); el inventory habla
/// capacidades canónicas (`POWER`, `BRIGHTNESS`, ...). Solo cuentan las
/// declaradas escribibles: sin metadatos (`writable` ausente) se asume
/// elegible —comportamiento histórico del catálogo—; `writable: false`
/// explícito excluye. Las capacidades sin token (p. ej. `POSITION`) no
/// aportan nada y caen al fallback on/off, como hasta ahora.
const canonicalToDomoticIntents = <String, Set<String>>{
  'POWER': {'TURN_ON', 'TURN_OFF'},
  'BRIGHTNESS': {'SET_VALUE'},
};

/// Vista ubicación→dispositivos en la forma legacy del catálogo, proyectada
/// del inventory (`/devices` + `/areas`) en vez de `GET /catalog`.
///
/// Cada entrada es `{'name': areaId, 'devices': [{'id': deviceId,
/// 'capabilities': [intents...]}]}`: el mismo contrato que consumen
/// [deviceCapabilities] y el resolutor de objetivos, así que esos no
/// cambian. Agrupación espejo del backend y de `devicesInArea`: área física
/// del dispositivo o área controlada de cualquiera de sus endpoints; los
/// dispositivos sin área conocida se omiten, igual que en el catálogo.
/// Nunca lanza: las entradas malformadas se saltan en silencio.
List<Map<String, dynamic>> inventoryCatalogView({
  required List areas,
  required List devices,
}) {
  final areaIds = <String>[];
  for (final area in areas) {
    if (area is! Map) continue;
    final id = area['id']?.toString() ?? '';
    if (id.isEmpty || areaIds.contains(id)) continue;
    areaIds.add(id);
  }
  final byArea = <String, List<Map<String, dynamic>>>{};
  final seenInArea = <String, Set<String>>{};
  for (final device in devices) {
    if (device is! Map) continue;
    final deviceId = device['device_id']?.toString() ?? '';
    if (deviceId.isEmpty) continue;
    final deviceAreas = <String>{};
    final physical = device['physical_area_id']?.toString() ?? '';
    if (physical.isNotEmpty) deviceAreas.add(physical);
    final endpoints = device['endpoints'];
    if (endpoints is List) {
      for (final endpoint in endpoints) {
        if (endpoint is! Map) continue;
        final controlled =
            endpoint['controlled_area_id']?.toString() ?? '';
        if (controlled.isNotEmpty) deviceAreas.add(controlled);
      }
    }
    final intents = _deviceIntents(device);
    for (final areaId in deviceAreas) {
      if (!areaIds.contains(areaId)) continue;
      final seen = seenInArea.putIfAbsent(areaId, () => <String>{});
      if (!seen.add(deviceId)) continue;
      byArea
          .putIfAbsent(areaId, () => <Map<String, dynamic>>[])
          .add({'id': deviceId, 'capabilities': intents});
    }
  }
  return [
    for (final areaId in areaIds)
      {
        'name': areaId,
        'devices': byArea[areaId] ?? const <Map<String, dynamic>>[],
      },
  ];
}

/// Intents domóticos de un dispositivo del inventory, en orden estable
/// (on/off antes que nivel). Vacío cuando nada es mapeable: el llamante
/// aplica el fallback conservador.
List<String> _deviceIntents(Map device) {
  final declared = <String>{};
  final endpoints = device['endpoints'];
  if (endpoints is List) {
    for (final endpoint in endpoints) {
      if (endpoint is! Map) continue;
      final capabilities = endpoint['capabilities'];
      if (capabilities is! List) continue;
      for (final capability in capabilities) {
        if (capability is! Map) continue;
        if (capability['writable'] == false) continue;
        final name =
            capability['capability']?.toString().trim().toUpperCase() ?? '';
        if (name.isNotEmpty) declared.add(name);
      }
    }
  }
  final intents = <String>[];
  for (final entry in canonicalToDomoticIntents.entries) {
    if (declared.contains(entry.key)) intents.addAll(entry.value);
  }
  return intents;
}

/// Categoría visual de una acción (refleja `actionCategory` del web).
String actionCategory(Map<String, dynamic> action) {
  final intent = action['intent']?.toString() ?? '';
  if (intent == 'FETCH_NEWS') return 'news';
  if (intent == 'MEDIA_CONTROL') return 'music';
  if (intent == 'CAMERA_CONTROL') return 'camera';
  if (intent == 'CLIMATE_CONTROL') return 'climate';
  if (intent == 'WAIT') return 'wait';
  if (intent == 'ANNOUNCE') return 'announce';
  if (intent == 'RUN_ROUTINE') return 'runroutine';
  final scope = action['scope']?.toString() ?? '';
  if (scope == 'HOUSE_ALL') return 'house';
  if (scope == 'LOCATION_ALL') return 'location';
  return 'device';
}

IconData actionIcon(Map<String, dynamic> action) =>
    routineCategories[actionCategory(action)]?.icon ??
    CupertinoIcons.square_grid_2x2;

/// Resumen de una acción, copia exacta de `actionSummary` del web.
String actionSummary(Map<String, dynamic> action) {
  final intent = action['intent']?.toString() ?? '';
  if (intent == 'FETCH_NEWS') return 'Lee las noticias del día';
  if (intent == 'MEDIA_CONTROL') {
    final op = action['operation']?.toString() ?? '';
    final labels = <String, String>{
      'play': 'Reproduce música',
      'resume': 'Reanuda la música',
      'pause': 'Pausa la música',
      'next': 'Pasa a la siguiente canción',
      'previous': 'Vuelve a la canción anterior',
      'volume': 'Ajusta el volumen',
      'status': 'Consulta el estado de la música',
    };
    var text = labels[op] ?? 'Operación $op';
    final query = action['query']?.toString();
    if (query != null && query.isNotEmpty) text += ': «$query»';
    if (op == 'volume') {
      final argument = action['argument']?.toString();
      if (argument != null && argument.isNotEmpty) text += ' al $argument%';
    }
    return text;
  }
  if (intent == 'CAMERA_CONTROL') {
    final op = action['operation']?.toString() ?? '';
    final labels = <String, String>{
      'snapshot': 'Toma una foto',
      'status': 'Consulta el estado de la cámara',
      'events': 'Consulta los eventos de la cámara',
      'list': 'Lista las cámaras',
    };
    var text = labels[op] ?? 'Cámara: $op';
    final query = action['query']?.toString();
    if (query != null && query.isNotEmpty) text += ' ($query)';
    return text;
  }
  if (intent == 'CLIMATE_CONTROL') {
    final mode = action['mode']?.toString() ?? 'cool';
    final modeLabel = switch (mode) {
      'heat' => 'Calor',
      'off' => 'Apagado',
      _ => 'Frío',
    };
    final location = action['location']?.toString();
    final where = (location == null || location.isEmpty)
        ? 'toda la casa'
        : formatLocationName(location);
    if (mode == 'off') return 'Apaga el clima en $where';
    final value = action['value'];
    final temp = value != null ? ' a $value°' : '';
    return 'Clima en $where: $modeLabel$temp';
  }
  if (intent == 'WAIT') {
    final value = int.tryParse(action['value']?.toString() ?? '') ?? 0;
    final unit = action['value_semantic']?.toString() ?? 'minutos';
    return 'Esperar $value $unit';
  }
  if (intent == 'ANNOUNCE') {
    final message = action['query']?.toString() ?? '';
    final target = action['location']?.toString() ?? '';
    final where = target.isEmpty ? 'toda la casa' : 'mi teléfono';
    return 'Anuncia en $where: «$message»';
  }
  if (intent == 'RUN_ROUTINE') {
    final name = action['query']?.toString() ?? '';
    return name.isEmpty ? 'Ejecuta otra rutina' : 'Ejecuta la rutina «$name»';
  }
  final verbs = <String, String>{
    'TURN_ON': 'Enciende',
    'TURN_OFF': 'Apaga',
    'SET_VALUE': 'Ajusta',
    'GET_STATUS': 'Consulta el estado de',
  };
  final verb = verbs[intent] ?? intent;
  final scope = action['scope']?.toString() ?? 'SINGLE';
  if (scope == 'HOUSE_ALL') return '$verb toda la casa';
  if (scope == 'LOCATION_ALL') {
    return '$verb todos los dispositivos en '
        '${formatLocationName(action['location']?.toString() ?? '')}';
  }
  if (scope == 'DEVICE_GLOBAL') {
    return '$verb todos los ${formatDeviceName(action['device']?.toString() ?? '')} '
        'de la casa';
  }
  var target = formatDeviceName(action['device']?.toString() ?? '');
  final location = action['location']?.toString();
  if (location != null && location.isNotEmpty) {
    target += ' en ${formatLocationName(location)}';
  }
  final value = action['value'];
  if (intent == 'SET_VALUE' && value != null) target += ' al $value%';
  return '$verb $target';
}

/// Subtítulo de la acción, copia exacta de `actionSub` del web.
String actionSub(Map<String, dynamic> action) {
  final intent = action['intent']?.toString() ?? '';
  if (intent == 'FETCH_NEWS') return 'Noticias';
  if (intent == 'MEDIA_CONTROL') return 'Spotify';
  if (intent == 'CAMERA_CONTROL') return 'Cámara';
  if (intent == 'CLIMATE_CONTROL') return 'Clima';
  if (intent == 'WAIT') return 'Espera';
  if (intent == 'ANNOUNCE') return 'Anuncio';
  if (intent == 'RUN_ROUTINE') return 'Rutina';
  final scope = action['scope']?.toString() ?? '';
  if (scope == 'HOUSE_ALL') return 'Toda la casa';
  if (scope == 'LOCATION_ALL') return 'Ubicación';
  return 'Dispositivo';
}

/// Capacidades admitidas por un dispositivo del catálogo. Sin metadatos se
/// asume un comportamiento conservador de encendido/apagado; nunca se inventa
/// el ajuste de nivel (refleja `deviceCapabilities` del web).
List<String> deviceCapabilities(
  String location,
  String deviceId,
  List<Map<String, dynamic>> catalogLocations,
) {
  Map<String, dynamic>? locationEntry;
  for (final candidate in catalogLocations) {
    if (candidate['name']?.toString() == location) {
      locationEntry = candidate;
      break;
    }
  }
  Map<String, dynamic>? device;
  final devices = (locationEntry?['devices'] as List?) ?? const [];
  for (final candidate in devices.cast<Map<String, dynamic>>()) {
    if (candidate['id']?.toString() == deviceId) {
      device = candidate;
      break;
    }
  }
  if (device == null) return const ['TURN_ON', 'TURN_OFF'];
  final capabilities =
      (device['capabilities'] as List?)
          ?.map((e) => e.toString())
          .where(domoticIntents.contains)
          .toList() ??
      const [];
  return capabilities.isEmpty ? const ['TURN_ON', 'TURN_OFF'] : capabilities;
}

/// Familia de un dispositivo («luz_1» → «luz»). Los ids `requested_N` no pueden
/// resolverse sin el catálogo, así que se ignoran (devuelve null).
String? _deviceFamily(String deviceId) {
  if (deviceId.isEmpty || deviceId.startsWith('requested')) return null;
  return deviceId.split('_').first;
}

/// Expande el alcance de una acción domótica a pares (location, device).
/// Si no puede resolverse con seguridad devuelve null (no se advierte).
Set<String>? _resolveDomoticTargets(
  Map<String, dynamic> action,
  List<Map<String, dynamic>> catalogLocations,
) {
  final scope = action['scope']?.toString() ?? '';
  final pairs = <String>{};

  void addLocation(Map<String, dynamic>? location) {
    final name = location?['name']?.toString();
    if (name == null || name.isEmpty) return;
    final devices = (location?['devices'] as List?) ?? const [];
    for (final device in devices.cast<Map<String, dynamic>>()) {
      final id = device['id']?.toString();
      if (id != null && id.isNotEmpty) pairs.add('$name\u0000$id');
    }
  }

  if (scope == 'HOUSE_ALL') {
    for (final location in catalogLocations) {
      addLocation(location);
    }
  } else if (scope == 'LOCATION_ALL') {
    Map<String, dynamic>? location;
    final target = action['location']?.toString();
    for (final candidate in catalogLocations) {
      if (candidate['name']?.toString() == target) {
        location = candidate;
        break;
      }
    }
    if (location == null) return null;
    addLocation(location);
  } else if (scope == 'SINGLE' || scope == 'DEVICE_LOCATION') {
    final device = action['device']?.toString() ?? '';
    final location = action['location']?.toString() ?? '';
    if (device.isEmpty || location.isEmpty) return null;
    pairs.add('$location\u0000$device');
  } else if (scope == 'DEVICE_GLOBAL') {
    final family = _deviceFamily(action['device']?.toString() ?? '');
    if (family == null) return null;
    for (final location in catalogLocations) {
      final name = location['name']?.toString();
      if (name == null || name.isEmpty) continue;
      final devices = (location['devices'] as List?) ?? const [];
      for (final device in devices.cast<Map<String, dynamic>>()) {
        final id = device['id']?.toString();
        if (id != null && _deviceFamily(id) == family) {
          pairs.add('$name\u0000$id');
        }
      }
    }
  } else {
    // FLOOR_*, agrupaciones y exclusiones opacas: no se resuelven.
    return null;
  }
  return pairs.isEmpty ? null : pairs;
}

bool _overlaps(Set<String>? a, Set<String>? b) {
  if (a == null || b == null) return false;
  return a.any(b.contains);
}

String? _spotifyConflictReason(
  Map<String, dynamic> candidate,
  Map<String, dynamic> existing,
) {
  String group(Object? value) {
    final v = value?.toString() ?? '';
    if (v == 'play' || v == 'resume') return 'play';
    if (v == 'pause') return 'pause';
    if (v == 'next') return 'next';
    if (v == 'previous') return 'previous';
    if (v == 'volume') return 'volume';
    return v;
  }

  final cg = group(candidate['operation']);
  final eg = group(existing['operation']);
  if (cg == 'play' && eg == 'pause') return 'Contradice la pausa anterior';
  if (cg == 'pause' && eg == 'play') {
    return 'Contradice la reproducción anterior';
  }
  if (cg == 'next' && eg == 'previous') return 'Contradice la canción anterior';
  if (cg == 'previous' && eg == 'next') {
    return 'Contradice la siguiente canción';
  }
  if (cg == 'play' && eg == 'play') {
    final selection =
        candidate['spotify_uri']?.toString() ?? candidate['query']?.toString();
    final existingSelection =
        existing['spotify_uri']?.toString() ?? existing['query']?.toString();
    if (selection != null &&
        selection.isNotEmpty &&
        existingSelection != null &&
        existingSelection.isNotEmpty &&
        selection != existingSelection) {
      return 'Reemplaza la selección anterior';
    }
  }
  if (cg == 'volume' && eg == 'volume') {
    final value = candidate['argument']?.toString();
    final existingValue = existing['argument']?.toString();
    if (value != null && existingValue != null && value != existingValue) {
      return 'Contradice el volumen anterior';
    }
  }
  return null;
}

/// Contradicción entre dos acciones de clima en la MISMA zona (zona exacta:
/// mismo id o ambas «toda la casa»). Zonas distintas o dudosas nunca avisan.
String? _climateConflictReason(
  Map<String, dynamic> candidate,
  Map<String, dynamic> existing,
) {
  final candidateZone = candidate['location']?.toString() ?? '';
  final existingZone = existing['location']?.toString() ?? '';
  if (candidateZone != existingZone) return null;
  final mode = candidate['mode']?.toString() ?? 'cool';
  final existingMode = existing['mode']?.toString() ?? 'cool';
  if (mode != existingMode) return 'Contradice el modo anterior';
  if (mode == 'off') return null;
  final value = candidate['value'];
  final existingValue = existing['value'];
  if (value != null &&
      existingValue != null &&
      num.tryParse(value.toString()) !=
          num.tryParse(existingValue.toString())) {
    return 'Contradice la temperatura anterior';
  }
  return null;
}

/// Razón del conflicto entre la candidata y una acción previa, o null si no hay
/// contradicción segura (mismas reglas conservadoras que el web).
String? conflictReason(
  Map<String, dynamic> candidate,
  Map<String, dynamic> existing,
  List<Map<String, dynamic>> catalogLocations,
) {
  final candidateIntent = candidate['intent']?.toString() ?? '';
  final existingIntent = existing['intent']?.toString() ?? '';

  if (domoticIntents.contains(candidateIntent) &&
      domoticIntents.contains(existingIntent)) {
    final candidateTargets = _resolveDomoticTargets(
      candidate,
      catalogLocations,
    );
    final existingTargets = _resolveDomoticTargets(existing, catalogLocations);
    if (!_overlaps(candidateTargets, existingTargets)) return null;
    if (candidateIntent == 'TURN_ON' && existingIntent == 'TURN_OFF') {
      return 'Contradice «Apagar»';
    }
    if (candidateIntent == 'TURN_OFF' && existingIntent == 'TURN_ON') {
      return 'Contradice «Encender»';
    }
    if (candidateIntent == 'SET_VALUE' && existingIntent == 'SET_VALUE') {
      final value = candidate['value'];
      final existingValue = existing['value'];
      if (value != null &&
          existingValue != null &&
          num.tryParse(value.toString()) !=
              num.tryParse(existingValue.toString())) {
        return 'Contradice el nivel $existingValue%';
      }
    }
    return null;
  }

  if (candidateIntent == 'MEDIA_CONTROL' && existingIntent == 'MEDIA_CONTROL') {
    return _spotifyConflictReason(candidate, existing);
  }

  if (candidateIntent == 'CLIMATE_CONTROL' &&
      existingIntent == 'CLIMATE_CONTROL') {
    return _climateConflictReason(candidate, existing);
  }

  return null;
}

/// Encuentra las acciones existentes que contradicen a la candidata. Devuelve
/// {index: posición 1-based, label: resumen existente, reason}.
List<Map<String, String>> findConflicts(
  Map<String, dynamic> candidate,
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> catalogLocations,
) {
  final conflicts = <Map<String, String>>[];
  for (var i = 0; i < existing.length; i++) {
    final reason = conflictReason(candidate, existing[i], catalogLocations);
    if (reason != null) {
      conflicts.add({
        'index': '${i + 1}',
        'label': actionSummary(existing[i]),
        'reason': reason,
      });
    }
  }
  return conflicts;
}
