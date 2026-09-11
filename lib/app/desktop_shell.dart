import 'package:flutter/material.dart';

import '../adaptive/adaptive_layout.dart';
import '../data/api_client.dart';
import 'desktop_drawer.dart';
import 'desktop_header.dart';
import 'navigation_destinations.dart';

/// Desktop navigation shell: header plus persistent admin sidebar and page.
/// The sidebar is always collapsed to icon-only (76px with tooltips),
/// keeping the workspace roomy at every window size (no hamburger toggle).
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    required this.page,
    required this.windowClass,
    required this.api,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Widget page;
  final AppWindowClass windowClass;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    // Icon-only sidebar by design: always collapsed regardless of window
    // class. windowClass is kept for API compatibility with callers/tests.
    final collapsed = true;
    return Scaffold(
      body: Column(
        children: [
          const DesktopHeader(),
          Expanded(
            child: Row(
              children: [
                DesktopSidebar(
                  selectedIndex: currentIndex,
                  onSelect: onSelected,
                  collapsed: collapsed,
                ),
                Expanded(child: page),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
