import 'package:flutter/foundation.dart';

import '../../data/device_inventory.dart';

/// Explicit per-camera online state from `GET /api/v1/cameras/status`,
/// keyed by `camera_id`.
///
/// Only statuses the backend actually reported live here: a camera absent
/// from the map is unknown, never inferred offline/online from its
/// configured metadata.
@immutable
class CameraStatusJoin {
  const CameraStatusJoin(this._onlineById);

  final Map<String, bool> _onlineById;

  /// Null when the backend did not report a status for [cameraId].
  bool? onlineFor(String? cameraId) {
    if (cameraId == null || cameraId.isEmpty) return null;
    return _onlineById[cameraId];
  }

  bool get isEmpty => _onlineById.isEmpty;

  static const empty = CameraStatusJoin({});
}

/// Joins the raw `/api/v1/cameras/status` payload: `{statuses: [...]}` items
/// carrying `camera_id` and a strict boolean `online`. Malformed entries are
/// skipped instead of guessed.
CameraStatusJoin joinCameraStatuses(List<Map<String, dynamic>> statuses) {
  final onlineById = <String, bool>{};
  for (final status in statuses) {
    final id = status['camera_id'];
    final online = status['online'];
    if (id is String && id.isNotEmpty && online is bool) {
      onlineById[id] = online;
    }
  }
  return CameraStatusJoin(onlineById);
}

/// Counts how many configured [cameras] the backend explicitly reported as
/// online. Cameras without a status entry count as unknown, not online.
int countOnlineCameras(
  List<Map<String, dynamic>> cameras,
  CameraStatusJoin status,
) {
  var count = 0;
  for (final camera in cameras) {
    final id = camera['camera_id']?.toString();
    if (status.onlineFor(id) == true) count++;
  }
  return count;
}

/// Confidence tone of the desktop home "Estado del hogar" pill.
enum HomeStatusTone {
  /// All observed devices are healthy and the state is validated.
  ok,

  /// At least one offline/unreachable/auth-error device or an endpoint whose
  /// last observation quality is `unavailable`.
  check,

  /// No device has a local state to validate yet.
  neutral,
}

/// Honest "Dispositivos activos" derivation for the desktop home.
@immutable
class HomeStatusSummary {
  const HomeStatusSummary({
    required this.activeCount,
    required this.knownCount,
    required this.tone,
    required this.subtitle,
  });

  /// Devices with [devicePowerDisplayState] == on.
  final int activeCount;

  /// Devices with any display state other than unknown.
  final int knownCount;

  final HomeStatusTone tone;
  final String subtitle;

  /// '—' when nothing is known: an unvalidated home never claims a count.
  String get valueLabel => knownCount == 0 ? '—' : '$activeCount';
}

/// Derives the status card values from confirmed observations only.
///
/// `known == 0` means no device reported a usable local state (the HTTP
/// path leaves observations null until the backend confirms one), so the
/// card shows a neutral "Sin validar" instead of a fabricated zero.
HomeStatusSummary deriveHomeStatus(DeviceInventorySnapshot snapshot) {
  var active = 0;
  var known = 0;
  var trouble = false;
  for (final device in snapshot.userDevices) {
    final state = devicePowerDisplayState(device);
    if (state != PowerDisplayState.unknown) {
      known++;
      if (state == PowerDisplayState.on) active++;
    }
    if (device.health == DeviceHealthState.offline ||
        device.health == DeviceHealthState.unreachable ||
        device.health == DeviceHealthState.authError) {
      trouble = true;
    }
    if (device.endpoints.any((e) => e.observedQuality == 'unavailable')) {
      trouble = true;
    }
  }
  if (known == 0) {
    return const HomeStatusSummary(
      activeCount: 0,
      knownCount: 0,
      tone: HomeStatusTone.neutral,
      subtitle: 'Estado local sin validar',
    );
  }
  return HomeStatusSummary(
    activeCount: active,
    knownCount: known,
    tone: trouble ? HomeStatusTone.check : HomeStatusTone.ok,
    subtitle: 'activos de $known con estado confirmado',
  );
}

/// True when any device linked to [areaId] (physical placement or controlled
/// endpoint) has a confirmed "on" display state. Unknown states never light
/// the area dot.
bool areaHasPowerOn(DeviceInventorySnapshot snapshot, String areaId) {
  return snapshot
      .devicesInArea(areaId)
      .any((device) => devicePowerDisplayState(device) == PowerDisplayState.on);
}
