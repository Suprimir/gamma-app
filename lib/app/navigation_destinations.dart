import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../features/cameras/cameras_page.dart';
import '../features/devices/devices_page.dart';
import '../features/routines/routines_page.dart';
import '../features/settings/settings_page.dart';
import '../features/wall_home/wall_panel_home_page.dart';

/// Canonical metadata for a top-level navigation destination.
class AppDestination {
  const AppDestination({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.buildPage,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function(ApiClient api, Duration spotifyPollInterval) buildPage;
}

/// The five top-level destinations of the app shell, in tab order.
final List<AppDestination> appDestinations = [
  AppDestination(
    index: 0,
    label: 'Inicio',
    icon: Icons.cottage_outlined,
    selectedIcon: Icons.cottage,
    buildPage: (api, spotifyPollInterval) =>
        AdaptiveHomePage(api: api, spotifyPollInterval: spotifyPollInterval),
  ),
  AppDestination(
    index: 1,
    label: 'Dispositivos',
    icon: Icons.lightbulb_outline,
    selectedIcon: Icons.lightbulb,
    buildPage: (api, _) => DevicesPage(api: api),
  ),
  AppDestination(
    index: 2,
    label: 'Rutinas',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    buildPage: (api, _) => RoutinesPage(api: api),
  ),
  AppDestination(
    index: 3,
    label: 'Ajustes',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    buildPage: (api, _) => SettingsPage(api: api),
  ),
  AppDestination(
    index: 4,
    label: 'Cámaras',
    icon: Icons.videocam_outlined,
    selectedIcon: Icons.videocam,
    buildPage: (api, _) => CamerasPage(api: api),
  ),
];
