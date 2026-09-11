import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_colors.dart';

enum LoopState { idle, listening, processing, speaking, error }

class AssistantOrb extends StatefulWidget {
  const AssistantOrb({super.key, required this.state, required this.onTap});

  final LoopState state;
  final VoidCallback? onTap;

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with TickerProviderStateMixin {
  late final AnimationController _orb = AnimationController(vsync: this);
  bool _pressed = false;

  static const _orbSize = 190.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startAnimations();
  }

  @override
  void didUpdateWidget(covariant AssistantOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _startAnimations();
  }

  @override
  void dispose() {
    _orb.dispose();
    super.dispose();
  }

  void _startAnimations() {
    _orb.stop();
    // Sin reset a 0: la nueva animación arranca desde el valor donde quedó la
    // anterior, así el cambio de estado es continuo. Resetear provocaba un
    // corte visual (la animación vieja se congelaba en seco y la nueva
    // arrancaba de cero) que el ojo percibe como un "pegue".
    if (MediaQuery.disableAnimationsOf(context)) return;
    switch (widget.state) {
      case LoopState.idle:
        _orb.duration = const Duration(milliseconds: 3800);
        _orb.repeat(reverse: true);
      case LoopState.listening:
        _orb.duration = const Duration(milliseconds: 1350);
        _orb.repeat(reverse: true);
      case LoopState.processing:
        _orb.duration = const Duration(milliseconds: 1100);
        _orb.repeat();
      case LoopState.speaking:
        _orb.duration = const Duration(milliseconds: 900);
        _orb.repeat(reverse: true);
      case LoopState.error:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.state == LoopState.error;
    // ColorFiltered solo cuando hay error: sin error es un no-op visual que
    // igualmente paga el filtro de color en cada frame del RepaintBoundary.
    // Sin AnimatedSwitcher: el fade pintaba DOS orbes con sombras blur
    // durante 180ms — medido, el frame de la UI tardaba ~420ms en pintarse
    // (endOfFrame 423/439/414ms). El corte directo es un frame simple.
    // Sombras CONSTANTES (no animadas) + RepaintBoundary separado por capa:
    // el orbe con blur se rasteriza UNA vez y la animación solo aplica
    // transform (scale/rotation) sobre la textura cacheada. Antes las sombras
    // cambiaban con t y el boundary se re-rasterizaba con blur en cada frame
    // (frame de transición medido: 57ms, 36.6ms en UI thread paint).
    Widget orb = SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle outer halo pulsing with _orb — IgnorePointer, behind orb.
          AnimatedBuilder(
            animation: _orb,
            builder: (context, _) {
              // Pulse opacity gently with the breathing animation.
              final t = _orb.value;
              final haloAlpha = isError ? 0.04 : 0.10 + 0.06 * t;
              return IgnorePointer(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.orbBlue.withValues(alpha: haloAlpha),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _orb,
            builder: (context, _) {
              final (scale, rotation) = _orbTransform(_orb.value);
              return Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scale: scale,
                  child: RepaintBoundary(
                    child: Container(
                      width: _orbSize,
                      height: _orbSize,
                      decoration: _orbDecoration,
                      child: const Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            color: Color(0xFF1D2B54),
                            fontSize: 50,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -3.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
    if (isError) {
      orb = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: orb,
      );
    }
    return Semantics(
      button: true,
      label: 'GAMMA',
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: RepaintBoundary(
            child: Opacity(opacity: isError ? 0.64 : 1, child: orb),
          ),
        ),
      ),
    );
  }

  // Sombras constantes para TODOS los estados: si la sombra cambiara con t,
  // el RepaintBoundary del orbe se re-rasterizaría con blur en cada frame.
  // Con sombra fija, la textura se rasteriza una vez y la animación solo
  // aplica transform (scale/rotation) sobre la capa cacheada.
  // Outer halo shadow added for premium depth.
  static final BoxDecoration _orbDecoration = BoxDecoration(
    shape: BoxShape.circle,
    gradient: const RadialGradient(
      center: Alignment(-0.32, -0.44),
      stops: [0, 0.2, 0.53, 1],
      colors: [
        Color(0xFFFFFFFF),
        Color(0xFFE1E8FF),
        Color(0xFF9FB3F2),
        Color(0xFF617BD4),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.orbBlue.withValues(alpha: 0.18),
        blurRadius: 60,
        offset: Offset(0, 0),
      ),
      BoxShadow(
        color: AppColors.orbBlue.withValues(alpha: 0.3),
        blurRadius: 44,
        offset: Offset(0, 13),
      ),
      BoxShadow(
        color: Color(0xCCFFFFFF),
        blurRadius: 12,
        offset: Offset(6, 6),
        blurStyle: BlurStyle.inner,
      ),
    ],
  );

  // Only animates transform (scale/rotation). Shadows stay fixed so the
  // RepaintBoundary is rasterized once and animation is a cheap texture
  // transform. Idle now breathes subtly with scale + tiny rotation.
  (double, double) _orbTransform(double t) {
    switch (widget.state) {
      case LoopState.idle:
        final scale = 1.0 + 0.018 * math.sin(t * math.pi);
        final rotation = math.sin(t * 2 * math.pi) * 0.8 * math.pi / 180;
        return (scale, rotation);
      case LoopState.listening:
        return (1 + 0.035 * t, 0.0);
      case LoopState.processing:
        final wobble = math.sin(t * 2 * math.pi);
        // Wobble + slight scale pulse on top of rotation.
        final scale = 1 + 0.025 * wobble.abs() + 0.012 * t;
        return (scale, wobble * 5 * math.pi / 180);
      case LoopState.speaking:
        return (1 + 0.06 * t, 0.0);
      case LoopState.error:
        return (1.0, 0.0);
    }
  }
}
