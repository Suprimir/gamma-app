import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';
import '../../data/device_inventory.dart';
import 'wall_home_projection.dart';

/// Read-only wall Area overview: canonical name and control list.
///
/// Navigation-only. No physical controls, no editing, no provider vocabulary.
/// Pushed with an obvious back path from Wall Home.
class WallAreaOverviewPage extends StatelessWidget {
  const WallAreaOverviewPage({
    super.key,
    required this.snapshot,
    required this.areaId,
    required this.areaName,
  });

  final DeviceInventorySnapshot snapshot;
  final String areaId;
  final String areaName;

  @override
  Widget build(BuildContext context) {
    final controls = projectAreaControls(snapshot, areaId);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(areaName),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
            children: [
              Text(
                controls.isEmpty
                    ? 'No hay controles configurados en esta habitación.'
                    : '${controls.length} '
                          '${controls.length == 1 ? 'control' : 'controles'}',
                style: const TextStyle(fontSize: 17, color: AppColors.textDim),
              ),
              const SizedBox(height: 16),
              for (final control in controls)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: ListTile(
                    title: Text(
                      control.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
