import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/api_client.dart';
import 'spotify_player_controller.dart';
import 'spotify_scope.dart';

/// Resolves the controller a surface should render: the app-wide shared one from
/// [SpotifyScope] when present, otherwise a locally owned fallback (tests,
/// previews, a page mounted without the app shell).
///
/// The owner never disposes or starts polling on the shared controller —
/// [GammaApp] owns its lifecycle — so surfaces can attach and detach without
/// killing the app-wide stream and its SSE subscription.
class SpotifyControllerOwner {
  SpotifyControllerOwner({required this.api, required this.interval});

  final ApiClient api;

  /// Fallback polling cadence used only when this owner creates the controller.
  final Duration interval;

  SpotifyPlayerController? _shared;
  SpotifyPlayerController? _local;
  bool _resolved = false;
  bool _started = false;

  SpotifyPlayerController get controller => _shared ?? _local!;

  /// True when this owner created (and must dispose) the controller.
  bool get ownsController => _shared == null;

  /// Resolves the controller for [context]. Call from `didChangeDependencies`.
  void attach(BuildContext context) {
    final shared = SpotifyScope.maybeOf(context);
    // `_resolved` matters on the first call: with no scope both values are
    // null, so an identity check alone would skip creating the local fallback.
    if (_resolved && identical(shared, _shared)) return;
    _resolved = true;
    _shared = shared;
    if (shared != null) {
      _local?.dispose();
      _local = null;
    } else {
      _local ??= SpotifyPlayerController(api);
    }
  }

  /// Kicks the initial canonical read (idempotent). Only a locally owned
  /// controller is also polled here; the shared one is polled by [GammaApp].
  void start() {
    if (_started) return;
    _started = true;
    unawaited(controller.refresh());
    if (ownsController) controller.startPolling(interval: interval);
  }

  void dispose() {
    _local?.dispose();
    _local = null;
    _shared = null;
  }
}
