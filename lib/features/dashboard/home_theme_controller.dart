import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/app_colors.dart';
import 'home_theme.dart';

/// Persists and exposes the selected appearance preset.
///
/// Storage key is [storageKey] and the value is the preset [id].
/// [instance] is the app-wide singleton every surface observes and mutates,
/// so a theme picked on any screen recolors the whole app immediately.
class HomeThemeController {
  static const String storageKey = 'home_theme_preset';

  /// App-wide controller used by the root app and every consumer.
  static final HomeThemeController instance = HomeThemeController();

  /// Loads the persisted preset id, falling back to [HomeThemePreset.claro].
  static Future<String> loadPresetId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    // Validate against known presets to handle stale ids.
    return HomeThemePreset.fromId(stored).id;
  }

  /// Applies and persists the given preset [id].
  static Future<void> savePresetId(String id) async {
    final preset = HomeThemePreset.fromId(id);
    // Apply first so the UI and unsaved-change state react immediately;
    // persistence is best-effort right after.
    AppColors.applyAccent(preset.accent);
    instance.presetIdNotifier.value = preset.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, preset.id);
  }

  /// Reactive notifier for UI that wants to observe preset changes.
  final ValueNotifier<String> presetIdNotifier = ValueNotifier<String>(
    HomeThemePreset.claro.id,
  );

  /// Current preset resolved from [presetIdNotifier].
  HomeThemePreset get preset => HomeThemePreset.fromId(presetIdNotifier.value);

  /// Loads persisted id into [presetIdNotifier] and applies its accent.
  Future<void> load() async {
    final id = await loadPresetId();
    AppColors.applyAccent(HomeThemePreset.fromId(id).accent);
    presetIdNotifier.value = id;
  }

  /// Persists [id] and applies it app-wide (notifier + accent tokens).
  Future<void> save(String id) => savePresetId(id);

  void dispose() {
    presetIdNotifier.dispose();
  }
}
