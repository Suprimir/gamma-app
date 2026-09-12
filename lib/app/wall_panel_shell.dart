import 'package:flutter/material.dart';

import '../features/dashboard/home_theme_background.dart';
import '../ui/app_colors.dart';
import 'navigation_destinations.dart';

/// Wall-panel navigation shell: touch-first left side rail.
///
/// Reference: left vertical bar (Inicio/Dispositivos/Rutinas/Ajustes/Camaras)
/// with the roomier look of the second mock: every destination always shows
/// icon + label, targets are >= 76px tall, and the active one gets a full
/// accent pill. Wall-only: mobile/desktop shells stay untouched.
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
      body: HomeThemeBackground(
        child: SafeArea(
          right: false,
          child: Stack(
            children: [
              // Page reserves the rail width so content never slides under it,
              // while the rail itself floats centered like the reference mock.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: 124),
                  child: page,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _WallSideRail(
                  key: const ValueKey('wall-panel-side-rail'),
                  destinations: destinations,
                  currentIndex: currentIndex,
                  onSelected: onSelected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wall-only icon remap: bigger, rounder, finger-readable versions of the
/// canonical destinations. Labels stay canonical on purpose.
({IconData icon, IconData selectedIcon}) _wallRailIcons(int index) {
  const pairs = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home),
    (icon: Icons.tune_outlined, selectedIcon: Icons.tune),
    (icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings),
    (icon: Icons.videocam_outlined, selectedIcon: Icons.videocam),
  ];
  if (index < 0 || index >= pairs.length) {
    return (icon: Icons.circle_outlined, selectedIcon: Icons.circle);
  }
  return pairs[index];
}

class _WallSideRail extends StatelessWidget {
  const _WallSideRail({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _railColor = Color(0xFF1C1F2B);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(left: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: _railColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < destinations.length; i++) ...[
              _RailItem(
                label: destinations[i].label,
                icons: _wallRailIcons(destinations[i].index),
                active: i == currentIndex,
                onTap: () => onSelected(i),
              ),
              if (i != destinations.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icons,
    required this.active,
    required this.onTap,
  });

  final String label;
  final ({IconData icon, IconData selectedIcon}) icons;
  final bool active;
  final VoidCallback onTap;

  static const _inactiveColor = Color(0xFF9AA0B2);

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        selected: active,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? icons.selectedIcon : icons.icon,
                    size: 28,
                    color: active ? Colors.white : _inactiveColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      color: active ? Colors.white : _inactiveColor,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
