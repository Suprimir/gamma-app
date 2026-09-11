import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_theme.dart';

/// Persists and exposes the selected home theme preset.
///
/// Storage key is [storageKey] and the value is the preset [id].
/// All methods are safe to call from any surface; the theme is
/// currently consumed only on desktop.
class HomeThemeController {
  static const String storageKey = 'home_theme_preset';

  /// Loads the persisted preset id, falling back to [HomeThemePreset.claro].
  static Future<String> loadPresetId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    // Validate against known presets to handle stale ids.
    return HomeThemePreset.fromId(stored).id;
  }

  /// Persists the given preset [id].
  static Future<void> savePresetId(String id) async {
    final normalized = HomeThemePreset.fromId(id).id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, normalized);
  }

  /// Reactive notifier for UI that wants to observe preset changes.
  final ValueNotifier<String> presetIdNotifier = ValueNotifier<String>(
    HomeThemePreset.claro.id,
  );

  /// Loads persisted id into [presetIdNotifier].
  Future<void> load() async {
    final id = await loadPresetId();
    presetIdNotifier.value = id;
  }

  /// Persists [id] and updates [presetIdNotifier].
  Future<void> save(String id) async {
    final normalized = HomeThemePreset.fromId(id).id;
    await savePresetId(normalized);
    presetIdNotifier.value = normalized;
  }

  void dispose() {
    presetIdNotifier.dispose();
  }
}
