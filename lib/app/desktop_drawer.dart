import 'package:flutter/material.dart';

import '../ui/app_colors.dart';

/// Persistent admin sidebar for desktop. Width 272 expanded, 76 collapsed
/// (icons with tooltips). Sections mirror the canonical shell destinations:
/// Inicio, Dispositivos, Rutinas, Ajustes y Cámaras.
/// Dispositivos uses grid_view icon per spec; selected item gets indigo light
/// bg #EEF2FF and indigo text #4F46E5.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.collapsed = false,
  });

  /// Destination index currently shown by the shell host.
  final int selectedIndex;

  /// Selects a shared destination by its [appDestinations] index.
  final ValueChanged<int> onSelect;

  final bool collapsed;

  static const double kExpandedWidth = 272;
  static const double kCollapsedWidth = 76;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('desktop-sidebar'),
      width: collapsed ? kCollapsedWidth : kExpandedWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0x1A14202D), width: 1)),
      ),
      child: Material(
        color: Colors.white,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            if (!collapsed)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  'ADMINISTRAR',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.25,
                  ),
                ),
              ),
            for (final entry in _entries)
              _SidebarItem(
                label: entry.label,
                icon: entry.icon,
                selectedIcon: entry.selectedIcon,
                selected: entry.destination == selectedIndex,
                collapsed: collapsed,
                onTap: () => onSelect(entry.destination),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarEntry {
  const _SidebarEntry({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.destination,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Shared destination index in [appDestinations].
  final int destination;
}

const List<_SidebarEntry> _entries = [
  _SidebarEntry(
    label: 'Inicio',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    destination: 0,
  ),
  _SidebarEntry(
    label: 'Dispositivos',
    icon: Icons.grid_view,
    selectedIcon: Icons.grid_view,
    destination: 1,
  ),
  _SidebarEntry(
    label: 'Rutinas',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    destination: 2,
  ),
  _SidebarEntry(
    label: 'Ajustes',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    destination: 3,
  ),
  _SidebarEntry(
    label: 'Cámaras',
    icon: Icons.videocam_outlined,
    selectedIcon: Icons.videocam,
    destination: 4,
  ),
];

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.gammaIndigoLight : Colors.transparent;
    final fg = selected ? AppColors.gammaIndigo : const Color(0xFF5F6877);
    final visuals = Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: collapsed
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 48,
                alignment: Alignment.center,
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: fg,
                  size: 20,
                ),
              ),
            )
          : ListTile(
              leading: Icon(
                selected ? selectedIcon : icon,
                color: fg,
                size: 20,
              ),
              title: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              onTap: onTap,
              selected: selected,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              dense: true,
            ),
    );
    final item = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      // Collapsed has no ListTile to carry selection: merge it here so the
      // icon-only node still announces its label and selected state.
      child: collapsed
          ? Semantics(
              selected: selected,
              label: label,
              button: true,
              enabled: true,
              child: visuals,
            )
          : visuals,
    );
    if (!collapsed) return item;
    return Tooltip(message: label, child: item);
  }
}
