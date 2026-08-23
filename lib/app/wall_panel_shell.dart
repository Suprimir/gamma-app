import 'package:flutter/material.dart';

import '../ui/app_colors.dart';
import 'floating_dock.dart';
import 'navigation_destinations.dart';

/// Wall-panel navigation shell: page area under a touch-first bottom dock.
///
/// No sidebar, no rail — just the page and a larger dock with roomy targets.
class WallPanelShell extends StatelessWidget {
  const WallPanelShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    required this.page,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: page),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: FloatingDock(
              currentIndex: currentIndex,
              onSelected: onSelected,
              destinations: [
                for (final d in destinations)
                  FloatingDockDestination(d.icon, d.selectedIcon, d.label),
              ],
              itemHeight: 88,
              iconSize: 32,
              maxWidth: null,
            ),
          ),
        ],
      ),
    );
  }
}
