import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

class FloatingDockDestination {
  const FloatingDockDestination(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class FloatingDock extends StatelessWidget {
  const FloatingDock({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.destinations,
    this.itemHeight = 68,
    this.iconSize = 26,
    this.maxWidth = 720,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<FloatingDockDestination> destinations;

  /// Height of each destination item.
  final double itemHeight;

  /// Size of each destination icon.
  final double iconSize;

  /// Cap on dock width; `null` lets the dock span the window inset.
  final double? maxWidth;

  static const _radius = 26.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(maxWidth ?? double.infinity, width - 28),
          ),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.border,
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _DockItem(
                      destination: destinations[i],
                      active: i == currentIndex,
                      onTap: () => onSelected(i),
                      height: itemHeight,
                      iconSize: iconSize,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.active,
    required this.onTap,
    required this.height,
    required this.iconSize,
  });

  final FloatingDockDestination destination;
  final bool active;
  final VoidCallback onTap;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentStrong : AppColors.textDim;
    // One merged semantic node per destination: the InkWell contributes the
    // tap action, the Text contributes the label, and the explicit flags
    // expose the selected state + button role. Without the selected flag the
    // active destination would only be distinguishable visually.
    return MergeSemantics(
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? destination.selectedIcon : destination.icon,
                    size: iconSize,
                    color: color,
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      destination.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: color,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
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
