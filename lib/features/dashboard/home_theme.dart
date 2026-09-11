import 'package:flutter/material.dart';

/// Curated background themes for the desktop home (DashboardPage).
///
/// All presets are intentionally light to preserve contrast with
/// [AppColors.text] and [AppColors.orbBlue]. No dark saturated
/// backgrounds are used.
enum HomeThemePreset {
  claro(
    id: 'claro',
    label: 'Claro',
    description: 'Claro y minimalista',
    gradientColors: [Color(0xFFF7F8FA), Color(0xFFEEF1F5)],
    scaffoldColor: Color(0xFFF7F8FA),
  ),
  cielo(
    id: 'cielo',
    label: 'Cielo',
    description: 'Azul cielo puro y celeste claro',
    gradientColors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
    scaffoldColor: Color(0xFFF0F9FF),
  ),
  aurora(
    id: 'aurora',
    label: 'Aurora',
    description: 'Rosa suave y magenta delicado',
    gradientColors: [Color(0xFFFDF2F8), Color(0xFFFCE7F3), Color(0xFFFBCFE8)],
    scaffoldColor: Color(0xFFFDF2F8),
  ),
  neon(
    id: 'neon',
    label: 'Neón',
    description: 'Cian eléctrico y violeta',
    gradientColors: [Color(0xFFDFFBFF), Color(0xFFC9F1FF), Color(0xFFE0D9FF)],
    scaffoldColor: Color(0xFFDFFBFF),
  ),
  volcan(
    id: 'volcan',
    label: 'Volcán',
    description: 'Naranja intenso y coral',
    gradientColors: [Color(0xFFFFF1EA), Color(0xFFFFD9C4), Color(0xFFFFAE8A)],
    scaffoldColor: Color(0xFFFFF1EA),
  ),
  uva(
    id: 'uva',
    label: 'Uva',
    description: 'Violeta profundo y lila',
    gradientColors: [Color(0xFFF2EBFF), Color(0xFFE3D4FF), Color(0xFFC4A8FF)],
    scaffoldColor: Color(0xFFF2EBFF),
  ),
  menta(
    id: 'menta',
    label: 'Menta',
    description: 'Verde eléctrico y lima',
    gradientColors: [Color(0xFFE9FFF3), Color(0xFFC8F7DE), Color(0xFF93E9BE)],
    scaffoldColor: Color(0xFFE9FFF3),
  ),
  sol(
    id: 'sol',
    label: 'Sol',
    description: 'Dorado radiante y ámbar',
    gradientColors: [Color(0xFFFFF9E6), Color(0xFFFFEDBE), Color(0xFFFFD67E)],
    scaffoldColor: Color(0xFFFFF9E6),
  );

  const HomeThemePreset({
    required this.id,
    required this.label,
    required this.description,
    required this.gradientColors,
    required this.scaffoldColor,
  });

  /// Stable string identifier persisted in SharedPreferences.
  final String id;

  /// Display label in Spanish.
  final String label;

  /// Short description in Spanish.
  final String description;

  /// Gradient stops (2-3 colors) for the background.
  final List<Color> gradientColors;

  /// Hint for scaffold background when gradient is not used.
  final Color scaffoldColor;

  /// Text color guidance — all presets use dark text for contrast.
  /// Kept as a getter so callers can style overlays consistently.
  Color get textColor => const Color(0xFF171B23);

  /// All curated presets in display order.
  static List<HomeThemePreset> get allPresets => HomeThemePreset.values;

  /// Resolve preset by [id], falling back to [claro] for unknown ids.
  static HomeThemePreset fromId(String? id) {
    for (final preset in HomeThemePreset.values) {
      if (preset.id == id) return preset;
    }
    return HomeThemePreset.claro;
  }
}
