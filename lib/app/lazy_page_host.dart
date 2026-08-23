import 'package:flutter/material.dart';

/// Lazily builds top-level pages on first visit and keeps their State alive.
///
/// Only the current [index]'s page is ever built; visited pages stay mounted
/// (offstage, tickers paused) so returning to them preserves their State.
class LazyPageHost extends StatefulWidget {
  const LazyPageHost({super.key, required this.builders, required this.index});

  final List<Widget Function()> builders;
  final int index;

  @override
  State<LazyPageHost> createState() => _LazyPageHostState();
}

class _LazyPageHostState extends State<LazyPageHost> {
  final Map<int, Widget> _pages = <int, Widget>{};

  @override
  Widget build(BuildContext context) {
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
