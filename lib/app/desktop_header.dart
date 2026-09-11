import 'package:flutter/material.dart';

/// GAMMA header bar for desktop surfaces.
/// Height 56, white bg, border bottom. GAMMA bold 16 left,
/// Spacer only (hamburger, bell and gear removed).
class DesktopHeader extends StatelessWidget {
  const DesktopHeader({super.key, this.onNotifications, this.onSettings});

  final VoidCallback? onNotifications;
  final VoidCallback? onSettings;

  static const double kHeight = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0x1A14202D), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(
        children: [
          Text(
            'GAMMA',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF171B23),
            ),
          ),
          Spacer(),
        ],
      ),
    );
  }
}
