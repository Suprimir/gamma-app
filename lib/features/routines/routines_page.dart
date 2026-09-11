import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../adaptive/adaptive_scope.dart';
import 'routine_actions.dart';
import 'routines_editor_page.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/app_colors.dart';

class RoutinesPage extends StatefulWidget {
  const RoutinesPage({
    super.key,
    required this.api,
    this.showBackButton = false,
  });

  final ApiClient api;

  /// Shows a Volver affordance on top: the page has no AppBar, so pushed
  /// routes (off the rail) would otherwise have no way back.
  final bool showBackButton;

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
    // La lista sí vive dentro del AppAdaptiveScope; la ruta pusheada no,
    // así que el flag táctil se captura acá y se pasa explícito.
    final wallLayout = AppAdaptiveScope.maybeOf(context)?.isWallPanel ?? false;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RoutinesEditorPage(
          api: widget.api,
          routineId: id,
          wallLayout: wallLayout,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Rutina guardada.')));
      }
    }
  }

  /// Enciende o apaga una rutina persistiendo `enabled` con el mismo PUT de
  /// edición. Sin `enabled` en el modelo el switch no tendría dónde vivir.
  Future<void> _toggleEnabled(Map<String, dynamic> routine, bool value) async {
    final id = routine['id'].toString();
    try {
      await widget.api.updateRoutine(id, {
        'nombre': routine['nombre']?.toString() ?? '',
        'descripcion': routine['descripcion']?.toString() ?? '',
        'activadores':
            (routine['activadores'] as List?)?.cast<String>() ?? const [],
        'acciones':
            (routine['acciones'] as List?)?.cast<Map<String, dynamic>>() ??
            const [],
        'enabled': value,
      });
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Rutina activada.' : 'Rutina desactivada.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No se pudo cambiar: $e')));
        }
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> routine) async {
    final id = routine['id'].toString();
    final name = routine['nombre']?.toString().trim() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar rutina'),
        content: Text(
          name.isEmpty
              ? '¿Eliminar esta rutina? Esta acción no se puede deshacer.'
              : '¿Eliminar "$name"? Esta acción no se puede deshacer.',
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
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Rutina eliminada.')));
      }
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
          if (widget.showBackButton)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: WallBackButton(),
              ),
            ),
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
                    icon: CupertinoIcons.refresh,
                    label: 'Actualizar',
                    onTap: () => _load(refresh: true),
                  ),
                  const SizedBox(width: 10),
                  ToolButton(
                    icon: CupertinoIcons.add,
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
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RoutineCard(
                      routine: _routines[i],
                      compact: compact,
                      onEdit: () => _openEditor(_routines[i]['id'].toString()),
                      onDelete: () => _confirmDelete(_routines[i]),
                      onToggle: (value) => _toggleEnabled(_routines[i], value),
                    ),
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

/// Fila horizontal de rutina según la referencia: icono por categoría,
/// nombre + «trigger» · N acciones · estado, switch encender/apagar y menú ⋯
/// (Editar / Eliminar). El tap en la tarjeta abre el editor.
class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final Map<String, dynamic> routine;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = routineEnabled(routine);
    final tile = _tileStyle(routine, enabled);
    final iconBox = compact ? 48.0 : 56.0;
    final iconSize = compact ? 24.0 : 27.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
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
          child: Row(
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: tile.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(tile.icon, size: iconSize, color: tile.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      routine['nombre']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.02,
                        color: enabled ? AppColors.text : AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      routineSubtitle(routine),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: enabled,
                activeThumbColor: AppColors.accent,
                onChanged: onToggle,
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  CupertinoIcons.ellipsis,
                  color: AppColors.textDim,
                ),
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.pencil_outline, size: 18),
                        SizedBox(width: 10),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.trash,
                          size: 18,
                          color: AppColors.red,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Eliminar',
                          style: TextStyle(color: AppColors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La rutina está encendida salvo `enabled: false` explícito. El backend
/// puede no mandar el campo en rutinas viejas: ausente = encendida.
bool routineEnabled(Map<String, dynamic> routine) {
  final value = routine['enabled'];
  if (value is bool) return value;
  return true;
}

/// Subtítulo de la tarjeta: «trigger» · N acciones · desactivada.
/// Sin `last_run` en el modelo no se inventa «última vez».
String routineSubtitle(Map<String, dynamic> routine) {
  final activadores =
      (routine['activadores'] as List?)?.cast<String>() ?? const [];
  final trigger = activadores.isNotEmpty ? activadores.first : '';
  final count = (routine['acciones'] as List?)?.length ?? 0;
  final countLabel = '$count ${count == 1 ? 'acción' : 'acciones'}';
  final head = trigger.isEmpty ? countLabel : '«$trigger» · $countLabel';
  if (!routineEnabled(routine)) return '$head · desactivada';
  final validationErrors =
      (routine['validation_errors'] as List?)?.cast<String>() ?? const [];
  if (validationErrors.isNotEmpty) return '$head · requiere revisión';
  return head;
}

/// Icono y colores del tile según la categoría dominante (primera acción).
/// Apagada: gris parejo como en la referencia.
({Color background, Color foreground, IconData icon}) _tileStyle(
  Map<String, dynamic> routine,
  bool enabled,
) {
  if (!enabled) {
    return (
      background: AppColors.surfaceSoft,
      foreground: AppColors.textDim,
      icon: CupertinoIcons.moon,
    );
  }
  final acciones =
      (routine['acciones'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final category = acciones.isNotEmpty
      ? actionCategory(acciones.first)
      : 'sparkles';
  return switch (category) {
    'device' => (
      background: const Color(0xFFFEF3C7),
      foreground: const Color(0xFFB45309),
      icon: CupertinoIcons.lightbulb,
    ),
    'location' || 'house' => (
      background: const Color(0xFFDBEAFE),
      foreground: const Color(0xFF1D4ED8),
      icon: CupertinoIcons.map,
    ),
    'music' => (
      background: const Color(0xFFEDE9FE),
      foreground: const Color(0xFF6D28D9),
      icon: CupertinoIcons.music_note,
    ),
    'news' => (
      background: const Color(0xFFFFEDD5),
      foreground: const Color(0xFFC2410C),
      icon: CupertinoIcons.news,
    ),
    'camera' => (
      background: const Color(0xFFCCFBF1),
      foreground: const Color(0xFF0F766E),
      icon: CupertinoIcons.videocam,
    ),
    'climate' => (
      background: const Color(0xFFCFFAFE),
      foreground: const Color(0xFF0E7490),
      icon: CupertinoIcons.thermometer,
    ),
    'wait' => (
      background: const Color(0xFFE2E8F0),
      foreground: const Color(0xFF475569),
      icon: CupertinoIcons.clock,
    ),
    'announce' => (
      background: const Color(0xFFFCE7F3),
      foreground: const Color(0xFFBE185D),
      icon: CupertinoIcons.volume_up,
    ),
    'runroutine' => (
      background: const Color(0xFFE0E7FF),
      foreground: const Color(0xFF4338CA),
      icon: CupertinoIcons.play_circle,
    ),
    _ => (
      background: AppColors.accentTint,
      foreground: AppColors.accent,
      icon: CupertinoIcons.sparkles,
    ),
  };
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
