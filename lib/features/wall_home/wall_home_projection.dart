import 'package:flutter/foundation.dart';

import '../../data/device_inventory.dart';

/// One room on the Wall Home grid, projected from canonical data.
@immutable
class WallAreaSummary {
  const WallAreaSummary({
    required this.areaId,
    required this.name,
    required this.controlCount,
  });

  final String areaId;
  final String name;
  final int controlCount;
}

/// Provider-neutral projection of the household for the Wall Home.
///
/// Pure function of a canonical [DeviceInventorySnapshot]: no widget logic,
/// no DTO parsing, no provider-specific code.
@immutable
class WallHomeSnapshot {
  const WallHomeSnapshot({required this.areas, required this.attentionCount});

  /// Ordered wall cards, in canonical Area order.
  final List<WallAreaSummary> areas;

  /// Household configuration work that needs attention (user devices with
  /// `needsConfiguration`); gateways never inflate this.
  final int attentionCount;
}

/// One control shown inside a wall Area overview, from canonical data.
@immutable
class WallAreaControl {
  const WallAreaControl({required this.displayName});

  final String displayName;
}

/// Projects a canonical inventory snapshot into the Wall Home model.
///
/// Counting policy (frozen in `test/f3b_wall_home_baseline_test.dart`):
/// - Area identity = canonical `HomeArea.id`; display = `HomeArea.name`.
/// - logical control count per Area = user-facing endpoints whose
///   `controlled_area_id` matches the Area.
/// - infrastructure (`isGateway`) is excluded from counts.
/// - attention = user devices with `PhysicalDevice.needsConfiguration`.
/// - `physical_area_id` stays distinct; a physical device is never counted
///   for the room it hangs in unless it controls endpoints there.
WallHomeSnapshot projectWallHome(DeviceInventorySnapshot snapshot) {
  final userDevices = snapshot.userDevices;

  final areaCounts = <String, int>{
    for (final area in snapshot.areas) area.id: 0,
  };
  for (final device in userDevices) {
    for (final endpoint in device.endpoints) {
      final controlled = endpoint.controlledAreaId;
      if (controlled != null && areaCounts.containsKey(controlled)) {
        areaCounts[controlled] = areaCounts[controlled]! + 1;
      }
    }
  }

  final areas = [
    for (final area in snapshot.areas)
      WallAreaSummary(
        areaId: area.id,
        name: area.name,
        controlCount: areaCounts[area.id] ?? 0,
      ),
  ];

  final attentionCount = userDevices
      .where((device) => device.needsConfiguration)
      .length;

  return WallHomeSnapshot(areas: areas, attentionCount: attentionCount);
}

/// Read-only controls for one wall Area, in canonical endpoint order.
///
/// Logical scope is `controlled_area_id`; a physical device in another room
/// only appears here through its endpoints that control this Area.
List<WallAreaControl> projectAreaControls(
  DeviceInventorySnapshot snapshot,
  String areaId,
) {
  final result = <WallAreaControl>[];
  for (final device in snapshot.userDevices) {
    for (final endpoint in device.endpoints) {
      if (endpoint.controlledAreaId == areaId) {
        result.add(WallAreaControl(displayName: endpoint.displayName));
      }
    }
  }
  return result;
}
