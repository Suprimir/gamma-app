/// Related-routines derivation shared by the wall and desktop device detail
/// surfaces.
///
/// The backend's canonical action shape carries `RoutineAction.device_id`
/// as an endpoint target (`"<device_id>:<endpoint_id>"`, see
/// `composition.py`); the legacy token field (`device`) is intentionally NOT
/// matched — the 6c migration retired it, and matching tokens here would
/// fabricate relations the backend already normalized away.
library;

/// Counts routines with at least one action targeting [deviceId].
///
/// Callers pass the physical device id (`dev_6`), so a composite endpoint
/// target (`dev_6:relay_1`) counts for its device when it starts with
/// `"<device_id>:"`. Exact matches keep working for older stored ids.
int countRelatedRoutines(List<Map<String, dynamic>> routines, String deviceId) {
  if (deviceId.isEmpty) return 0;
  final prefix = '$deviceId:';
  var count = 0;
  for (final routine in routines) {
    final actions = routine['acciones'];
    if (actions is! List) continue;
    final related = actions.any(
      (action) =>
          action is Map &&
          action['device_id'] is String &&
          (action['device_id'] == deviceId ||
              (action['device_id'] as String).startsWith(prefix)),
    );
    if (related) count++;
  }
  return count;
}
