import 'package:flutter/foundation.dart';

/// Width-derived window size class. Geometry only — never interaction intent.
enum AppWindowClass {
  compact,
  medium,
  expanded,
  large;

  factory AppWindowClass.fromWidth(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    return large;
  }

  /// True for phone-like windows.
  bool get isCompact => this == compact;

  /// True for any window wider than compact.
  bool get isWide => this != compact;
}

/// Persisted user intent for the app surface.
enum AppSurfaceMode { auto, mobile, desktop, wallPanel }

/// The resolved surface the shell must render.
enum EffectiveAppSurface { mobile, desktop, wallPanel }

/// Resolves the effective surface from geometry, user intent, and platform.
///
/// Explicit modes always win. `auto` falls back to window class for compact
/// widths, then platform: Android/iOS stay mobile, desktop OSes become
/// desktop. Web has no distinct [TargetPlatform]; it defaults from the window
/// class (compact -> mobile, otherwise desktop). wallPanel is never inferred.
EffectiveAppSurface resolveEffectiveAppSurface({
  required AppWindowClass windowClass,
  required AppSurfaceMode mode,
  required TargetPlatform platform,
}) {
  switch (mode) {
    case AppSurfaceMode.mobile:
      return EffectiveAppSurface.mobile;
    case AppSurfaceMode.desktop:
      return EffectiveAppSurface.desktop;
    case AppSurfaceMode.wallPanel:
      return EffectiveAppSurface.wallPanel;
    case AppSurfaceMode.auto:
      break;
  }
  if (windowClass.isCompact) return EffectiveAppSurface.mobile;
  if (kIsWeb) {
    return windowClass.isWide
        ? EffectiveAppSurface.desktop
        : EffectiveAppSurface.mobile;
  }
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return EffectiveAppSurface.mobile;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      return EffectiveAppSurface.desktop;
  }
}
