import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../adaptive/adaptive_layout.dart';
import '../adaptive/adaptive_scope.dart';
import '../adaptive/adaptive_surface_preferences.dart';
import '../data/api_client.dart';
import 'desktop_shell.dart';
import 'lazy_page_host.dart';
import 'mobile_shell.dart';
import 'navigation_destinations.dart';
import 'wall_panel_shell.dart';

/// Adaptive orchestrator: window geometry + persisted surface mode + platform
/// resolve to a shell. Live resizes and mode changes swap shells without
/// restart and without losing the selected destination or visited page State.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    this.surfaceModeController,
    this.spotifyPollInterval = Duration.zero,
  });

  final ApiClient api;

  /// Injected for tests; otherwise [AppShell] owns one and loads it once.
  final AdaptiveSurfaceModeController? surfaceModeController;

  /// Playback polling cadence for the Home surfaces; zero (tests, previews)
  /// keeps every timer off.
  final Duration spotifyPollInterval;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _pageHostKey = GlobalKey();
  int _index = 0;

  late final AdaptiveSurfaceModeController _controller =
      widget.surfaceModeController ?? AdaptiveSurfaceModeController();
  late final bool _ownsController = widget.surfaceModeController == null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSurfaceModeChanged);
    if (_ownsController) _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onSurfaceModeChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onSurfaceModeChanged() {
    if (mounted) setState(() {});
  }

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final windowClass = AppWindowClass.fromWidth(constraints.maxWidth);
        final mode = _controller.value;
        var effective = resolveEffectiveAppSurface(
          windowClass: windowClass,
          mode: mode,
          platform: defaultTargetPlatform,
        );

        // COMPACT-SAFE FALLBACK: a persisted wallPanel preference must never
        // overflow a tiny window, so compact widths render mobile instead.
        // The preference stays persisted as wallPanel — it reapplies as soon
        // as the window widens.
        if (effective == EffectiveAppSurface.wallPanel &&
            windowClass.isCompact) {
          effective = EffectiveAppSurface.mobile;
        }

        // LazyPageHost keeps its GlobalKey across shell switches, so visited
        // page State survives a live shell change.
        final page = LazyPageHost(
          key: _pageHostKey,
          index: _index,
          builders: [
            for (final d in appDestinations)
              () => d.buildPage(widget.api, widget.spotifyPollInterval),
          ],
        );

        final Widget shell = switch (effective) {
          EffectiveAppSurface.mobile => MobileShell(
            destinations: appDestinations,
            currentIndex: _index,
            onSelected: _select,
            page: page,
          ),
          EffectiveAppSurface.desktop => DesktopShell(
            destinations: appDestinations,
            currentIndex: _index,
            onSelected: _select,
            page: page,
            windowClass: windowClass,
            api: widget.api,
          ),
          EffectiveAppSurface.wallPanel => WallPanelShell(
            destinations: appDestinations,
            currentIndex: _index,
            onSelected: _select,
            page: page,
          ),
        };

        return Scaffold(
          body: AppAdaptiveScope(
            windowClass: windowClass,
            effectiveSurface: effective,
            controller: _controller,
            child: shell,
          ),
        );
      },
    );
  }
}
