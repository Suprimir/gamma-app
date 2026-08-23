import 'package:flutter/widgets.dart';

import 'adaptive_layout.dart';
import 'adaptive_surface_preferences.dart';

/// Inherited scope exposing stable adaptive presentation facts to the tree.
///
/// Deliberately holds no business state — only the resolved geometry
/// ([windowClass]), the resolved shell ([effectiveSurface]), and the surface
/// mode [controller]. Shell selection lives in [AppShell]'s own State.
class AppAdaptiveScope extends InheritedWidget {
  const AppAdaptiveScope({
    super.key,
    required this.windowClass,
    required this.effectiveSurface,
    required this.controller,
    required super.child,
  });

  final AppWindowClass windowClass;
  final EffectiveAppSurface effectiveSurface;
  final AdaptiveSurfaceModeController controller;

  bool get isCompact => windowClass.isCompact;
  bool get isDesktopSurface => effectiveSurface == EffectiveAppSurface.desktop;
  bool get isWallPanel => effectiveSurface == EffectiveAppSurface.wallPanel;

  static AppAdaptiveScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppAdaptiveScope>();

  static AppAdaptiveScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No AppAdaptiveScope found in the widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppAdaptiveScope oldWidget) =>
      oldWidget.windowClass != windowClass ||
      oldWidget.effectiveSurface != effectiveSurface ||
      oldWidget.controller != controller;
}
