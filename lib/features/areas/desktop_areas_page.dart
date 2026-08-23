import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import 'area_editor.dart';
import '../../data/device_inventory.dart';
import '../../ui/shared_widgets.dart';

/// Espacio de trabajo maestro/detalle de la feature Areas en superficie
/// desktop (F3-C Fase 6): lista de habitaciones a la izquierda, editor
/// embebido a la derecha. La selección vive en el controlador; el formulario
/// es [AreaEditorForm] compartido con la navegación móvil y wall.
class DesktopAreasPage extends StatefulWidget {
  const DesktopAreasPage({super.key, required this.controller});

  final AdaptiveFeatureController controller;

  @override
  State<DesktopAreasPage> createState() => _DesktopAreasPageState();
}

class _DesktopAreasPageState extends State<DesktopAreasPage> {
  // ponytail: feature-specific pane split; desktop surface with insufficient
  // width falls back to list-detail push, never switches the app surface.
  static const _narrowBreakpoint = 880.0;

  @override
  void initState() {
    super.initState();
    // El subtítulo de cada fila cuenta dispositivos del snapshot canónico.
    // Un solo fetch (no duplicado: solo cuando aún no se cargó).
    if (widget.controller.snapshot == null) {
      widget.controller.loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.areasLoading && controller.areas == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.areasError != null && controller.areas == null) {
          return MessageView(
            message: controller.areasError.toString(),
            onRetry: controller.loadAreas,
          );
        }
        final areas = controller.areas!;
        return Material(
          color: AppColors.bg,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < _narrowBreakpoint) {
                return _buildNarrow(areas);
              }
              return _buildMasterDetail(areas);
            },
          ),
        );
      },
    );
  }

  Widget _buildNarrow(List<HomeArea> areas) {
    final controller = widget.controller;
    return _AreaMasterList(
      areas: areas,
      snapshot: controller.snapshot,
      selectedAreaId: null,
      onSelect: (area) => _openNarrowDetail(area),
      onCreate: _create,
    );
  }

  /// Navegación secuencial lista → editor de página completa; al volver
  /// refresca la lista canónica (mismo contrato que la navegación móvil).
  Future<void> _openNarrowDetail(HomeArea area) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(area.name),
          ),
          body: _AreaDetailPane(
            controller: widget.controller,
            areaId: area.id,
            onDeleted: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    await widget.controller.loadAreas();
  }

  Widget _buildMasterDetail(List<HomeArea> areas) {
    final controller = widget.controller;
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: _AreaMasterList(
            areas: areas,
            snapshot: controller.snapshot,
            selectedAreaId: controller.selectedAreaId,
            onSelect: (area) => controller.selectArea(area.id),
            onCreate: _create,
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
        Expanded(child: _AreaDetailPane(controller: controller)),
      ],
    );
  }

  Future<void> _create() async {
    final controller = widget.controller;
    if (controller.areaMutating) return;
    final result = await showDialog<({String name, List<String> aliases})>(
      context: context,
      builder: (_) =>
          AreaEditorDialog(title: 'Nueva área', submitLabel: 'Crear'),
    );
    if (result == null) return;
    try {
      await controller.createArea(result.name, result.aliases);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Área creada.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
      }
    }
  }
}

class _AreaMasterList extends StatelessWidget {
  const _AreaMasterList({
    required this.areas,
    required this.snapshot,
    required this.selectedAreaId,
    required this.onSelect,
    required this.onCreate,
  });

  final List<HomeArea> areas;
  final DeviceInventorySnapshot? snapshot;
  final String? selectedAreaId;
  final ValueChanged<HomeArea> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final countByArea = {
      for (final area in areas)
        area.id: snapshot?.devicesInArea(area.id).length ?? 0,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Habitaciones',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${areas.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva habitación'),
            ),
          ),
        ),
        if (areas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Todavía no hay áreas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
        for (final area in areas) ...[
          _DesktopAreaRow(
            key: ValueKey('desktop-area-${area.id}'),
            title: area.name,
            subtitle: _areaDeviceLabel(countByArea[area.id] ?? 0),
            selected: area.id == selectedAreaId,
            onSelect: () => onSelect(area),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

String _areaDeviceLabel(int count) {
  return count == 1 ? '1 dispositivo' : '$count dispositivos';
}

class _DesktopAreaRow extends StatefulWidget {
  const _DesktopAreaRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_DesktopAreaRow> createState() => _DesktopAreaRowState();
}

class _DesktopAreaRowState extends State<_DesktopAreaRow> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return FocusableActionDetector(
      focusNode: _focusNode,
      enabled: true,
      onFocusChange: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: Semantics(
        selected: selected,
        button: true,
        label: widget.title,
        child: Material(
          color: selected ? AppColors.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onSelect,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _focused ? AppColors.accentStrong : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.place_outlined,
                      size: 17,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaDetailPane extends StatefulWidget {
  const _AreaDetailPane({
    required this.controller,
    this.areaId,
    this.onDeleted,
  });

  final AdaptiveFeatureController controller;

  /// Área explícita (fallback estrecho); null usa la selección del controlador.
  final String? areaId;

  /// Se invoca tras una eliminación exitosa (fallback estrecho: cerrar ruta).
  final VoidCallback? onDeleted;

  @override
  State<_AreaDetailPane> createState() => _AreaDetailPaneState();
}

class _AreaDetailPaneState extends State<_AreaDetailPane> {
  HomeArea? get _area {
    final id = widget.areaId ?? widget.controller.selectedAreaId;
    if (id == null) return null;
    for (final area in widget.controller.areas ?? const <HomeArea>[]) {
      if (area.id == id) return area;
    }
    return null;
  }

  Future<void> _submit(HomeArea area, String name, List<String> aliases) async {
    try {
      await widget.controller.updateArea(area.id, name: name, aliases: aliases);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Área actualizada.')));
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _delete(HomeArea area) async {
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (!confirmed) return;
    try {
      await widget.controller.deleteArea(area.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Área eliminada.')));
        widget.onDeleted?.call();
      }
    } catch (error) {
      if (!mounted) return;
      // 404: el área desapareció concurrentemente — refrescar la lista
      // canónica y reportar el refresh con honestidad (mismo contrato móvil).
      if (error is ApiException && error.statusCode == 404) {
        final refreshed = await widget.controller.loadAreas();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                refreshed
                    ? 'El área ya no existe. Se actualizó la lista.'
                    : 'El área ya no existe, pero no se pudo actualizar la lista.',
              ),
            ),
          );
        }
      } else if (mounted) {
        _showError(error);
      }
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
  }

  @override
  Widget build(BuildContext context) {
    final area = _area;
    final controller = widget.controller;
    if (area == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selecciona un área',
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
              SizedBox(height: 8),
              Text(
                'Elige una habitación de la lista para ver y editar su configuración.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        AreaEditorForm(
          key: ValueKey(area.id),
          initialName: area.name,
          initialAliases: area.aliases,
          submitLabel: 'Guardar',
          busy: controller.areaMutating,
          onSubmit: (name, aliases) => _submit(area, name, aliases),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: controller.areaMutating ? null : () => _delete(area),
          icon: const Icon(Icons.delete_outline, color: AppColors.red),
          label: const Text('Eliminar', style: TextStyle(color: AppColors.red)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.red),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}
