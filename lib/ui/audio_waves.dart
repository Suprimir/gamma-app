import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared equalizer bars used while listening (VAD active).
/// Extracted from `dashboard_page.dart` to be reused on desktop.
class AudioWaves extends StatefulWidget {
  const AudioWaves({super.key, required this.listening});

  final bool listening;

  @override
  State<AudioWaves> createState() => _AudioWavesState();
}

class _AudioWavesState extends State<AudioWaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _barColors = [
    Color(0xE64665C9),
    Color(0xB34F6FDA),
    Color(0xD94665C9),
    Color(0x994F6FDA),
    Color(0xCC4665C9),
  ];

  // Phase offsets to desynchronize bars (approx 0,120,60,180,90 ms on 700ms loop).
  static const _phases = [0.0, 1.07, 0.54, 1.61, 0.80];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(5, (i) {
            final phase = _phases[i];
            final sine = math.sin(t + phase);
            final normalized = (sine + 1) / 2; // 0..1
            final height = 8 + 20 * normalized; // 8..28
            final variedHeight = height + (i.isEven ? 0 : 2 * normalized);
            return Container(
              width: 4,
              height: variedHeight.clamp(8, 28),
              margin: EdgeInsets.only(left: i == 0 ? 0 : 5),
              decoration: BoxDecoration(
                color: _barColors[i],
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        );
      },
    );
  }
}
