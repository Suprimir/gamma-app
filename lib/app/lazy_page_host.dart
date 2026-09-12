import 'package:flutter/material.dart';

import '../features/dashboard/home_theme_controller.dart';

/// Lazily builds top-level pages on first visit and keeps their State alive.
///
/// Only the current [index]'s page is ever built; visited pages stay mounted
/// (offstage, tickers paused) so returning to them preserves their State.
///
/// Pages read the mutable [AppColors] accent tokens at build time. When the
/// app appearance changes, this host rebuilds every already-visited page from
/// its builder (new widget instances of the same type/key, so State is
/// preserved) so the new accent reaches them without forcing a remount.
class LazyPageHost extends StatefulWidget {
  const LazyPageHost({super.key, required this.builders, required this.index});

  final List<Widget Function()> builders;
  final int index;

  @override
  State<LazyPageHost> createState() => _LazyPageHostState();
}

class _LazyPageHostState extends State<LazyPageHost> {
  final Map<int, Widget> _pages = <int, Widget>{};
  late String _themeId;

  @override
  void initState() {
    super.initState();
    _themeId = HomeThemeController.instance.presetIdNotifier.value;
  }

  void _rebuildForThemeChange() {
    final themeId = HomeThemeController.instance.presetIdNotifier.value;
    if (themeId == _themeId) return;
    _themeId = themeId;
    for (final index in _pages.keys.toList()) {
      _pages[index] = widget.builders[index]();
    }
  }

  @override
  Widget build(BuildContext context) {
    _rebuildForThemeChange();
    _pages.putIfAbsent(widget.index, () => widget.builders[widget.index]());
    return Stack(
      children: [
        for (final entry in _pages.entries)
          Positioned.fill(
            child: Offstage(
              offstage: entry.key != widget.index,
              child: TickerMode(
                enabled: entry.key == widget.index,
                child: entry.value,
              ),
            ),
          ),
      ],
    );
  }
}
