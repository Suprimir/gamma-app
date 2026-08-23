import 'package:flutter/material.dart';

import 'floating_dock.dart';
import 'navigation_destinations.dart';

/// Vertical space reserved below the page area for the dock geometry.
const double kMobileDockReserve = 96;

/// Mobile navigation shell: page area above a floating bottom dock.
class MobileShell extends StatelessWidget {
  const MobileShell({
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
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(bottom: kMobileDockReserve),
            child: page,
          ),
        ),
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
          ),
        ),
      ],
    );
  }
}
