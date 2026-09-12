import 'package:flutter/material.dart';

/// Spotify brand glyph (green disc + three white arcs) drawn at any size.
///
/// Shared by the desktop and wall music cards as a subtle service indicator.
class SpotifyLogo extends StatelessWidget {
  const SpotifyLogo({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SpotifyLogoPainter()),
    );
  }
}

class _SpotifyLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Designed on a 30x30 grid, scaled by [u] to any size.
    final u = size.shortestSide / 30;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      size.shortestSide / 2,
      Paint()..color = const Color(0xFF1ED760),
    );
    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * u
      ..strokeCap = StrokeCap.round;
    void arc(Offset p0, Offset p1, Offset control) {
      Offset px(Offset p) => center + Offset((p.dx - 15) * u, (p.dy - 15) * u);
      canvas.drawPath(
        Path()
          ..moveTo(px(p0).dx, px(p0).dy)
          ..quadraticBezierTo(
            px(control).dx,
            px(control).dy,
            px(p1).dx,
            px(p1).dy,
          ),
        arcPaint,
      );
    }

    // Three thick arcs rising slightly to the right, longest on top.
    arc(
      const Offset(6.5, 10.5),
      const Offset(23.5, 8.0),
      const Offset(15, 12.8),
    );
    arc(
      const Offset(8.0, 15.5),
      const Offset(22.0, 13.0),
      const Offset(15, 17.6),
    );
    arc(
      const Offset(9.5, 20.0),
      const Offset(20.5, 17.8),
      const Offset(15, 21.6),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
