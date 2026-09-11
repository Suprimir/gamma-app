import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../devices/wall_touch_name_editor.dart';

/// Touch-first area editor for the wall panel, in the same design language
/// as the wall add-device dialog (gradient header, large inputs, >= 56dp
/// action targets). The shared `AreaEditorDialog` chrome doesn't match the
/// panel, so wall surfaces (devices list, home long-press) use this.
///
/// Only the name is editable here (aliases are out of scope on the panel).
/// The name never opens an OS keyboard the panel doesn't have: tapping it
/// shows the wall sheet (built-in finger keyboard + voice dictation, no
/// suggestions).
///
/// Returns `({String name, List<String> aliases})`, or null on cancel.
/// [initialAliases] are preserved as-is so editing a name never wipes them.
Future<({String name, List<String> aliases})?> showWallAreaEditor({
  required BuildContext context,
  required ApiClient api,
  required String title,
  required String subtitle,
  required String submitLabel,
  String initialName = '',
  List<String> initialAliases = const [],
}) {
  return showDialog<({String name, List<String> aliases})>(
    context: context,
    builder: (_) => _WallAreaEditorDialog(
      api: api,
      title: title,
      subtitle: subtitle,
      submitLabel: submitLabel,
      initialName: initialName,
      initialAliases: initialAliases,
    ),
  );
}

/// Centered wall dialog with a small pop-in animation (fade + scale),
/// for option sheets that must appear in the middle of the screen instead
/// of sliding up from the bottom.
Future<T?> showWallCenterDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Centered wall dialog chrome: drag handle, title, optional subtitle and
/// large content, capped to dialog width.
class WallCenterDialog extends StatelessWidget {
  const WallCenterDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle case final text?) ...[
                      const SizedBox(height: 4),
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 15,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Large option row for wall bottom sheets (>= 64dp tall): accent
/// highlight when selected, red variant for destructive actions.
/// Optional [actions] render as trailing icon buttons (e.g. per-area
/// edit/delete) without triggering the row tap.
class WallSheetOption extends StatelessWidget {
  const WallSheetOption({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.destructive = false,
    this.actions,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool destructive;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final iconColor = destructive
        ? AppColors.red
        : selected
        ? AppColors.accent
        : AppColors.textDim;
    final textColor = destructive
        ? AppColors.red
        : selected
        ? AppColors.accentStrong
        : AppColors.text;
    return Material(
      color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, size: 26, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: selected || destructive
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              ...?actions,
              if (selected && !destructive)
                const Icon(Icons.check, size: 24, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _WallAreaEditorDialog extends StatefulWidget {
  const _WallAreaEditorDialog({
    required this.api,
    required this.title,
    required this.subtitle,
    required this.submitLabel,
    required this.initialName,
    required this.initialAliases,
  });

  final ApiClient api;
  final String title;
  final String subtitle;
  final String submitLabel;
  final String initialName;
  final List<String> initialAliases;

  @override
  State<_WallAreaEditorDialog> createState() => _WallAreaEditorDialogState();
}

class _WallAreaEditorDialogState extends State<_WallAreaEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío.');
      return;
    }
    Navigator.of(context).pop((name: name, aliases: widget.initialAliases));
  }

  /// Touch-first name entry: the field never opens an OS keyboard. Tapping
  /// it shows the wall sheet (built-in keyboard + voice dictation, no
  /// suggestions) and puts the confirmed text back here.
  Future<void> _editName() async {
    final result = await showWallSearchEditor(
      context: context,
      api: widget.api,
      initialText: _nameController.text,
      title: 'Nombre del área',
      confirmLabel: 'Listo',
    );
    if (result == null || !mounted) return;
    setState(() {
      _nameController.text = result;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
      actionsPadding: const EdgeInsets.fromLTRB(28, 20, 28, 26),
      title: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7C6FF0), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.place_outlined,
              size: 34,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nombre',
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                readOnly: true,
                showCursor: false,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Toca para escribir o dictar',
                  hintStyle: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 18,
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(
                    color: AppColors.red,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceRaised,
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldBorder,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 22,
                  ),
                  suffixIcon: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.keyboard_outlined,
                      size: 28,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                onTap: _editName,
              ),
              const SizedBox(height: 6),
              const Text(
                'Se abre el teclado táctil con dictado por voz.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textDim,
            minimumSize: const Size(120, 64),
            textStyle: const TextStyle(fontSize: 17),
          ),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 24),
          label: Text(widget.submitLabel),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(200, 64),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
