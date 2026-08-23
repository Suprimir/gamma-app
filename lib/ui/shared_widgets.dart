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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // InkWell needs a Material ancestor for ink splashes. Wrap in a
    // transparent Material so ToolButton works from any host (even a bare
    // Column without a Scaffold), instead of crashing with
    // "No Material widget found" in release builds.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          height: 56,
          decoration: BoxDecoration(
            color: filled ? AppColors.accent : null,
            border: filled ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
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
