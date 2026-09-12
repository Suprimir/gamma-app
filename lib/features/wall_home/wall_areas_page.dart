import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../areas/area_editor.dart';
import '../../data/device_inventory.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../ui/shared_widgets.dart';

/// Gestión touch-first de Habitaciones para la superficie wall (F3-C Fase 7):
/// tarjetas grandes por área, creación con el diálogo compartido y detalle
/// con [AreaEditorForm] en controles grandes más una eliminación secundaria
/// explícita con confirmación (nunca swipe-only ni icono diminuto).
class WallAreasPage extends StatefulWidget {
  WallAreasPage({
    super.key,
    required this.api,
    DeviceInventoryRepository? repository,
  }) : repository = repository ?? HttpDeviceInventoryRepository(api);

  final ApiClient api;
  final DeviceInventoryRepository repository;

  @override
  State<WallAreasPage> createState() => _WallAreasPageState();
}

class _WallAreasPageState extends State<WallAreasPage> {
  late final AdaptiveFeatureController _controller;

  /// Set on the first active load; offstage pages stay inert until activated.
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AdaptiveFeatureController(widget.repository);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted && TickerMode.valuesOf(context).enabled) {
      _loadStarted = true;
      _startLoads();
    }
  }

  /// Loads areas plus the device snapshot the area card counts need.
  void _startLoads() {
    _controller.loadAreas();
    // El subtítulo de cada tarjeta cuenta dispositivos del snapshot canónico.
    if (_controller.snapshot == null) _controller.loadDevices();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openArea(HomeArea area) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _WallAreaDetailPage(controller: _controller, areaId: area.id),
      ),
    );
  }

  Future<void> _create() async {
    if (_controller.areaMutating) return;
    final result = await showDialog<({String name, List<String> aliases})>(
      context: context,
      builder: (_) =>
          AreaEditorDialog(title: 'Nueva área', submitLabel: 'Crear'),
    );
    if (result == null) return;
    try {
      await _controller.createArea(result.name, result.aliases);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.areasLoading && _controller.areas == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_controller.areasError != null && _controller.areas == null) {
          return MessageView(
            message: _controller.areasError.toString(),
            onRetry: _controller.loadAreas,
          );
        }
        // Deferred offstage state: created inactive and never loaded — render
        // inert content instead of dereferencing a null areas list (F3-C III).
        if (_controller.areas == null) {
          return const SizedBox.shrink();
        }
        final areas = _controller.areas!;
        final snapshot = _controller.snapshot;
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: RefreshIndicator(
                  onRefresh: _controller.loadAreas,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
                    children: [
                      _WallAreasHeader(count: areas.length),
                      const SizedBox(height: 18),
                      if (areas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            'Todavía no hay habitaciones.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 16,
                            ),
                          ),
                        )
                      else
                        for (final area in areas) ...[
                          _WallAreaCard(
                            key: ValueKey('wall-area-${area.id}'),
                            area: area,
                            deviceCount: snapshot
                                ?.devicesInArea(area.id)
                                .length,
                            onTap: () => _openArea(area),
                          ),
                          const SizedBox(height: 14),
                        ],
                      const SizedBox(height: 14),
                      _WallNewAreaCard(
                        key: const ValueKey('wall-new-area'),
                        onTap: _create,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WallAreasHeader extends StatelessWidget {
  const _WallAreasHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Habitaciones',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.accentStrong,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta grande y totalmente tappable de área (vocabulario de casa).
class _WallAreaCard extends StatelessWidget {
  const _WallAreaCard({
    super.key,
    required this.area,
    required this.deviceCount,
    required this.onTap,
  });

  final HomeArea area;
  final int? deviceCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.place_outlined,
                  size: 28,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      area.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (deviceCount != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        deviceCount == 1
                            ? '1 dispositivo'
                            : '$deviceCount dispositivos',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Afordancia grande de creación de habitación (>= 72dp de alto).
class _WallNewAreaCard extends StatelessWidget {
  const _WallNewAreaCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 26),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accentTintActive),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: AppColors.accent),
              const SizedBox(width: 10),
              Text(
                'Nueva habitación',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle touch de área: formulario compartido en controles grandes y
/// eliminación secundaria explícita con confirmación. Reutiliza el controlador
/// de la lista (el CRUD ya recarga una sola vez; sin doble fetch al volver).
class _WallAreaDetailPage extends StatefulWidget {
  const _WallAreaDetailPage({required this.controller, required this.areaId});

  final AdaptiveFeatureController controller;
  final String areaId;

  @override
  State<_WallAreaDetailPage> createState() => _WallAreaDetailPageState();
}

class _WallAreaDetailPageState extends State<_WallAreaDetailPage> {
  HomeArea? get _area {
    for (final area in widget.controller.areas ?? const <HomeArea>[]) {
      if (area.id == widget.areaId) return area;
    }
    return null;
  }

  Future<void> _submit(HomeArea area, String name, List<String> aliases) async {
    try {
      await widget.controller.updateArea(area.id, name: name, aliases: aliases);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _delete(HomeArea area) async {
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (!confirmed) return;
    try {
      await widget.controller.deleteArea(area.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(area?.name ?? 'Habitación'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
              children: [
                if (area == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Esta habitación ya no existe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 16),
                    ),
                  )
                else ...[
                  AreaEditorForm(
                    key: ValueKey(area.id),
                    initialName: area.name,
                    initialAliases: area.aliases,
                    submitLabel: 'Guardar',
                    busy: widget.controller.areaMutating,
                    large: true,
                    onSubmit: (name, aliases) => _submit(area, name, aliases),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: widget.controller.areaMutating
                        ? null
                        : () => _delete(area),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.red,
                    ),
                    label: const Text(
                      'Eliminar habitación',
                      style: TextStyle(color: AppColors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.red),
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
