import 'package:flutter/material.dart';
import 'app_colors.dart';

class HeaderRow extends StatelessWidget {
  const HeaderRow({super.key, required this.title, required this.onRefresh});

  final String title;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
            ),
          ),
        ),
        ToolButton(icon: Icons.refresh, label: 'Actualizar', onTap: onRefresh),
      ],
    );
  }
}

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // InkWell needs a Material ancestor for ink splashes. Wrap in a
    // transparent Material so ToolButton works from any host (even a bare
    // Column without a Scaffold), instead of crashing with
    // "No Material widget found" in release builds.
    final effectiveOnTap = busy
        ? () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Buscando dispositivos...')),
            );
          }
        : onTap;
    final isDisabled = onTap == null && !busy;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      height: 56,
      decoration: BoxDecoration(
        color: filled ? AppColors.accent : null,
        border: filled ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: filled ? Colors.white : AppColors.accent,
              ),
            )
          else
            Icon(
              icon,
              size: 20,
              color: filled ? Colors.white : AppColors.textDim,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: filled ? Colors.white : null,
            ),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: effectiveOnTap,
          borderRadius: BorderRadius.circular(14),
          child: isDisabled
              ? Tooltip(message: 'No disponible', child: content)
              : content,
        ),
      ),
    );
  }
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Touch-first back affordance (>= 56dp) for bare content pages shown as
/// pushed routes. Rail destinations like Dispositivos/Cámaras/Rutinas have
/// no AppBar, so pushing them off the rail would otherwise leave the user
/// with no way back.
class WallBackButton extends StatelessWidget {
  const WallBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back, size: 24),
        label: const Text('Volver'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentStrong,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          minimumSize: const Size(48, 56),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
