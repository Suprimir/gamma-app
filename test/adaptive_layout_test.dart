import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';

void main() {
  group('F3-A window class boundaries', () {
    test('599px is compact', () {
      expect(AppWindowClass.fromWidth(599), AppWindowClass.compact);
    });

    test('600px is medium', () {
      expect(AppWindowClass.fromWidth(600), AppWindowClass.medium);
    });

    test('839px is medium', () {
      expect(AppWindowClass.fromWidth(839), AppWindowClass.medium);
    });

    test('840px is expanded', () {
      expect(AppWindowClass.fromWidth(840), AppWindowClass.expanded);
    });

    test('1199px is expanded', () {
      expect(AppWindowClass.fromWidth(1199), AppWindowClass.expanded);
    });

    test('1200px is large', () {
      expect(AppWindowClass.fromWidth(1200), AppWindowClass.large);
    });
  });

  group('F3-A auto-selection matrix', () {
    test('compact Linux resolves to mobile', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.compact,
        mode: AppSurfaceMode.auto,
        platform: TargetPlatform.linux,
      );
      expect(result, EffectiveAppSurface.mobile);
    });

    test('expanded Linux resolves to desktop', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.expanded,
        mode: AppSurfaceMode.auto,
        platform: TargetPlatform.linux,
      );
      expect(result, EffectiveAppSurface.desktop);
    });

    test('compact Android resolves to mobile', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.compact,
        mode: AppSurfaceMode.auto,
        platform: TargetPlatform.android,
      );
      expect(result, EffectiveAppSurface.mobile);
    });

    test('expanded Android resolves to mobile', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.expanded,
        mode: AppSurfaceMode.auto,
        platform: TargetPlatform.android,
      );
      expect(result, EffectiveAppSurface.mobile);
    });

    test('explicit desktop wins on any valid width', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.compact,
        mode: AppSurfaceMode.desktop,
        platform: TargetPlatform.android,
      );
      expect(result, EffectiveAppSurface.desktop);
    });

    test('explicit wallPanel wins on any valid width', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.compact,
        mode: AppSurfaceMode.wallPanel,
        platform: TargetPlatform.android,
      );
      expect(result, EffectiveAppSurface.wallPanel);
    });

    test('auto never yields wallPanel for any class/platform', () {
      for (final windowClass in AppWindowClass.values) {
        for (final platform in TargetPlatform.values) {
          final result = resolveEffectiveAppSurface(
            windowClass: windowClass,
            mode: AppSurfaceMode.auto,
            platform: platform,
          );
          expect(
            result,
            isNot(EffectiveAppSurface.wallPanel),
            reason: '$windowClass on $platform must not infer wallPanel',
          );
        }
      }
    });

    test('explicit mobile wins on large Linux', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.large,
        mode: AppSurfaceMode.mobile,
        platform: TargetPlatform.linux,
      );
      expect(result, EffectiveAppSurface.mobile);
    });

    test('explicit desktop wins on compact Linux', () {
      final result = resolveEffectiveAppSurface(
        windowClass: AppWindowClass.compact,
        mode: AppSurfaceMode.desktop,
        platform: TargetPlatform.linux,
      );
      expect(result, EffectiveAppSurface.desktop);
    });
  });

  group('F3-A helpers', () {
    test('compact is compact, everything else is wide', () {
      expect(AppWindowClass.compact.isCompact, isTrue);
      expect(AppWindowClass.compact.isWide, isFalse);
      for (final windowClass in AppWindowClass.values) {
        if (windowClass != AppWindowClass.compact) {
          expect(windowClass.isCompact, isFalse);
          expect(windowClass.isWide, isTrue);
        }
      }
    });
  });
}
