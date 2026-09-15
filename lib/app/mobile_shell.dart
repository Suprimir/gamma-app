import 'package:flutter/cupertino.dart';

import 'floating_dock.dart';
import 'navigation_destinations.dart';

/// Bottom content inset reserved for the floating dock geometry, injected as
/// bottom MediaQuery padding so pages keep their content clear of the dock
/// while their backgrounds still paint edge to edge behind it.
/// Pill: inner padding 8 + capsule ~42 + bottom 24 + SafeArea ~8 = ~82 → 96 safe.
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
    final media = MediaQuery.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          // The page paints edge to edge so its background (gradient, orb
          // glow) stays visible behind the transparent dock. Content stays
          // clear of the dock through the injected bottom inset consumed by
          // each page's root SafeArea — the page area itself is not shrunk.
          child: MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                bottom: media.padding.bottom + kMobileDockReserve,
              ),
            ),
            child: page,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: FloatingDock(
            key: const ValueKey('mobile-floating-dock'),
            currentIndex: currentIndex,
            onSelected: onSelected,
            destinations: [
              for (var i = 0; i < destinations.length; i++)
                _iosDestination(destinations[i], i),
            ],
          ),
        ),
      ],
    );
  }
}

/// iOS-style (SF Symbols via CupertinoIcons) dock icons, mobile only.
///
/// [AppDestination] keeps the Material icons because the same list feeds the
/// desktop and wall shells; only the mobile dock remaps them here by tab
/// index so other surfaces stay untouched.
FloatingDockDestination _iosDestination(AppDestination d, int index) {
  const ios = [
    (icon: CupertinoIcons.house, selectedIcon: CupertinoIcons.house_fill),
    (
      icon: CupertinoIcons.lightbulb,
      selectedIcon: CupertinoIcons.lightbulb_fill,
    ),
    (icon: CupertinoIcons.sparkles, selectedIcon: CupertinoIcons.sparkles),
    (icon: CupertinoIcons.gear, selectedIcon: CupertinoIcons.gear_solid),
    (icon: CupertinoIcons.videocam, selectedIcon: CupertinoIcons.videocam_fill),
  ];
  if (index < 0 || index >= ios.length) {
    return FloatingDockDestination(d.icon, d.selectedIcon, d.label);
  }
  final pair = ios[index];
  return FloatingDockDestination(pair.icon, pair.selectedIcon, d.label);
}
