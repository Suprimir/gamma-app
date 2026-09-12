import 'package:flutter/material.dart';

/// Official Spotify brand mark (green disc with the dark arcs) shipped as a
/// shared asset; used as a subtle service indicator on the music cards.
class SpotifyLogo extends StatelessWidget {
  const SpotifyLogo({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/spotify_icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Spotify',
    );
  }
}
