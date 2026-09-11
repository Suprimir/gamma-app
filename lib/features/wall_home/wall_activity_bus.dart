import 'package:flutter/foundation.dart';

/// App-wide user-activity bus for the wall sleep countdown.
///
/// The home page only sees touches inside its own tree, so dialogs, pushed
/// pages, bottom sheets and the touch keyboard (all separate routes above
/// it) never reached its idle timer and sleep could fire mid-task — e.g.
/// while adding a device. A top-level [Listener] (above the Navigator, see
/// `GammaApp.builder`) pokes this bus on every touch, and the home page
/// re-arms its countdown from here.
///
/// [hold]/[release] is a ref-count for hands-free work with no touches
/// (voice dictation): while held, the countdown stays off entirely.
class WallActivityBus {
  WallActivityBus._();

  static final ValueNotifier<int> _pokes = ValueNotifier<int>(0);
  static ValueListenable<int> get pokes => _pokes;

  static final ValueNotifier<int> _holds = ValueNotifier<int>(0);
  static ValueListenable<int> get holds => _holds;

  static bool get held => _holds.value > 0;

  /// Any touch anywhere in the app. Cheap: a single counter bump.
  static void poke() => _pokes.value++;

  static void hold() => _holds.value++;

  static void release() {
    if (_holds.value > 0) _holds.value--;
  }
}
