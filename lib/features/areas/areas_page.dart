import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../adaptive/adaptive_scope.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import 'area_editor.dart';
import 'desktop_areas_page.dart';
import '../../data/device_inventory.dart';
import '../../ui/shared_widgets.dart';

/// F2-C Areas management screen: list, create, edit name/aliases.
///
/// Delete is surfaced truthfully: the F2-A backend exposes no DELETE, so the
/// action reports the limitation instead of faking a client-side cascade.
class AreasPage extends StatefulWidget {
  const AreasPage({super.key, required this.repository});

  final DeviceInventoryRepository repository;

  @override
  State<AreasPage> createState() => _AreasPageState();
}

class _AreasPageState extends State<AreasPage> {
  late final AdaptiveFeatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AdaptiveFeatureController(widget.repository)
      ..addListener(_rebuild)
      ..loadAreas();
  }

  void _rebuild() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  /// Returns `true` when the canonical Areas reload succeeded, `false` when
  /// it failed (so DELETE-404 can report refresh truthfully).
  Future<bool> _load() => _controller.loadAreas();

  Future<void> _create() async {
    if (_controller.areaMutating) return;
    try {
      final result = await showDialog<({String name, List<String> aliases})>(
        context: context,
        builder: (_) =>
            AreaEditorDialog(title: 'Nueva área', submitLabel: 'Crear'),
      );
      if (result == null) return;
      await _controller.createArea(result.name, result.aliases);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Área creada.')));
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _edit(HomeArea area) async {
    if (_controller.areaMutating) return;
    try {
      final result = await showDialog<({String name, List<String> aliases})>(
        context: context,
        builder: (_) => AreaEditorDialog(
          title: 'Editar área',
          submitLabel: 'Guardar',
          initialName: area.name,
          initialAliases: area.aliases,
        ),
      );
      if (result == null) return;
      await _controller.updateArea(
        area.id,
        name: result.name,
        aliases: result.aliases,
      );
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
    if (_controller.areaMutating) return;
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (confirmed != true) return;
    try {
      await _controller.deleteArea(area.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Área eliminada.')));
      }
    } catch (error) {
      if (mounted) {
        // 404: the Area disappeared concurrently — refresh canonical Areas
        // so the stale entry is removed. Report refresh truthfully: only
        // claim "se actualizó" when the reload actually succeeded.
        if (error is ApiException && error.statusCode == 404) {
          final refreshed = await _controller.loadAreas();
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
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppAdaptiveScope.maybeOf(context);
    if (scope != null && scope.isDesktopSurface) {
      return DesktopAreasPage(controller: _controller);
    }
    if (_controller.areasLoading && _controller.areas == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Áreas'),
        actions: [
          IconButton(
            tooltip: 'Nueva área',
            onPressed: _controller.areaMutating ? null : _create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _controller.areasError != null && _controller.areas == null
            ? MessageView(
                message: _controller.areasError.toString(),
                onRetry: _load,
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: _controller.areas == null || _controller.areas!.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.home_work_outlined,
                                  size: 48,
                                  color: AppColors.textFaint,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Todavía no hay áreas.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Crea una para organizar dónde están los dispositivos y qué zona controla cada canal.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textDim,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        itemCount: _controller.areas!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final area = _controller.areas![index];
                          return _AreaRow(
                            area: area,
                            onTap: () => _edit(area),
                            onDelete: () => _delete(area),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.area,
    required this.onTap,
    required this.onDelete,
  });

  final HomeArea area;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      area.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (area.aliases.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Aliases: ${area.aliases.join(', ')}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.textFaint,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
