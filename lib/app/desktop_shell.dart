import 'package:flutter/material.dart';

import '../adaptive/adaptive_layout.dart';
import '../ui/app_colors.dart';
import 'navigation_destinations.dart';

/// Desktop navigation shell: a [NavigationRail] beside the page area.
///
/// Expanded/large windows get an extended rail with visible labels; medium
/// windows get a compact icon-only rail with tooltips.
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    required this.page,
    required this.windowClass,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Widget page;
  final AppWindowClass windowClass;

  bool get _extended =>
      windowClass == AppWindowClass.expanded ||
      windowClass == AppWindowClass.large;

  @override
  Widget build(BuildContext context) {
    final extended = _extended;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            labelType: extended ? null : NavigationRailLabelType.none,
            backgroundColor: AppColors.bg,
            selectedIconTheme: const IconThemeData(
              color: AppColors.accentStrong,
            ),
            unselectedIconTheme: const IconThemeData(color: AppColors.textDim),
            selectedLabelTextStyle: const TextStyle(
              color: AppColors.accentStrong,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelTextStyle: const TextStyle(color: AppColors.textDim),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: _railIcon(d, d.icon, extended),
                  selectedIcon: _railIcon(d, d.selectedIcon, extended),
                  label: Text(d.label),
                ),
            ],
            selectedIndex: currentIndex,
            onDestinationSelected: onSelected,
          ),
          VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: page),
        ],
      ),
    );
  }

  /// Compact rails hide labels, so their icons need tooltips.
  static Widget _railIcon(AppDestination d, IconData icon, bool extended) {
    final child = Icon(icon);
    return extended ? child : Tooltip(message: d.label, child: child);
  }
}
