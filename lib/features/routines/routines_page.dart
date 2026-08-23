import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import 'routines_editor_page.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/app_colors.dart';

class RoutinesPage extends StatefulWidget {
  const RoutinesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<RoutinesPage> createState() => _RoutinesPageState();
}

class _RoutinesPageState extends State<RoutinesPage> {
  List<Map<String, dynamic>> _routines = [];
  String? _error;
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = widget.api.events().listen((event) {
      if (event['event'] == 'routine_changed') _load();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final routines = await widget.api.routines();
      if (!mounted) return;
      setState(() {
        _routines = routines;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor([String? id]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RoutinesEditorPage(api: widget.api, routineId: id),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> routine) async {
    final id = routine['id'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar rutina'),
        content: const Text(
          '¿Eliminar esta rutina? Esta acción no se puede deshacer.',
        ),
        actions: [
          _DialogButton(
            label: 'Cancelar',
            filled: false,
            onTap: () => Navigator.pop(context, false),
          ),
          _DialogButton(
            label: 'Eliminar',
            filled: true,
            danger: true,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.deleteRoutine(id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView(message: _error!, onRetry: () => _load(refresh: true));
    }
    // En móvil las cards se compactan (menos padding, iconos y botones más
    // chicos) para que el contenido no se salga de la tarjeta.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Rutinas',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.02,
                      ),
                    ),
                  ),
                  ToolButton(
                    icon: Icons.refresh,
                    label: 'Actualizar',
                    onTap: () => _load(refresh: true),
                  ),
                  const SizedBox(width: 10),
                  ToolButton(
                    icon: Icons.add,
                    label: 'Nueva rutina',
                    filled: true,
                    onTap: () => _openEditor(),
                  ),
                ],
              ),
            ),
          ),
          if (_routines.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No hay rutinas configuradas. Crea la primera con «Nueva rutina».',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: MediaQuery.textScalerOf(
                    context,
                  ).scale(compact ? 300 : 330),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RoutineCard(
                    routine: _routines[i],
                    compact: compact,
                    onEdit: () => _openEditor(_routines[i]['id'].toString()),
                    onDelete: () => _confirmDelete(_routines[i]),
                  ),
                  childCount: _routines.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> routine;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final activadores =
        (routine['activadores'] as List?)?.cast<String>() ?? const [];
    final count = (routine['acciones'] as List?)?.length ?? 0;
    final countLabel = '$count ${count == 1 ? 'acción' : 'acciones'}';
    final validationErrors =
        (routine['validation_errors'] as List?)?.cast<String>() ?? const [];
    final triggers = activadores.take(3).toList();
    final extra = activadores.length - triggers.length;

    // Medidas compactas para móvil; las de escritorio quedan como estaban.
    final pad = compact ? 16.0 : 22.0;
    final iconBox = compact ? 44.0 : 52.0;
    final iconSize = compact ? 23.0 : 27.0;
    final titleSize = compact ? 18.0 : 20.0;
    final buttonH = compact ? 48.0 : 56.0;
    final triggerH = compact ? 34.0 : 40.0;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: iconSize,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    routine['nombre']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.02,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    routine['descripcion']?.toString() ?? '',
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textDim,
                    ),
                  ),
                  if (validationErrors.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.32),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Requiere revisión',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (triggers.isNotEmpty) ...[
            SizedBox(
              height: triggerH,
              child: ClipRect(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final trigger in triggers)
                      _triggerPill(
                        '«$trigger»',
                        mic: true,
                        height: triggerH,
                        compact: compact,
                      ),
                    if (extra > 0)
                      _triggerPill(
                        '+$extra',
                        height: triggerH,
                        compact: compact,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _cardButton(
                  label: 'Editar',
                  filled: true,
                  danger: false,
                  icon: Icons.edit_outlined,
                  height: buttonH,
                  compact: compact,
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 10),
              if (compact)
                // En móvil: cuadrado compacto solo con el icono de basura;
                // el resto del ancho queda para el botón de Editar.
                SizedBox(
                  width: buttonH,
                  height: buttonH,
                  child: _cardButton(
                    label: 'Eliminar',
                    filled: false,
                    danger: true,
                    icon: Icons.delete_outline,
                    height: buttonH,
                    compact: compact,
                    iconOnly: true,
                    onTap: onDelete,
                  ),
                )
              else
                Expanded(
                  child: _cardButton(
                    label: 'Eliminar',
                    filled: false,
                    danger: true,
                    icon: Icons.delete_outline,
                    height: buttonH,
                    compact: compact,
                    onTap: onDelete,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _triggerPill(
    String text, {
    bool mic = false,
    required double height,
    bool compact = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mic) ...[
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: AppColors.accentTint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.mic, size: 13, color: AppColors.accent),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w600,
                color: mic ? AppColors.text : AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _cardButton({
    required String label,
    required bool filled,
    required bool danger,
    required VoidCallback onTap,
    required double height,
    required bool compact,
    bool iconOnly = false,
    IconData? icon,
  }) {
    final fg = danger ? AppColors.red : AppColors.accent;
    return SizedBox(
      height: height,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
          decoration: BoxDecoration(
            color: filled ? (danger ? AppColors.red : AppColors.accent) : null,
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(
                    color: danger
                        ? AppColors.red.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: compact ? 18 : 18,
                  color: filled ? Colors.white : fg,
                ),
                if (!iconOnly && !compact) const SizedBox(width: 6),
              ],
              if (!iconOnly)
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: compact ? 12 : 14,
                      color: filled ? Colors.white : fg,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool filled;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.red
        : (filled ? AppColors.accent : AppColors.surfaceRaised);
    return SizedBox(
      height: 56,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: filled ? null : Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}
