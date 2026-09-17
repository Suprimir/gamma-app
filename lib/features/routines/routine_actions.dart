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
///
/// Clima, esperar, anuncio y encadenar no se ofrecen: el whitelist del
/// backend (`utils/catalog_validation.py`) no admite sus intents/scopes, así
/// que guardarlos daría 422. Sus entradas de [routineCategories] se conservan
/// solo para renderizar (tolerante) acciones antiguas.
const paletteCategoryOrder = ['device', 'location', 'music', 'news', 'camera'];

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
/// elegible —comportamiento histórico—; `writable: false` explícito
/// excluye. Las capacidades sin token (p. ej. `POSITION`) no aportan nada y
/// caen al fallback on/off, como hasta ahora.
const canonicalToDomoticIntents = <String, Set<String>>{
  'POWER': {'TURN_ON', 'TURN_OFF'},
  'BRIGHTNESS': {'SET_VALUE'},
};

/// Objetivo canónico de rutina: un endpoint resolver-exposed del inventory.
///
/// El backend 6c persiste `device_id` como `"<device_id>:<endpoint_id>"`
/// (ver `composition.py`), así que [id] replica exactamente esa forma: es lo
/// único que el editor debe mandar en una acción SINGLE.
class RoutineTarget {
  const RoutineTarget({
    required this.id,
    required this.deviceId,
    required this.endpointId,
    required this.areaId,
    required this.label,
    required this.capabilities,
  });

  /// Id canónico `"<device_id>:<endpoint_id>"`.
  final String id;
  final String deviceId;
  final String endpointId;

  /// Área canónica que controla el endpoint (`controlled_area_id`) o, en su
  /// defecto, el área física del dispositivo. Vacía cuando no tiene área.
  final String areaId;

  /// Etiqueta legible (`display_name_global`, p. ej. «Patio · Luz»).
  final String label;

  /// Intents domóticos admitidos por el endpoint (on/off y/o nivel).
  final List<String> capabilities;
}

/// Vista de objetivos de rutina proyectada del inventory (`/devices` +
/// `/areas`), en vez del catálogo legacy retirado.
///
/// Solo incluye endpoints elegibles para el resolver: `enabled` y
/// `exposed_to_resolver` no pueden ser `false` explícitos (ausentes se
/// asumen elegibles, igual que `writable`), y deben caer en un área conocida.
/// Nunca lanza: las entradas malformadas se saltan en silencio.
List<RoutineTarget> inventoryTargetView({
  required List areas,
  required List devices,
}) {
  final areaIds = <String>{};
  for (final area in areas) {
    if (area is! Map) continue;
    final id = area['id']?.toString() ?? '';
    if (id.isNotEmpty) areaIds.add(id);
  }
  final targets = <RoutineTarget>[];
  for (final device in devices) {
    if (device is! Map) continue;
    final deviceId = device['device_id']?.toString() ?? '';
    if (deviceId.isEmpty) continue;
    final physicalArea = device['physical_area_id']?.toString() ?? '';
    final deviceLabel =
        _displayLabel(device['display_name']) ??
        _displayLabel(device['provider_name']) ??
        '';
    final endpoints = device['endpoints'];
    if (endpoints is! List) continue;
    for (final endpoint in endpoints) {
      if (endpoint is! Map) continue;
      if (endpoint['enabled'] == false) continue;
      if (endpoint['exposed_to_resolver'] == false) continue;
      final endpointId = endpoint['endpoint_id']?.toString() ?? '';
      if (endpointId.isEmpty) continue;
      final controlled = endpoint['controlled_area_id']?.toString() ?? '';
      final areaId = controlled.isNotEmpty ? controlled : physicalArea;
      if (areaId.isEmpty || !areaIds.contains(areaId)) continue;
      final capabilities = endpoint['capabilities'];
      final intents = _endpointIntents(endpoint);
      // Con metadatos de capacidades presentes pero nada mapeable/escribible
      // (p. ej. un sensor de solo lectura) el endpoint no es accionable: no se
      // ofrece. Sin metadatos se mantiene el fallback conservador on/off.
      if (capabilities is List && capabilities.isNotEmpty && intents.isEmpty) {
        continue;
      }
      final label =
          _displayLabel(endpoint['display_name_global']) ??
          _displayLabel(endpoint['display_name_semantic']) ??
          _displayLabel(endpoint['user_name']) ??
          _displayLabel(endpoint['display_name']) ??
          (deviceLabel.isNotEmpty ? deviceLabel : deviceId);
      targets.add(
        RoutineTarget(
          id: '$deviceId:$endpointId',
          deviceId: deviceId,
          endpointId: endpointId,
          areaId: areaId,
          label: label,
          capabilities: intents,
        ),
      );
    }
  }
  return targets;
}

String? _displayLabel(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

/// Intents domóticos de un endpoint del inventory, en orden estable (on/off
/// antes que nivel). Vacío cuando nada es mapeable: el llamante aplica el
/// fallback conservador.
List<String> _endpointIntents(Map endpoint) {
  final declared = <String>{};
  final capabilities = endpoint['capabilities'];
  if (capabilities is List) {
    for (final capability in capabilities) {
      if (capability is! Map) continue;
      if (capability['writable'] == false) continue;
      final name =
          capability['capability']?.toString().trim().toUpperCase() ?? '';
      if (name.isNotEmpty) declared.add(name);
    }
  }
  final intents = <String>[];
  for (final entry in canonicalToDomoticIntents.entries) {
    if (declared.contains(entry.key)) intents.addAll(entry.value);
  }
  return intents;
}

/// Intents admitidos por un objetivo; fallback conservador on/off cuando el
/// endpoint no declara nada mapeable (nunca se inventa el ajuste de nivel).
List<String> targetCapabilities(String targetId, List<RoutineTarget> targets) {
  for (final target in targets) {
    if (target.id == targetId) {
      return target.capabilities.isEmpty
          ? const ['TURN_ON', 'TURN_OFF']
          : target.capabilities;
    }
  }
  return const ['TURN_ON', 'TURN_OFF'];
}

/// Resolver de nombres para renderizar acciones canónicas: objetivos
/// (`device_id:endpoint_id` → etiqueta) y áreas (`area_*` → nombre).
class RoutineLabels {
  const RoutineLabels({this.targets = const [], this.areas = const []});

  final List<RoutineTarget> targets;
  final List<Map<String, dynamic>> areas;

  String? targetLabel(String id) {
    for (final target in targets) {
      if (target.id == id) return target.label;
    }
    return null;
  }

  String? areaLabel(String id) {
    for (final area in areas) {
      if (area['id']?.toString() == id) {
        final name = area['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }
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
///
/// [labels] resuelve ids canónicos (`device_id:endpoint_id`, `area_*`) a
/// nombres legibles; sin él cae a los formatters de tokens legacy, que siguen
/// funcionando para acciones antiguas.
String actionSummary(
  Map<String, dynamic> action, {
  RoutineLabels labels = const RoutineLabels(),
}) {
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
        : (labels.areaLabel(location) ?? formatLocationName(location));
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
    final location = action['location']?.toString() ?? '';
    return '$verb todos los dispositivos en '
        '${labels.areaLabel(location) ?? formatLocationName(location)}';
  }
  if (scope == 'DEVICE_GLOBAL') {
    return '$verb todos los ${_targetText(action, labels)} '
        'de la casa';
  }
  var target = _targetText(action, labels);
  final location = action['location']?.toString();
  if (location != null && location.isNotEmpty) {
    target += ' en ${labels.areaLabel(location) ?? formatLocationName(location)}';
  }
  final value = action['value'];
  if (intent == 'SET_VALUE' && value != null) target += ' al $value%';
  return '$verb $target';
}

/// Nombre legible del objetivo de una acción domótica: id canónico
/// (`device_id:endpoint_id`) resuelto por [labels]; sin resolver, se usa la
/// parte de dispositivo; acciones sin `device_id` caen al token legacy.
String _targetText(Map<String, dynamic> action, RoutineLabels labels) {
  final canonical = action['device_id']?.toString() ?? '';
  if (canonical.isNotEmpty) {
    final label = labels.targetLabel(canonical);
    if (label != null) return label;
    return formatDeviceName(canonical.split(':').first);
  }
  return formatDeviceName(action['device']?.toString() ?? '');
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

/// Expande el alcance de una acción domótica a ids canónicos de objetivo
/// (`device_id:endpoint_id`). Si no puede resolverse con seguridad devuelve
/// null (no se advierte).
Set<String>? _resolveDomoticTargets(
  Map<String, dynamic> action,
  List<RoutineTarget> targets,
) {
  final scope = action['scope']?.toString() ?? '';
  final ids = <String>{};

  if (scope == 'HOUSE_ALL') {
    for (final target in targets) {
      ids.add(target.id);
    }
  } else if (scope == 'LOCATION_ALL') {
    final area = action['location']?.toString() ?? '';
    if (area.isEmpty) return null;
    for (final target in targets) {
      if (target.areaId == area) ids.add(target.id);
    }
  } else if (scope == 'SINGLE' || scope == 'DEVICE_LOCATION') {
    final canonical = action['device_id']?.toString() ?? '';
    final token = canonical.isNotEmpty
        ? canonical
        : action['device']?.toString() ?? '';
    if (token.isEmpty) return null;
    ids.add(token);
  } else {
    // FLOOR_*, DEVICE_GLOBAL, agrupaciones y exclusiones opacas: no se
    // resuelven (la heurística de familia token se retiró con el catálogo).
    return null;
  }
  return ids.isEmpty ? null : ids;
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
  List<RoutineTarget> targets,
) {
  final candidateIntent = candidate['intent']?.toString() ?? '';
  final existingIntent = existing['intent']?.toString() ?? '';

  if (domoticIntents.contains(candidateIntent) &&
      domoticIntents.contains(existingIntent)) {
    final candidateTargets = _resolveDomoticTargets(candidate, targets);
    final existingTargets = _resolveDomoticTargets(existing, targets);
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
  List<RoutineTarget> targets, {
  RoutineLabels labels = const RoutineLabels(),
}) {
  final conflicts = <Map<String, String>>[];
  for (var i = 0; i < existing.length; i++) {
    final reason = conflictReason(candidate, existing[i], targets);
    if (reason != null) {
      conflicts.add({
        'index': '${i + 1}',
        'label': actionSummary(existing[i], labels: labels),
        'reason': reason,
      });
    }
  }
  return conflicts;
}
