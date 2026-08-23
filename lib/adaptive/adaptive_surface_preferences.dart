import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_layout.dart';

/// Owner of the persisted [AppSurfaceMode] preference.
class AdaptiveSurfaceModeController extends ChangeNotifier {
  static const _prefsKey = 'adaptive_surface_mode';

  AppSurfaceMode _value = AppSurfaceMode.auto;

  AppSurfaceMode get value => _value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    _value =
        AppSurfaceMode.values.where((m) => m.name == stored).firstOrNull ??
        AppSurfaceMode.auto;
    notifyListeners();
  }

  Future<void> setMode(AppSurfaceMode mode) async {
    if (_value == mode) return;
    _value = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
