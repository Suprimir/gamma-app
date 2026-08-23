import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';

/// Calm wall header clock.
///
/// Owns a boundary-aligned one-shot timer so the rest of the wall home never
/// rebuilds when the time changes. Each tick reschedules to the exact next
/// local minute boundary, so a clock started at 08:42:53 updates at 08:43:00,
/// not at 08:43:53. The timer is cancelled in [dispose].
class WallHomeClock extends StatefulWidget {
  const WallHomeClock({super.key, this.now = DateTime.now});

  /// Injectable clock source (tests use a frozen/stepped value).
  final DateTime Function() now;

  @override
  State<WallHomeClock> createState() => _WallHomeClockState();
}

class _WallHomeClockState extends State<WallHomeClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    _scheduleNextMinute();
  }

  @override
  void didUpdateWidget(WallHomeClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The clock source changed identity; realign to the next boundary.
    if (!identical(oldWidget.now, widget.now)) {
      _now = widget.now();
      _scheduleNextMinute();
    }
  }

  void _scheduleNextMinute() {
    _timer?.cancel();
    final now = widget.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final delay = nextMinute.difference(now);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = widget.now());
      _scheduleNextMinute();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _timeLabel(_now),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _dateLabel(_now),
          style: const TextStyle(fontSize: 17, color: AppColors.textDim),
        ),
      ],
    );
  }
}

String _timeLabel(DateTime now) {
  final h = now.hour.toString().padLeft(2, '0');
  final m = now.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _dateLabel(DateTime now) {
  const weekdays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  return '${weekdays[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';
}
