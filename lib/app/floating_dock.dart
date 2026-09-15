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
    this.iconSize = 22,
    this.maxWidth = 400,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<FloatingDockDestination> destinations;

  /// Height of each destination item (kept for API compatibility).
  final double itemHeight;

  /// Size of each destination icon.
  final double iconSize;

  /// Cap on dock width; `null` lets the dock span the window inset.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(maxWidth ?? double.infinity, width - 32),
            ),
            child: Padding(
              // Transparent dock: the page background (gradient, orb glow)
              // stays visible behind the floating items. The active pill uses
              // the runtime-themable accent.
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _DockItem(
                      destination: destinations[i],
                      active: i == currentIndex,
                      onTap: () => onSelected(i),
                      iconSize: iconSize,
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

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.active,
    required this.onTap,
    required this.iconSize,
  });

  final FloatingDockDestination destination;
  final bool active;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        selected: active,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          padding: active
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: active
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          destination.selectedIcon,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    )
                  : Icon(destination.icon, size: 22, color: AppColors.textDim),
            ),
          ),
        ),
      ),
    );
  }
}
