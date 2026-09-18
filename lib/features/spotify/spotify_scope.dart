import 'package:flutter/widgets.dart';

import 'spotify_player_controller.dart';

/// Exposes the app-wide [SpotifyPlayerController] to every surface (wall music
/// card, sleep chip, desktop dashboard) so they render one canonical state with
/// a single poll/SSE subscription.
///
/// [GammaApp] provides it through `MaterialApp.builder`, above the Navigator, so
/// overlay entries (the sleep overlay) find it too. When absent — tests,
/// previews, a page mounted on its own — surfaces fall back to a locally owned
/// controller.
class SpotifyScope extends InheritedWidget {
  const SpotifyScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SpotifyPlayerController controller;

  static SpotifyPlayerController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpotifyScope>()?.controller;

  @override
  bool updateShouldNotify(SpotifyScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
