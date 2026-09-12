import 'dart:async';

import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../data/device_capability_commit.dart';
import '../../data/device_inventory.dart';
import 'devices_page.dart';
import 'wall_touch_name_editor.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../ui/device_status.dart';
import '../../ui/shared_widgets.dart';
import '../routines/related_routines.dart';
import '../routines/routines_page.dart';
import '../areas/area_editor.dart';
import '../wall_home/wall_area_editor.dart';

/// Touch-first Devices management for the wall panel surface.
///
/// Owns its own [AdaptiveFeatureController] (same contract as [DevicesPage])
/// and renders large, fully tappable device cards in canonical snapshot order.
/// Desktop parity adapted to fingers: instant search, room filter chips,
/// add-device dialog and discovery live here with >= 56dp targets. Tapping a
/// card opens the household-first wall detail — primary vocabulary only,
/// technical metadata collapsed under 'Información técnica'.
class WallDevicesPage extends StatefulWidget {
  WallDevicesPage({
    super.key,
    required this.api,
    DeviceInventoryRepository? repository,
    this.initialLocationId,
    this.showBackButton = false,
  }) : repository = repository ?? HttpDeviceInventoryRepository(api);

  final ApiClient api;
  final DeviceInventoryRepository repository;

  /// Pre-selected area filter (e.g. coming from Inicio → Ver dispositivos).
  final String? initialLocationId;

  /// Shows a Volver affordance on top: the page has no AppBar, so pushed
  /// routes (off the rail) would otherwise have no way back.
  final bool showBackButton;

  @override
  State<WallDevicesPage> createState() => _WallDevicesPageState();
}

class _WallDevicesPageState extends State<WallDevicesPage> {
  late final AdaptiveFeatureController _controller;

  /// Set on the first active load; offstage pages stay inert until activated.
  bool _loadStarted = false;

  /// Local-only UI filters; never mutate the canonical model and never
  /// become backend queries (same contract as the desktop master pane).
  String _query = '';
  String? _locationId;

  @override
  void initState() {
    super.initState();
    _controller = AdaptiveFeatureController(widget.repository);
    _locationId = widget.initialLocationId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted && TickerMode.valuesOf(context).enabled) {
      _loadStarted = true;
      _controller.loadDevices();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDevice(PhysicalDevice device) async {
    final snapshot = _controller.snapshot;
    if (snapshot == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _WallDeviceDetailPage(
          device: device,
          areas: snapshot.areas,
          gateways: snapshot.gateways,
          repository: _controller.repository,
          api: widget.api,
          onCanonicalDeviceChanged: _controller.applyCanonicalDevice,
          onDelete: () => _controller.removeLocalDevice(device.id),
        ),
      ),
    );
    await _controller.loadDevices();
  }

  /// Opens the 'Sin acceso' overlay: offline devices are excluded from the
  /// main list, so this dialog keeps them reachable. Rows open the same wall
  /// detail as a card tap.
  Future<void> _showOfflineDevices() async {
    final snapshot = _controller.snapshot;
    if (snapshot == null) return;
    final offline = List<PhysicalDevice>.unmodifiable(snapshot.offlineDevices);
    final selected = await showWallCenterDialog<PhysicalDevice>(
      context: context,
      builder: (dialogContext) => WallCenterDialog(
        title: 'Sin acceso',
        children: [
          if (offline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No hay dispositivos sin acceso.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
            )
          else
            for (final device in offline) ...[
              _WallOfflineDeviceRow(
                key: ValueKey('wall-offline-device-${device.id}'),
                device: device,
                areaName: _roomName(snapshot.areas, device.physicalAreaId),
                onTap: () => Navigator.of(dialogContext).pop(device),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
    if (!mounted || selected == null) return;
    await _openDevice(selected);
  }

  /// Wall parity with Habitaciones: creates a new area with the same dialog
  /// style, then reloads so the filter chips converge without leaving
  /// this page.
  Future<void> _showAddAreaDialog() async {
    if (_controller.areaMutating) return;
    final result = await showWallAreaEditor(
      context: context,
      api: widget.api,
      title: 'Nueva área',
      subtitle: 'Creala para organizar tu casa',
      submitLabel: 'Crear',
    );
    if (result == null || !mounted) return;
    try {
      await _controller.createArea(result.name, result.aliases);
      if (!mounted) return;
      unawaited(showWallSuccessSplash(context, message: 'Área creada.'));
      await _controller.loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  /// Wall parity with Habitaciones: edits an area in place, then reloads
  /// so the filter converges without leaving this page.
  Future<void> _editFilterArea(HomeArea area) async {
    final result = await showWallAreaEditor(
      context: context,
      api: widget.api,
      title: 'Editar área',
      subtitle: 'Actualizá el nombre',
      submitLabel: 'Guardar',
      initialName: area.name,
      initialAliases: area.aliases,
    );
    if (result == null || !mounted) return;
    try {
      await _controller.updateArea(
        area.id,
        name: result.name,
        aliases: result.aliases,
      );
      if (!mounted) return;
      unawaited(showWallSuccessSplash(context, message: 'Área actualizada.'));
      await _controller.loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  /// Wall parity with Habitaciones: deletes an area with confirmation,
  /// clearing the filter when it pointed at the deleted area.
  Future<void> _deleteFilterArea(HomeArea area) async {
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (!confirmed || !mounted) return;
    try {
      await _controller.deleteArea(area.id);
      if (!mounted) return;
      if (_locationId == area.id) setState(() => _locationId = null);
      unawaited(showWallSuccessSplash(context, message: 'Área eliminada.'));
      await _controller.loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  /// Desktop parity: discovery runs through the shared controller; the page
  /// only decides the household-language feedback.
  Future<void> _discover() async {
    if (_controller.discovering) return;
    try {
      final ok = await _controller.discover();
      if (!ok || !mounted) return;
      final snapshot = _controller.snapshot!;
      unawaited(
        showWallSuccessSplash(
          context,
          message: snapshot.unassigned.isEmpty
              ? 'No se encontraron dispositivos pendientes.'
              : '${snapshot.unassigned.length} dispositivos pendientes de configurar.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo buscar dispositivos: $error')),
      );
    }
  }

  /// Desktop parity: manual add creates a local device through the shared
  /// controller, without requiring a backend round-trip.
  Future<void> _showAddDeviceDialog() async {
    final areas = _controller.snapshot?.areas ?? const <HomeArea>[];
    final result = await showDialog<_WallAddResult>(
      context: context,
      builder: (_) => _WallAddDeviceDialog(areas: areas, api: widget.api),
    );
    if (result == null || !mounted) return;
    final id = 'dev_manual_${DateTime.now().millisecondsSinceEpoch}';
    final kind = switch (result.type) {
      'Luz' => DeviceKind.light,
      'Enchufe' => DeviceKind.outlet,
      'Sensor' => DeviceKind.sensor,
      'Interruptor' => DeviceKind.switchController,
      _ => DeviceKind.unknown,
    };
    final endpoint = switch (result.type) {
      'Luz' => const DeviceEndpoint(
        id: 'light',
        name: 'Luz',
        kind: DeviceKind.light,
        capabilities: {'on_off', 'brightness'},
      ),
      'Enchufe' => const DeviceEndpoint(
        id: 'outlet',
        name: 'Enchufe',
        kind: DeviceKind.outlet,
        capabilities: {'on_off'},
      ),
      'Sensor' => const DeviceEndpoint(
        id: 'sensor',
        name: 'Sensor',
        kind: DeviceKind.sensor,
        capabilities: {'motion'},
      ),
      'Interruptor' => const DeviceEndpoint(
        id: 'switch',
        name: 'Interruptor',
        kind: DeviceKind.switchController,
        capabilities: {'on_off'},
      ),
      _ => const DeviceEndpoint(
        id: 'channel',
        name: 'Canal',
        kind: DeviceKind.unknown,
        capabilities: {'on_off'},
      ),
    };
    final device = PhysicalDevice(
      id: id,
      name: result.name,
      kind: kind,
      provider: 'Manual',
      providerDeviceId: '',
      model: 'Manual',
      manufacturer: 'Manual',
      physicalAreaId: result.areaId,
      provisioningState: DeviceProvisioningState.configured,
      online: true,
      health: DeviceHealthState.online,
      endpoints: [endpoint],
    );
    _controller.addLocalDevice(device);
    if (!mounted) return;
    unawaited(
      showWallSuccessSplash(
        context,
        message: 'Dispositivo "${result.name}" agregado',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.devicesLoading && _controller.snapshot == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_controller.deviceError != null && _controller.snapshot == null) {
          return MessageView(
            message: 'No se pudieron cargar los dispositivos',
            onRetry: _controller.loadDevices,
          );
        }
        // Deferred offstage state: created inactive and never loaded — render
        // inert content instead of dereferencing a null snapshot (F3-C III).
        if (_controller.snapshot == null) {
          return const SizedBox.shrink();
        }
        final snapshot = _controller.snapshot!;
        final areaById = {for (final area in snapshot.areas) area.id: area};
        final query = _query.trim().toLowerCase();
        final devices = snapshot.userDevices.where((device) {
          final matchesQuery =
              query.isEmpty ||
              (device.userName ?? device.name).toLowerCase().contains(query) ||
              (device.providerName ?? '').toLowerCase().contains(query) ||
              (areaById[device.physicalAreaId]?.name ?? '')
                  .toLowerCase()
                  .contains(query);
          final matchesLocation =
              _locationId == null || device.physicalAreaId == _locationId;
          // Offline devices leave the main list; they stay reachable through
          // the 'Sin acceso' dialog in the header.
          return matchesQuery &&
              matchesLocation &&
              !DeviceInventorySnapshot.isOfflineDevice(device);
        }).toList();
        final filtering = query.isNotEmpty || _locationId != null;
        // Material host: TextField/ChoiceChip/FilledButton below need a
        // Material ancestor even when this page is pushed as a bare route
        // (e.g. from the wall home attention entry, with no Scaffold above).
        return Material(
          color: AppColors.bg,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: RefreshIndicator(
                  onRefresh: _controller.refreshStatesAndReload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
                    children: [
                      if (widget.showBackButton) ...[
                        const WallBackButton(),
                        const SizedBox(height: 6),
                      ],
                      _WallDevicesHeader(
                        count: devices.length,
                        offlineCount: snapshot.offlineDevices.length,
                        onShowOffline: _showOfflineDevices,
                      ),
                      const SizedBox(height: 18),
                      _WallSearchField(
                        query: _query,
                        api: widget.api,
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 14),
                      _WallLocationChips(
                        areas: snapshot.areas,
                        selectedId: _locationId,
                        onSelected: (id) => setState(() => _locationId = id),
                        onEditArea: _editFilterArea,
                        onDeleteArea: _deleteFilterArea,
                      ),
                      const SizedBox(height: 14),
                      _WallListActions(
                        discovering: _controller.discovering,
                        onAdd: _showAddDeviceDialog,
                        onDiscover: _discover,
                        onAddArea: _showAddAreaDialog,
                      ),
                      const SizedBox(height: 18),
                      if (devices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            filtering
                                ? 'Sin resultados'
                                : snapshot.offlineDevices.isNotEmpty
                                ? 'No hay dispositivos activos.'
                                : 'Todavía no hay dispositivos.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 16,
                            ),
                          ),
                        )
                      else
                        for (final device in devices) ...[
                          _WallDeviceCard(
                            key: ValueKey('wall-device-${device.id}'),
                            device: device,
                            roomName: _roomName(
                              snapshot.areas,
                              device.physicalAreaId,
                            ),
                            healthLabel: wallHealthLabel(device.health),
                            commandsSupported:
                                _controller.supportsEndpointCommands,
                            onTap: () => _openDevice(device),
                          ),
                          const SizedBox(height: 14),
                        ],
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

class _WallDevicesHeader extends StatelessWidget {
  const _WallDevicesHeader({
    required this.count,
    required this.offlineCount,
    required this.onShowOffline,
  });

  final int count;
  final int offlineCount;
  final VoidCallback onShowOffline;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Dispositivos',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
            ),
          ),
        ),
        // Icon-only entry to the offline devices overlay; hidden when every
        // device is active.
        if (offlineCount > 0) ...[
          IconButton(
            key: const ValueKey('wall-offline-button'),
            tooltip: 'Dispositivos sin acceso',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            padding: EdgeInsets.zero,
            onPressed: onShowOffline,
            icon: const Icon(
              Icons.wifi_off_rounded,
              size: 24,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(width: 4),
        ],
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

/// Offline device row for the 'Sin acceso' dialog: household name plus area
/// on one tappable surface, matching [WallSheetOption]'s wall language.
class _WallOfflineDeviceRow extends StatelessWidget {
  const _WallOfflineDeviceRow({
    super.key,
    required this.device,
    required this.areaName,
    required this.onTap,
  });

  final PhysicalDevice device;
  final String areaName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 26,
                color: AppColors.textDim,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.userName ?? device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      areaName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Touch-first search: tapping opens the wall sheet (built-in finger
/// keyboard + voice dictation, no suggestions) instead of an OS keyboard
/// the panel doesn't have. Same local-only filter contract as desktop,
/// with a >= 60dp target for fingers.
class _WallSearchField extends StatelessWidget {
  const _WallSearchField({
    required this.query,
    required this.api,
    required this.onChanged,
  });

  final String query;
  final ApiClient api;
  final ValueChanged<String> onChanged;

  Future<void> _edit(BuildContext context) async {
    final result = await showWallSearchEditor(
      context: context,
      api: api,
      initialText: query,
    );
    if (result == null) return;
    onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _edit(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 24, color: AppColors.textDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  query.isEmpty ? 'Buscar dispositivos' : query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: query.isEmpty ? AppColors.textFaint : AppColors.text,
                  ),
                ),
              ),
              if (query.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar búsqueda',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => onChanged(''),
                  icon: const Icon(
                    Icons.clear,
                    size: 22,
                    color: AppColors.textDim,
                  ),
                )
              else
                Icon(
                  Icons.keyboard_outlined,
                  size: 24,
                  color: AppColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Touch-first area filter: desktop parity (the 'Todas las ubicaciones'
/// dropdown) in the wall design language. Null means 'Todas'. Local UI
/// state only, like desktop.
///
/// The closed control is a >= 60dp target; tapping it opens a centered
/// dialog with one large row per option instead of a desktop popup menu.
/// Each area row also carries edit/delete actions to manage areas here.
class _WallLocationChips extends StatefulWidget {
  const _WallLocationChips({
    required this.areas,
    required this.selectedId,
    required this.onSelected,
    required this.onEditArea,
    required this.onDeleteArea,
  });

  final List<HomeArea> areas;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final Future<void> Function(HomeArea area) onEditArea;
  final Future<void> Function(HomeArea area) onDeleteArea;

  @override
  State<_WallLocationChips> createState() => _WallLocationChipsState();
}

class _WallLocationChipsState extends State<_WallLocationChips> {
  String _labelFor(String? id) {
    if (id == null) return 'Todas';
    for (final area in widget.areas) {
      if (area.id == id) return area.name;
    }
    return 'Todas';
  }

  Future<void> _pick() async {
    // '' selects 'Todas' (area ids are never empty); dialog dismissal
    // returns null and changes nothing.
    final result = await showWallCenterDialog<String>(
      context: context,
      builder: (dialogContext) => WallCenterDialog(
        title: 'Ubicación',
        subtitle: 'Filtra los dispositivos por habitación',
        children: [
          WallSheetOption(
            label: 'Todas las ubicaciones',
            icon: Icons.select_all_outlined,
            selected: widget.selectedId == null,
            onTap: () => Navigator.of(dialogContext).pop(''),
          ),
          const SizedBox(height: 10),
          for (final area in widget.areas) ...[
            WallSheetOption(
              label: area.name,
              icon: Icons.place_outlined,
              selected: widget.selectedId == area.id,
              onTap: () => Navigator.of(dialogContext).pop(area.id),
              actions: [
                IconButton(
                  tooltip: 'Editar área',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await widget.onEditArea(area);
                  },
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 22,
                    color: AppColors.textDim,
                  ),
                ),
                IconButton(
                  tooltip: 'Eliminar área',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await widget.onDeleteArea(area);
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 22,
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
    if (!mounted || result == null) return;
    widget.onSelected(result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _pick,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.place_outlined, size: 24, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _labelFor(widget.selectedId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.selectedId != null)
                IconButton(
                  tooltip: 'Mostrar todas',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.onSelected(null),
                  icon: const Icon(
                    Icons.clear,
                    size: 22,
                    color: AppColors.textDim,
                  ),
                )
              else
                const Icon(
                  Icons.expand_more,
                  size: 26,
                  color: AppColors.textDim,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Touch-first list actions: desktop parity (+Agregar, Buscar, +Área) with
/// >= 60dp targets side by side.
class _WallListActions extends StatelessWidget {
  const _WallListActions({
    required this.discovering,
    required this.onAdd,
    required this.onDiscover,
    required this.onAddArea,
  });

  final bool discovering;
  final VoidCallback onAdd;
  final VoidCallback onDiscover;
  final VoidCallback onAddArea;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 24),
            label: const Text(
              'Agregar dispositivo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: discovering ? null : onDiscover,
            icon: discovering
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.radar_outlined, size: 24),
            label: Text(
              discovering ? 'Buscando…' : 'Buscar dispositivos',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentStrong,
              minimumSize: const Size.fromHeight(60),
              side: BorderSide(color: AppColors.accentTintActive),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onAddArea,
            icon: const Icon(Icons.add_home_outlined, size: 24),
            label: const Text(
              'Agregar área',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentStrong,
              minimumSize: const Size.fromHeight(60),
              side: BorderSide(color: AppColors.accentTintActive),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WallAddResult {
  const _WallAddResult({required this.name, required this.type, this.areaId});
  final String name;
  final String type;
  final String? areaId;
}

/// Touch-first add dialog: same fields as desktop (Nombre/Tipo/Ubicación)
/// with large inputs and >= 56dp action targets.
class _WallAddDeviceDialog extends StatefulWidget {
  const _WallAddDeviceDialog({required this.areas, required this.api});
  final List<HomeArea> areas;
  final ApiClient api;
  @override
  State<_WallAddDeviceDialog> createState() => _WallAddDeviceDialogState();
}

class _WallAddDeviceDialogState extends State<_WallAddDeviceDialog> {
  late final TextEditingController _nameController = TextEditingController();
  String _type = 'Luz';
  String? _areaId;
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
    Navigator.of(
      context,
    ).pop(_WallAddResult(name: name, type: _type, areaId: _areaId));
  }

  /// Touch-first name entry: the field never opens an OS keyboard. Tapping
  /// it shows the wall sheet (suggestions + built-in keyboard + voice
  /// dictation) and puts the confirmed text back here.
  Future<void> _editName() async {
    final areaName = _areaName(widget.areas, _areaId);
    final result = await showWallNameEditor(
      context: context,
      api: widget.api,
      initialText: _nameController.text,
      typeLabel: _type,
      areaName: areaName,
    );
    if (result == null || !mounted) return;
    setState(() {
      _nameController.text = result;
      _error = null;
    });
  }

  String? _areaName(List<HomeArea> areas, String? areaId) {
    if (areaId == null) return null;
    for (final area in areas) {
      if (area.id == areaId) return area.name;
    }
    return null;
  }

  DeviceKind _kindFor(String type) => switch (type) {
    'Luz' => DeviceKind.light,
    'Enchufe' => DeviceKind.outlet,
    'Sensor' => DeviceKind.sensor,
    _ => DeviceKind.switchController,
  };

  @override
  Widget build(BuildContext context) {
    final headerIcon = deviceKindMeta(_kindFor(_type)).icon;
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
            child: Icon(headerIcon, size: 34, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agregar dispositivo',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Crealo y ubicalo en tu casa',
                  style: TextStyle(
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
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
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
                'Se abre el teclado táctil con sugerencias y dictado por voz.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Text(
                'Tipo',
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.4,
                children: [
                  for (final entry in const [
                    'Luz',
                    'Enchufe',
                    'Sensor',
                    'Interruptor',
                  ])
                    _WallTypeCard(
                      label: entry,
                      icon: deviceKindMeta(_kindFor(entry)).icon,
                      selected: _type == entry,
                      onTap: () => setState(() => _type = entry),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Esto define qué controles vas a poder usar '
                '(brillo, velocidad, temperatura, etc.).',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Text(
                'Habitación',
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.areas.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _WallAddAreaChip(
                        label: 'Sin área',
                        selected: _areaId == null,
                        onTap: () => setState(() => _areaId = null),
                      );
                    }
                    final area = widget.areas[index - 1];
                    return _WallAddAreaChip(
                      label: area.name,
                      selected: _areaId == area.id,
                      onTap: () => setState(
                        () => _areaId = _areaId == area.id ? null : area.id,
                      ),
                    );
                  },
                ),
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
          icon: const Icon(Icons.add, size: 24),
          label: const Text('Agregar'),
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

/// Big selectable type card for the wall add sheet (>= 88dp tall).
class _WallTypeCard extends StatelessWidget {
  const _WallTypeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 30,
                color: selected ? AppColors.accent : AppColors.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.accentStrong : AppColors.text,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 24, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big room chip for the wall add sheet (>= 56dp tall).
class _WallAddAreaChip extends StatelessWidget {
  const _WallAddAreaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: selected
            ? Icon(Icons.check, size: 22, color: AppColors.accentStrong)
            : const Icon(
                Icons.place_outlined,
                size: 22,
                color: AppColors.textDim,
              ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.accentStrong : AppColors.text,
        ),
        selectedColor: AppColors.accentTint,
        backgroundColor: AppColors.surfaceRaised,
        side: BorderSide(
          color: selected ? AppColors.accent : Colors.transparent,
          width: selected ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

/// Large, fully tappable wall device card. Human vocabulary only: name, room,
/// configuration status, control count and plain-language health.
class _WallDeviceCard extends StatelessWidget {
  const _WallDeviceCard({
    super.key,
    required this.device,
    required this.roomName,
    required this.healthLabel,
    required this.commandsSupported,
    required this.onTap,
  });

  final PhysicalDevice device;
  final String roomName;
  final String? healthLabel;

  /// Whether the repository exposes canonical commands. False keeps the
  /// legacy `powerOn ?? online` pill for plain fakes.
  final bool commandsSupported;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = deviceKindMeta(device.kind);
    final controls = device.endpoints.length;
    final healthColor = _wallHealthColor(device.health);
    final powerState = _wallPowerState(
      device,
      commandsSupported: commandsSupported,
    );
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(meta.icon, size: 28, color: AppColors.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.userName ?? device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (healthLabel != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: healthColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              healthLabel!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: healthColor,
                              ),
                            ),
                          ),
                        ],
                        if (powerState != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: powerState.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              powerState.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: powerState.color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Habitación física: $roomName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.needsConfiguration
                          ? 'Sin configurar'
                          : 'Configurado',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$controls ${controls == 1 ? 'control' : 'controles'}',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Household-first wall detail with desktop parity, adapted to fingers:
/// display name, 'Nombre', power, 'Habitación física', 'Ajustes' per device
/// type (brillo/ventilador/clima/sensor), 'Controles' per endpoint,
/// 'Rutinas relacionadas', 'Probar conexión', 'Eliminar dispositivo' and the
/// technical metadata collapsed under 'Información técnica'. Every control
/// target is >= 56dp; primary vocabulary stays household-first.
/// Outcome of the wall unsaved-changes guard (desktop parity): save the
/// buffered display values, discard them, or cancelled (stay on the page).
enum _WallPendingAction { save, discard }

class _WallDeviceDetailPage extends StatefulWidget {
  const _WallDeviceDetailPage({
    required this.device,
    required this.areas,
    required this.gateways,
    required this.repository,
    required this.api,
    this.onCanonicalDeviceChanged,
    this.onDelete,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final List<GatewayInfo> gateways;
  final DeviceInventoryRepository repository;
  final ApiClient api;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;
  final VoidCallback? onDelete;

  @override
  State<_WallDeviceDetailPage> createState() => _WallDeviceDetailPageState();
}

class _WallDeviceDetailPageState extends State<_WallDeviceDetailPage> {
  late PhysicalDevice _device = widget.device;
  bool _savingPhysicalArea = false;
  String? _savingEndpoint;
  bool _renaming = false;
  bool _identifying = false;
  bool _deleting = false;

  /// Related routines from `GET /api/v1/routines`, filtered by canonical
  /// action `device_id`. Null = unknown (still loading or fetch failed): the
  /// card shows '—', never a fabricated zero.
  int? _relatedRoutineCount;

  /// Desktop parity: display values (power excluded, like desktop) don't
  /// apply instantly — moving a slider only buffers it and arms
  /// Guardar cambios, which converges everything into the shared state.
  /// There is no repository setter for these fields; like desktop's commit,
  /// saving converges the canonical device locally.
  int? _pendingBrightness;
  int? _pendingFanSpeed;
  double? _pendingTargetTemperature;
  String? _pendingClimateMode;
  int? _pendingPosition;
  int? _pendingColorTemperature;
  bool _saving = false;

  bool get _hasPendingChanges =>
      _pendingBrightness != null ||
      _pendingFanSpeed != null ||
      _pendingTargetTemperature != null ||
      _pendingClimateMode != null ||
      _pendingPosition != null ||
      _pendingColorTemperature != null;

  num? _confirmedCapabilityNumber(String capability) {
    final endpoint = firstEndpointWithCapability(_device, capability);
    if (endpoint == null) return null;
    final value = confirmedCapabilityValue(endpoint, capability);
    return value is num ? value : null;
  }

  String? _confirmedCapabilityString(String capability) {
    final endpoint = firstEndpointWithCapability(_device, capability);
    final value = endpoint == null
        ? null
        : confirmedCapabilityValue(endpoint, capability);
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Device with the buffered values applied, for the Ajustes card. Display
  /// preference: pending edit → confirmed canonical observation → demo field.
  PhysicalDevice get _effectiveDevice {
    final observedBrightness = _confirmedCapabilityNumber('BRIGHTNESS');
    final observedSpeed = _confirmedCapabilityNumber('SPEED');
    final observedMode = _confirmedCapabilityString('MODE');
    final observedPosition = _confirmedCapabilityNumber('POSITION');
    final observedColorTemperature = _confirmedCapabilityNumber(
      'COLOR_TEMPERATURE',
    );
    return _device.copyWith(
      brightness:
          _pendingBrightness ??
          observedBrightness?.round() ??
          _device.brightness,
      fanSpeed:
          _pendingFanSpeed ??
          (observedSpeed == null ? null : percentToSpeedLevel(observedSpeed)) ??
          _device.fanSpeed,
      targetTemperature: _pendingTargetTemperature ?? _device.targetTemperature,
      climateMode: _pendingClimateMode ?? observedMode ?? _device.climateMode,
      position:
          _pendingPosition ??
          observedPosition?.round().clamp(0, 100).toInt() ??
          _device.position,
      colorTemperature:
          _pendingColorTemperature ??
          observedColorTemperature?.round().clamp(0, 100).toInt() ??
          _device.colorTemperature,
    );
  }

  void _converge(PhysicalDevice updated) {
    setState(() => _device = updated);
    widget.onCanonicalDeviceChanged?.call(updated);
  }

  @override
  void initState() {
    super.initState();
    _loadRelatedRoutines();
  }

  Future<void> _loadRelatedRoutines() async {
    try {
      final routines = await widget.api.routines().timeout(
        const Duration(milliseconds: 900),
      );
      if (!mounted) return;
      setState(() {
        _relatedRoutineCount = countRelatedRoutines(routines, _device.id);
      });
    } catch (_) {
      // Unknown, never a fabricated zero: the card shows '—'.
      if (!mounted) return;
      setState(() => _relatedRoutineCount = null);
    }
  }

  bool get _isSensor =>
      _wallEffectiveType(_device) == _wallTypeSensor || _device.isGateway;

  bool get _isGateway =>
      _device.isGateway || _device.kind == DeviceKind.gateway;

  /// Whether the repository exposes the canonical command surface. Plain
  /// fakes without commands keep the legacy local behavior untouched.
  bool get _commandsAvailable =>
      asDeviceCommandRepository(widget.repository) != null;

  /// Honest power display: with command support, confirmed observations (or
  /// the demo-only powerOn fallback) decide; unknown is never projected as a
  /// confident off. Without command support the legacy `powerOn ?? online`
  /// behavior is preserved.
  PowerDisplayState get _powerDisplayState {
    if (!_commandsAvailable) {
      final legacyOn = _device.powerOn ?? _device.online;
      return legacyOn ? PowerDisplayState.on : PowerDisplayState.off;
    }
    return devicePowerDisplayState(_device);
  }

  /// Desktop parity: power applies instantly. With command support the
  /// canonical backend is called and only a confirmed observation converges;
  /// without it the legacy local convergence stays as fallback.
  Future<void> _setPower(bool value) async {
    if (!_commandsAvailable) {
      _converge(
        _device.copyWith(
          powerOn: value,
          online: value,
          health: value ? DeviceHealthState.online : DeviceHealthState.sleeping,
        ),
      );
      unawaited(
        showWallSuccessSplash(
          context,
          message: value ? 'Dispositivo encendido' : 'Dispositivo apagado',
        ),
      );
      return;
    }
    final endpoint = _device.endpoints.where(hasPowerCapability).firstOrNull;
    if (endpoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El dispositivo no expone un canal de encendido.'),
        ),
      );
      return;
    }
    final commands = asDeviceCommandRepository(widget.repository);
    if (commands == null) return; // unreachable: guarded by _commandsAvailable
    try {
      final result = await commands.setEndpointPower(
        _device.id,
        endpoint.id,
        value,
      );
      if (!mounted) return;
      if (result.responseParsed &&
          result.observedPower != null &&
          result.observedQuality != null) {
        _converge(
          _device.copyWith(
            endpoints: [
              for (final candidate in _device.endpoints)
                if (candidate.id == endpoint.id)
                  candidate.copyWith(
                    observedPower: result.observedPower,
                    observedQuality: result.observedQuality,
                    observedAt: result.observedAt,
                  )
                else
                  candidate,
            ],
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(powerOutcomeMessage(result, requested: value))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(powerFailureMessage(error))));
    }
  }

  void _setBrightness(double value) {
    setState(() => _pendingBrightness = value.round());
  }

  void _setFanSpeed(int speed) {
    setState(() => _pendingFanSpeed = speed);
  }

  void _setTargetTemperature(double value) {
    setState(() => _pendingTargetTemperature = value);
  }

  void _setClimateMode(String mode) {
    setState(() => _pendingClimateMode = mode);
  }

  void _setPosition(double value) {
    setState(() => _pendingPosition = value.round());
  }

  void _setColorTemperature(double value) {
    setState(() => _pendingColorTemperature = value.round());
  }

  /// Desktop parity: saves the buffered values at once. With a command-capable
  /// repository the capability-backed fields execute canonical actions through
  /// the shared commit helper and confirmed observations converge back; without
  /// one the legacy local convergence stays as fallback. Target temperature has
  /// no backend action and always converges locally (documented contract gap).
  Future<void> _saveAll() async {
    if (_saving || !_hasPendingChanges) return;
    setState(() => _saving = true);
    final commands = asDeviceCommandRepository(widget.repository);
    try {
      if (commands == null) {
        _converge(_effectiveDevice);
        _clearPending();
        if (!mounted) return;
        unawaited(
          showWallSuccessSplash(
            context,
            message: 'Cambios realizados correctamente',
          ),
        );
        return;
      }
      final result = await commitCapabilityFields(
        commands: commands,
        device: _device,
        brightness: _pendingBrightness,
        fanSpeed: _pendingFanSpeed,
        climateMode: _pendingClimateMode,
        position: _pendingPosition,
        colorTemperature: _pendingColorTemperature,
      );
      if (!mounted) return;
      var updated = result.device;
      if (_pendingTargetTemperature != null) {
        updated = updated.copyWith(
          targetTemperature: _pendingTargetTemperature,
        );
      }
      _converge(updated);
      _clearPending();
      final notice = result.notice;
      unawaited(
        showWallSuccessSplash(
          context,
          message: notice ?? 'Cambios realizados correctamente',
        ),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearPending() {
    setState(() {
      _pendingBrightness = null;
      _pendingFanSpeed = null;
      _pendingTargetTemperature = null;
      _pendingClimateMode = null;
      _pendingPosition = null;
      _pendingColorTemperature = null;
    });
  }

  Future<void> _renameDevice() async {
    if (_renaming) return;
    setState(() => _renaming = true);
    try {
      final result = await showDialog<_WallRenameResult>(
        context: context,
        builder: (_) => _WallRenameDialog(
          title: 'Cambiar nombre del dispositivo',
          initialName: _device.userName,
          fallbackName: _device.name,
          canReset: _device.userName != null,
        ),
      );
      if (result is! _WallRenameSet && result is! _WallRenameClear) return;
      final userName = result is _WallRenameSet ? result.name : null;
      final updated = await widget.repository.renameDevice(
        _device.id,
        userName,
      );
      _converge(updated);
      if (mounted) {
        unawaited(
          showWallSuccessSplash(context, message: 'Nombre actualizado'),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  Future<void> _renameEndpoint(DeviceEndpoint endpoint) async {
    if (_renaming) return;
    setState(() => _renaming = true);
    try {
      final result = await showDialog<_WallRenameResult>(
        context: context,
        builder: (_) => _WallRenameDialog(
          title: 'Cambiar nombre del control',
          initialName: endpoint.userName,
          fallbackName: endpoint.displayName,
          canReset: endpoint.userName != null,
        ),
      );
      if (result is! _WallRenameSet && result is! _WallRenameClear) return;
      final userName = result is _WallRenameSet ? result.name : null;
      final updated = await widget.repository.renameEndpoint(
        _device.id,
        endpoint.id,
        userName,
      );
      _converge(updated);
      if (mounted) {
        unawaited(
          showWallSuccessSplash(context, message: 'Nombre actualizado'),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  Future<void> _setPhysicalArea(String? areaId) async {
    setState(() => _savingPhysicalArea = true);
    try {
      final updated = await widget.repository.assignPhysicalArea(
        _device.id,
        areaId,
      );
      _converge(updated);
      if (mounted) {
        unawaited(
          showWallSuccessSplash(context, message: 'Habitación actualizada'),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingPhysicalArea = false);
    }
  }

  Future<void> _setEndpointArea(DeviceEndpoint endpoint, String? areaId) async {
    if (_savingEndpoint != null) return;
    setState(() => _savingEndpoint = endpoint.id);
    try {
      final updated = await widget.repository.assignEndpointArea(
        _device.id,
        endpoint.id,
        areaId,
      );
      _converge(updated);
      if (mounted) {
        unawaited(
          showWallSuccessSplash(context, message: 'Control actualizado'),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingEndpoint = null);
    }
  }

  Future<void> _setEndpointRole(DeviceEndpoint endpoint, String? role) async {
    if (_savingEndpoint != null) return;
    setState(() => _savingEndpoint = endpoint.id);
    try {
      final updated = await widget.repository.assignEndpointSemanticRole(
        _device.id,
        endpoint.id,
        role,
      );
      _converge(updated);
      if (mounted) {
        unawaited(
          showWallSuccessSplash(context, message: 'Control actualizado'),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingEndpoint = null);
    }
  }

  Future<void> _applyPhysicalAreaToEndpoints() async {
    final areaId = _device.physicalAreaId;
    if (areaId == null || _savingEndpoint != null) return;
    setState(() => _savingEndpoint = '__all__');
    try {
      var updated = _device;
      for (final endpoint in _device.endpoints) {
        updated = await widget.repository.assignEndpointArea(
          _device.id,
          endpoint.id,
          areaId,
        );
        _converge(updated);
      }
      if (mounted) {
        unawaited(
          showWallSuccessSplash(
            context,
            message: 'Habitación aplicada a los controles',
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingEndpoint = null);
    }
  }

  /// Desktop parity: device identify with household-language feedback.
  Future<void> _testConnection() async {
    if (_identifying) return;
    setState(() => _identifying = true);
    try {
      final result = await identifyDeviceWithFallback(
        widget.repository,
        _device.id,
      );
      if (!mounted) return;
      if (!result.supported) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(identifyUnsupportedMessage(result))),
        );
        return;
      }
      unawaited(
        showWallSuccessSplash(
          context,
          message: 'Conexión correcta con el dispositivo.',
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      unawaited(
        showWallSuccessSplash(
          context,
          message: 'Orden de identificación enviada (simulada)',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _identifying = false);
    }
  }

  /// Desktop parity: local-only removal with explicit confirmation.
  Future<void> _deleteDevice() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Eliminar dispositivo',
          style: TextStyle(fontSize: 20),
        ),
        content: Text(
          '¿Eliminar "${_device.userName ?? _device.name}" de la lista? '
          'Esta acción solo lo quita de la vista local.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size(96, 56),
              textStyle: const TextStyle(fontSize: 16),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(128, 56),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    widget.onDelete?.call();
    if (!mounted) return;
    // The device is going away: drop buffered display values so the
    // unsaved-changes guard doesn't intercept the pop below.
    _discardPending();
    // The splash sits above this route and dismisses itself; only then the
    // detail pops, so the dialog is never mistaken for the route pop.
    await showWallSuccessSplash(context, message: 'Dispositivo eliminado');
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _openRoutines() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinesPage(api: widget.api, showBackButton: true),
      ),
    );
  }

  /// Desktop parity: buffers are lost when the route pops, so leaving with
  /// pending display values asks first (Guardar / Descartar / Cancelar)
  /// instead of silently discarding them.
  void _discardPending() {
    if (!_hasPendingChanges) return;
    setState(() {
      _pendingBrightness = null;
      _pendingFanSpeed = null;
      _pendingTargetTemperature = null;
      _pendingClimateMode = null;
      _pendingPosition = null;
      _pendingColorTemperature = null;
    });
  }

  Future<_WallPendingAction?> _showUnsavedChangesDialog() {
    return showDialog<_WallPendingAction>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Guardar cambios',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Tienes cambios sin guardar en este dispositivo. '
          '¿Qué quieres hacer?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_WallPendingAction.discard),
            style: TextButton.styleFrom(
              minimumSize: const Size(96, 56),
              textStyle: const TextStyle(fontSize: 16),
            ),
            child: const Text('Descartar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(96, 56),
              textStyle: const TextStyle(fontSize: 16),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_WallPendingAction.save),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(128, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showError(Object error) {
    final body = error is ApiException ? error.body : null;
    final detail = body is Map ? body['detail'] : null;
    final message = detail != null
        ? detail.toString()
        : error is ApiException
        ? 'Error del servidor (${error.statusCode}).'
        : error.toString();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _busySnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guardando cambios, espera un momento...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    GatewayInfo? gateway;
    for (final candidate in widget.gateways) {
      if (candidate.id == _device.gatewayId) {
        gateway = candidate;
        break;
      }
    }
    return PopScope(
      // Desktop parity: buffered display values die with the route, so a
      // back navigation with pending changes asks first (Guardar /
      // Descartar / Cancelar) instead of silently discarding them.
      canPop: !_hasPendingChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final action = await _showUnsavedChangesDialog();
        if (!mounted || action == null) return;
        switch (action) {
          case _WallPendingAction.discard:
            _discardPending();
            if (mounted) navigator.pop();
          case _WallPendingAction.save:
            await _saveAll();
            if (!mounted || _hasPendingChanges) return;
            navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          title: const Text('Configurar dispositivo'),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              // SingleChildScrollView builds every section up front (never
              // lazy): all labels exist at any text scale, with natural
              // heights and no clipping.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WallDeviceHero(device: _device, onRename: _renameDevice),
                    const SizedBox(height: 14),
                    _WallPowerCard(
                      device: _device,
                      powerState: _powerDisplayState,
                      isSensor: _isSensor,
                      isGateway: _isGateway,
                      onPowerChanged: _setPower,
                    ),
                    const SizedBox(height: 14),
                    _WallCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _WallAreaDropdown(
                            key: const Key('physical-area-dropdown'),
                            label: 'Habitación física',
                            value: _device.physicalAreaId,
                            areas: widget.areas,
                            enabled: !_savingPhysicalArea,
                            onChanged: _setPhysicalArea,
                          ),
                          if (_device.physicalAreaId != null &&
                              _device.endpoints.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _savingEndpoint == null
                                  ? _applyPhysicalAreaToEndpoints
                                  : _busySnack,
                              icon: const Icon(
                                Icons.copy_all_outlined,
                                size: 22,
                              ),
                              label: const Text(
                                'Usar también para todos los controles',
                                style: TextStyle(fontSize: 15),
                              ),
                              style: TextButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _WallAdjustCard(
                      device: _effectiveDevice,
                      commandsAvailable: _commandsAvailable,
                      onBrightnessChanged: _setBrightness,
                      onFanSpeedChanged: _setFanSpeed,
                      onTemperatureChanged: _setTargetTemperature,
                      onClimateModeChanged: _setClimateMode,
                      onPositionChanged: _setPosition,
                      onColorTemperatureChanged: _setColorTemperature,
                    ),
                    const SizedBox(height: 14),
                    _WallCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Controles',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (
                            var index = 0;
                            index < _device.endpoints.length;
                            index++
                          ) ...[
                            _WallEndpointEditor(
                              endpoint: _device.endpoints[index],
                              areas: widget.areas,
                              busy:
                                  _savingEndpoint ==
                                  _device.endpoints[index].id,
                              onAreaChanged: (areaId) => _setEndpointArea(
                                _device.endpoints[index],
                                areaId,
                              ),
                              onRoleChanged:
                                  widget.repository.supportsSemanticRole
                                  ? (role) => _setEndpointRole(
                                      _device.endpoints[index],
                                      role,
                                    )
                                  : null,
                              onRename: () =>
                                  _renameEndpoint(_device.endpoints[index]),
                            ),
                            if (index != _device.endpoints.length - 1)
                              const Divider(
                                height: 32,
                                color: AppColors.border,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _WallRoutinesCard(
                      relatedCount: _relatedRoutineCount,
                      onCreate: _openRoutines,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _identifying ? null : _testConnection,
                      icon: _identifying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.wifi_find_outlined, size: 24),
                      label: Text(
                        _identifying ? 'Probando…' : 'Probar conexión',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(64),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _deleting ? null : _deleteDevice,
                      icon: const Icon(Icons.delete_outline, size: 24),
                      label: const Text(
                        'Eliminar dispositivo',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red.withValues(alpha: 0.12),
                        foregroundColor: AppColors.red,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size.fromHeight(64),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final canSave = _hasPendingChanges && !_saving;
                        return FilledButton.icon(
                          onPressed: canSave ? _saveAll : null,
                          icon: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check, size: 24),
                          label: Text(
                            _saving ? 'Guardando…' : 'Guardar cambios',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.accent
                                .withValues(alpha: 0.4),
                            minimumSize: const Size.fromHeight(64),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _WallTechnicalSection(gateway: gateway, device: _device),
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

/// Device-level types driving the 'Ajustes' section. Fan and climate have no
/// [DeviceKind] counterpart: they are refinements over a generically detected
/// device (same derivation as the desktop detail pane).
const _wallTypeLight = 'light';
const _wallTypeOutlet = 'outlet';
const _wallTypeSwitch = 'switch';
const _wallTypeBlinds = 'blinds';
const _wallTypeFan = 'fan';
const _wallTypeClimate = 'climate';
const _wallTypeSensor = 'sensor';

/// Effective device type: explicit semantic role wins, then the backend
/// device class, then the device kind.
String _wallEffectiveType(PhysicalDevice device) {
  for (final endpoint in device.endpoints) {
    final role = endpoint.semanticRole?.toLowerCase();
    if (role == null || role.isEmpty) continue;
    switch (role) {
      case 'light':
        return _wallTypeLight;
      case 'switch':
        return _wallTypeSwitch;
      case 'fan':
      case 'extractor':
        return _wallTypeFan;
      case 'sensor':
        return _wallTypeSensor;
      case 'outlet':
        return _wallTypeOutlet;
      case 'climate':
        return _wallTypeClimate;
      case 'cover':
      case 'blind':
      case 'blinds':
      case 'shutter':
      case 'curtain':
        return _wallTypeBlinds;
    }
  }
  switch (device.deviceClass.toLowerCase()) {
    case 'light':
      return _wallTypeLight;
    case 'switch':
    case 'relay':
      return _wallTypeSwitch;
    case 'outlet':
      return _wallTypeOutlet;
    case 'fan':
      return _wallTypeFan;
    case 'climate':
    case 'ac':
    case 'thermostat':
      return _wallTypeClimate;
    case 'sensor':
      return _wallTypeSensor;
    case 'cover':
    case 'blind':
    case 'blinds':
    case 'shutter':
    case 'curtain':
      return _wallTypeBlinds;
  }
  // Position capability without role/class metadata: a generically detected
  // blind must still resolve to its real control.
  if (device.endpoints.any(
    (endpoint) =>
        endpoint.capabilities.contains('POSITION') ||
        endpoint.capabilityDetails.containsKey('POSITION'),
  )) {
    return _wallTypeBlinds;
  }
  return switch (device.kind) {
    DeviceKind.light => _wallTypeLight,
    DeviceKind.outlet => _wallTypeOutlet,
    DeviceKind.sensor => _wallTypeSensor,
    _ => _wallTypeSwitch,
  };
}

/// Touch-first power/state card (desktop header parity): a large switch for
/// controllable devices, the sensor reading for sensors, and honest,
/// never-faked state text otherwise. No raw ON/OFF vocabulary.
class _WallPowerCard extends StatelessWidget {
  const _WallPowerCard({
    required this.device,
    required this.powerState,
    required this.isSensor,
    required this.isGateway,
    required this.onPowerChanged,
  });

  final PhysicalDevice device;
  final PowerDisplayState powerState;
  final bool isSensor;
  final bool isGateway;
  final ValueChanged<bool> onPowerChanged;

  @override
  Widget build(BuildContext context) {
    if (isGateway) {
      return _WallCard(
        child: Row(
          children: [
            Icon(Icons.hub_outlined, size: 30, color: AppColors.accent),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Este gateway conecta tus dispositivos. No tiene controles: '
                'su estado se gestiona solo.',
                style: TextStyle(color: AppColors.textDim, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }
    if (isSensor) {
      return _WallCard(
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.sensors_outlined,
                size: 30,
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.sensorValue ?? 'Sin datos recientes',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Valor actual reportado (solo lectura)',
                    style: TextStyle(color: AppColors.textDim, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // Power requires a real power channel (canonical POWER or legacy on_off);
    // devices without one get an honest read-only card instead of a fake
    // switch.
    if (!device.endpoints.any(hasPowerCapability)) {
      return const _WallCard(
        child: Row(
          children: [
            Icon(Icons.power_off_outlined, size: 30, color: AppColors.textDim),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Este dispositivo no expone un canal de encendido.',
                style: TextStyle(color: AppColors.textDim, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }
    // Capability-based (not health-based): turning the device off sets
    // health to sleeping, which must not hide the way back on.
    // Unknown power is never shown as a confident off: the label carries the
    // truth ('Sin datos') while the action stays enabled to command it.
    final isOn = powerState == PowerDisplayState.on;
    final stateColor = switch (powerState) {
      PowerDisplayState.on => AppColors.green,
      PowerDisplayState.off => AppColors.red,
      PowerDisplayState.unknown => AppColors.textDim,
    };
    final stateLabel = switch (powerState) {
      PowerDisplayState.on => 'Encendido',
      PowerDisplayState.off => 'Apagado',
      PowerDisplayState.unknown => 'Sin datos',
    };
    final actionColor = isOn ? AppColors.red : AppColors.green;
    return _WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  switch (powerState) {
                    PowerDisplayState.on => Icons.power_outlined,
                    PowerDisplayState.off => Icons.power_off_outlined,
                    PowerDisplayState.unknown => Icons.help_outline,
                  },
                  size: 30,
                  color: stateColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stateLabel,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: stateColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      powerState == PowerDisplayState.unknown
                          ? 'El dispositivo todavía no reportó su estado.'
                          : 'Toca el botón para cambiarlo',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => onPowerChanged(!isOn),
            icon: Icon(
              isOn ? Icons.power_settings_new_outlined : Icons.power_outlined,
              size: 24,
            ),
            label: Text(
              isOn ? 'Apagar' : 'Encender',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Touch-first area dropdown: label + >= 64dp field, household language.
class _WallAreaDropdown extends StatelessWidget {
  const _WallAreaDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.areas,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<HomeArea> areas;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dropdown = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          style: const TextStyle(color: AppColors.text, fontSize: 17),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceRaised,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 22,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Sin asignar'),
            ),
            for (final area in areas)
              DropdownMenuItem<String?>(value: area.id, child: Text(area.name)),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
    if (!enabled) {
      return Tooltip(
        message: 'Guardando cambios, espera un momento...',
        child: dropdown,
      );
    }
    return dropdown;
  }
}

/// Canonical semantic-role options. Only backend-supported roles appear;
/// 'Sin configurar' clears the override.
const _wallRoleOptions = <String, String>{
  'light': 'Luz',
  'switch': 'Interruptor',
  'fan': 'Ventilador',
  'extractor': 'Extractor',
  'sensor': 'Sensor',
};

/// Touch-first 'Qué controla' selector with a >= 64dp target.
class _WallRoleDropdown extends StatelessWidget {
  const _WallRoleDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value ?? 'unknown';
    final dropdown = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Qué controla',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _wallRoleOptions.containsKey(current) ? current : null,
          isExpanded: true,
          style: const TextStyle(color: AppColors.text, fontSize: 17),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceRaised,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 22,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Sin configurar'),
            ),
            for (final entry in _wallRoleOptions.entries)
              DropdownMenuItem<String?>(
                value: entry.key,
                child: Text(entry.value),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
    if (!enabled) {
      return Tooltip(
        message: 'Guardando cambios, espera un momento...',
        child: dropdown,
      );
    }
    return dropdown;
  }
}

String _wallRoleSourceLabel(DeviceEndpoint endpoint) {
  switch (endpoint.semanticRoleSource) {
    case 'user':
      return 'Configurado manualmente';
    case 'provider':
      return 'Detectado automáticamente';
    default:
      return 'Sin configurar';
  }
}

/// Touch-first 'Ajustes' card (desktop 'Controles' parity): type-specific
/// controls bound to the canonical capability actions. Gateways and sensors
/// skip this card.
class _WallAdjustCard extends StatelessWidget {
  const _WallAdjustCard({
    required this.device,
    required this.commandsAvailable,
    required this.onBrightnessChanged,
    required this.onFanSpeedChanged,
    required this.onTemperatureChanged,
    required this.onClimateModeChanged,
    required this.onPositionChanged,
    required this.onColorTemperatureChanged,
  });

  final PhysicalDevice device;
  final bool commandsAvailable;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<int> onFanSpeedChanged;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<String> onClimateModeChanged;
  final ValueChanged<double> onPositionChanged;
  final ValueChanged<double> onColorTemperatureChanged;

  @override
  Widget build(BuildContext context) {
    if (device.isGateway || device.kind == DeviceKind.gateway) {
      return const SizedBox.shrink();
    }
    final type = _wallEffectiveType(device);
    if (type == _wallTypeSensor) {
      return const SizedBox.shrink();
    }
    final modeOptions = capabilityModeOptions(
      endpoint: firstEndpointWithCapability(device, 'MODE'),
      commandsAvailable: commandsAvailable,
      selected: device.climateMode ?? 'cold',
    );
    final showColorTemperature =
        firstEndpointWithCapability(
          device,
          'COLOR_TEMPERATURE',
        )?.capabilityDetails.containsKey('COLOR_TEMPERATURE') ??
        false;
    return _WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ajustes',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          switch (type) {
            _wallTypeBlinds => _WallPositionControl(
              position: ((device.position ?? 0).toDouble()),
              onChanged: onPositionChanged,
            ),
            _wallTypeLight => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WallBrightnessControl(
                  brightness: ((device.brightness ?? 80).toDouble()),
                  onChanged: onBrightnessChanged,
                ),
                if (showColorTemperature) ...[
                  const SizedBox(height: 16),
                  _WallColorTemperatureControl(
                    colorTemperature: ((device.colorTemperature ?? 50)
                        .toDouble()),
                    onChanged: onColorTemperatureChanged,
                  ),
                ],
              ],
            ),
            _wallTypeFan => _WallFanControls(
              fanSpeed: device.fanSpeed ?? 2,
              onChanged: onFanSpeedChanged,
            ),
            _wallTypeClimate => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WallTemperatureControl(
                  targetTemperature: device.targetTemperature ?? 22,
                  onChanged: onTemperatureChanged,
                ),
                const SizedBox(height: 16),
                _WallClimateModeChips(
                  mode: device.climateMode ?? 'cold',
                  options: modeOptions,
                  onChanged: onClimateModeChanged,
                ),
                const SizedBox(height: 16),
                _WallFanControls(
                  fanSpeed: device.fanSpeed ?? 2,
                  onChanged: onFanSpeedChanged,
                  label: 'Velocidad del ventilador',
                ),
              ],
            ),
            _ => const Text(
              'Sin controles adicionales para este tipo.',
              style: TextStyle(color: AppColors.textDim, fontSize: 16),
            ),
          },
        ],
      ),
    );
  }
}

/// Shared wall percent slider used by the capability-backed controls
/// (brightness, position, color temperature). 0-100 with 20 divisions.
class _WallPercentControl extends StatelessWidget {
  const _WallPercentControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 15),
            ),
            const Spacer(),
            Text(
              '${value.round()} %',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 17),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 32),
          ),
          child: Slider(
            value: value.clamp(0, 100),
            min: 0,
            max: 100,
            divisions: 20,
            label: '${value.round()} %',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _WallBrightnessControl extends StatelessWidget {
  const _WallBrightnessControl({
    required this.brightness,
    required this.onChanged,
  });

  final double brightness;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _WallPercentControl(
      label: 'Brillo',
      value: brightness,
      onChanged: onChanged,
    );
  }
}

class _WallPositionControl extends StatelessWidget {
  const _WallPositionControl({required this.position, required this.onChanged});

  final double position;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _WallPercentControl(
      label: 'Posición',
      value: position,
      onChanged: onChanged,
    );
  }
}

class _WallColorTemperatureControl extends StatelessWidget {
  const _WallColorTemperatureControl({
    required this.colorTemperature,
    required this.onChanged,
  });

  final double colorTemperature;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _WallPercentControl(
      label: 'Temperatura de color',
      value: colorTemperature,
      onChanged: onChanged,
    );
  }
}

class _WallFanControls extends StatelessWidget {
  const _WallFanControls({
    required this.fanSpeed,
    required this.onChanged,
    this.label = 'Velocidad',
  });

  final int fanSpeed;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textDim, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var speed = 1; speed <= 3; speed++) ...[
              Expanded(
                child: _WallSpeedCard(
                  speed: speed,
                  selected: fanSpeed == speed,
                  onTap: () => onChanged(speed),
                ),
              ),
              if (speed != 3) const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }
}

class _WallSpeedCard extends StatelessWidget {
  const _WallSpeedCard({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final int speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.gammaIndigoLight : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.gammaIndigo : AppColors.border,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              '$speed',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.gammaIndigo : AppColors.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WallTemperatureControl extends StatelessWidget {
  const _WallTemperatureControl({
    required this.targetTemperature,
    required this.onChanged,
  });

  final double targetTemperature;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Temperatura objetivo',
          style: TextStyle(color: AppColors.textDim, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Bajar temperatura',
              constraints: const BoxConstraints.tightFor(width: 64, height: 64),
              onPressed: targetTemperature > 16
                  ? () => onChanged(targetTemperature - 1)
                  : null,
              icon: const Icon(Icons.remove, size: 28),
            ),
            Expanded(
              child: Text(
                '${targetTemperature.toStringAsFixed(0)} °C',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Subir temperatura',
              constraints: const BoxConstraints.tightFor(width: 64, height: 64),
              onPressed: targetTemperature < 30
                  ? () => onChanged(targetTemperature + 1)
                  : null,
              icon: const Icon(Icons.add, size: 28),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 17),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 32),
          ),
          child: Slider(
            value: targetTemperature.clamp(16, 30),
            min: 16,
            max: 30,
            divisions: 14,
            label: '${targetTemperature.toStringAsFixed(0)} °C',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _WallClimateModeChips extends StatelessWidget {
  const _WallClimateModeChips({
    required this.mode,
    required this.options,
    required this.onChanged,
  });

  final String mode;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modo',
          style: TextStyle(color: AppColors.textDim, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(capabilityModeLabel(option)),
                selected: mode == option,
                onSelected: (_) => onChanged(option),
                labelStyle: const TextStyle(fontSize: 15),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Touch-first routines entry (desktop parity): related count plus a >= 60dp
/// creation button into [RoutinesPage].
class _WallRoutinesCard extends StatelessWidget {
  const _WallRoutinesCard({required this.onCreate, this.relatedCount});

  final VoidCallback onCreate;

  /// Related routines count; null while loading or unknown (fetch failed).
  final int? relatedCount;

  String get _countLabel {
    final count = relatedCount;
    if (count == null) return '—';
    return count == 1 ? '1 rutina' : '$count rutinas';
  }

  @override
  Widget build(BuildContext context) {
    return _WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 22,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rutinas relacionadas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _countLabel,
                style: const TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCreate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gammaIndigoLight,
                foregroundColor: AppColors.gammaIndigo,
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('+ Crear rutina con este dispositivo'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wall rename outcome: set, clear (null) or cancelled.
sealed class _WallRenameResult {
  const _WallRenameResult();
}

class _WallRenameSet extends _WallRenameResult {
  const _WallRenameSet(this.name);
  final String name;
}

class _WallRenameClear extends _WallRenameResult {
  const _WallRenameClear();
}

class _WallRenameCancelled extends _WallRenameResult {
  const _WallRenameCancelled();
}

/// Touch-first rename dialog with explicit null-clear semantics and >= 64dp
/// action targets.
class _WallRenameDialog extends StatefulWidget {
  const _WallRenameDialog({
    required this.title,
    required this.initialName,
    required this.fallbackName,
    required this.canReset,
  });

  final String title;
  final String? initialName;
  final String fallbackName;
  final bool canReset;

  @override
  State<_WallRenameDialog> createState() => _WallRenameDialogState();
}

class _WallRenameDialogState extends State<_WallRenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío.');
      return;
    }
    Navigator.of(context).pop(_WallRenameSet(value));
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
              Icons.edit_outlined,
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
                const Text(
                  'Se muestra en tu casa',
                  style: TextStyle(
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
                'Nombre personalizado',
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Escribí el nombre',
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
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 6),
              Text(
                'El nombre del fabricante/proveedor no se modifica. '
                'Sin nombre personalizado se muestra: ${widget.fallbackName}',
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _WallRenameClear()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textDim,
              minimumSize: const Size(120, 64),
              textStyle: const TextStyle(fontSize: 17),
            ),
            child: const Text('Restablecer'),
          ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const _WallRenameCancelled()),
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
          label: const Text('Guardar'),
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

/// Card container shared by the wall detail sections.
class _WallCard extends StatelessWidget {
  const _WallCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Wall hero: large display name and plain-language health, with a
/// touch-first 'Nombre' rename control (>= 64dp). No model/providerName here.
class _WallDeviceHero extends StatelessWidget {
  const _WallDeviceHero({required this.device, required this.onRename});

  final PhysicalDevice device;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final kindIcon = iosKindIcon(device.kind);
    final primaryName = device.userName ?? device.name;
    final health = wallHealthLabel(device.health);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(kindIcon, size: 30, color: AppColors.accent),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (health != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        health,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 7),
            child: Text(
              'Nombre',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cambiar nombre',
            onPressed: onRename,
            constraints: const BoxConstraints.tightFor(width: 64, height: 64),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accentTint,
              foregroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 26),
          ),
        ],
      ),
    );
  }
}

/// Wall per-control editor: household vocabulary only (display name, 'Qué
/// controla', 'Habitación que controla'). Presents the shared state mutation
/// callbacks; never duplicates repository logic.
class _WallEndpointEditor extends StatelessWidget {
  const _WallEndpointEditor({
    required this.endpoint,
    required this.areas,
    required this.busy,
    required this.onAreaChanged,
    required this.onRename,
    this.onRoleChanged,
  });

  final DeviceEndpoint endpoint;
  final List<HomeArea> areas;
  final bool busy;
  final ValueChanged<String?> onAreaChanged;
  final VoidCallback onRename;
  final ValueChanged<String?>? onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final kindIcon = iosKindIcon(endpoint.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(kindIcon, size: 20, color: AppColors.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                endpoint.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cambiar nombre del control',
              onPressed: busy
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Guardando cambios, espera un momento...',
                          ),
                        ),
                      );
                    }
                  : onRename,
              constraints: const BoxConstraints.tightFor(width: 64, height: 64),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceRaised,
                foregroundColor: AppColors.accent,
              ),
              icon: const Icon(Icons.edit_outlined, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (onRoleChanged != null) ...[
          _WallRoleDropdown(
            value: endpoint.semanticRole,
            enabled: !busy,
            onChanged: onRoleChanged!,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              _wallRoleSourceLabel(endpoint),
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _WallAreaDropdown(
          label: 'Habitación que controla',
          value: endpoint.controlledAreaId,
          areas: areas,
          enabled: !busy,
          onChanged: onAreaChanged,
        ),
      ],
    );
  }
}

/// Collapsed-by-default technical metadata for the wall surface. The body is
/// removed from the tree until expanded, so raw IDs/providers never leak into
/// the primary wall view.
class _WallTechnicalSection extends StatelessWidget {
  const _WallTechnicalSection({required this.gateway, required this.device});

  final GatewayInfo? gateway;
  final PhysicalDevice device;

  @override
  Widget build(BuildContext context) {
    final gatewayName = gateway?.name;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
          title: const Text('Información técnica'),
          children: [
            _WallMetadataRow(
              label: 'Última conexión',
              value: device.lastSeenLabel ?? 'Sin datos',
            ),
            _WallMetadataRow(
              label: 'Detectado como',
              value: _wallDetectedAs(device),
            ),
            if (gatewayName != null)
              _WallMetadataRow(label: 'Gateway', value: gatewayName),
          ],
        ),
      ),
    );
  }
}

class _WallMetadataRow extends StatelessWidget {
  const _WallMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop parity for 'Detectado como': the provider role wins, then the
/// device kind. Keeps Información técnica to three rows on the wall.
String _wallDetectedAs(PhysicalDevice device) {
  final providerRole = device.endpoints
      .map((endpoint) => endpoint.providerSemanticRole)
      .whereType<String>()
      .firstOrNull;
  if (providerRole != null) {
    return switch (providerRole.toLowerCase()) {
      'light' => 'Luz',
      'switch' => 'Interruptor',
      'fan' || 'extractor' => 'Ventilador',
      'sensor' => 'Sensor',
      'outlet' => 'Enchufe',
      'climate' => 'Clima',
      _ => 'Interruptor',
    };
  }
  return switch (device.kind) {
    DeviceKind.light => 'Luz',
    DeviceKind.outlet => 'Enchufe',
    DeviceKind.sensor => 'Sensor',
    DeviceKind.gateway => 'Gateway',
    DeviceKind.switchController => 'Interruptor genérico',
    DeviceKind.unknown => 'Dispositivo',
  };
}

String _roomName(List<HomeArea> areas, String? physicalAreaId) {
  if (physicalAreaId == null) return 'Sin área';
  for (final area in areas) {
    if (area.id == physicalAreaId) return area.name;
  }
  return 'Sin área';
}

/// On/off state for the wall device cards (top-right pill): green
/// Encendido, red Apagado. Available on every device with a power channel,
/// even when the backend doesn't report a canonical POWER capability
/// (existing devices). Null when the state would mislead — sensors, gateways,
/// or unreachable ones (a disconnected device is not 'Apagado'). With command
/// support a missing observation is 'Sin datos' instead of a fabricated
/// 'Apagado'; without it the legacy `powerOn ?? online` behavior stays.
({String label, Color color})? _wallPowerState(
  PhysicalDevice device, {
  required bool commandsSupported,
}) {
  if (device.isGateway || device.kind == DeviceKind.gateway) return null;
  if (device.kind == DeviceKind.sensor) return null;
  switch (device.health) {
    case DeviceHealthState.online:
    case DeviceHealthState.sleeping:
    case DeviceHealthState.unknown:
      break;
    case DeviceHealthState.offline:
    case DeviceHealthState.unreachable:
    case DeviceHealthState.authError:
      return null;
  }
  if (commandsSupported) {
    return switch (devicePowerDisplayState(device)) {
      PowerDisplayState.on => (label: 'Encendido', color: AppColors.green),
      PowerDisplayState.off => (label: 'Apagado', color: AppColors.red),
      PowerDisplayState.unknown => (
        label: 'Sin datos',
        color: AppColors.textFaint,
      ),
    };
  }
  final on = device.powerOn ?? device.online;
  return (
    label: on ? 'Encendido' : 'Apagado',
    color: on ? AppColors.green : AppColors.red,
  );
}

/// Plain-language health, only when authoritative. Unknown stays neutral: no
/// availability invented.
String? wallHealthLabel(DeviceHealthState health) {
  return switch (health) {
    DeviceHealthState.online => 'En línea',
    DeviceHealthState.offline ||
    DeviceHealthState.unreachable ||
    DeviceHealthState.authError => 'Atención',
    DeviceHealthState.sleeping => 'En espera',
    DeviceHealthState.unknown => null,
  };
}

Color _wallHealthColor(DeviceHealthState health) {
  return switch (health) {
    DeviceHealthState.online => AppColors.green,
    DeviceHealthState.offline ||
    DeviceHealthState.unreachable ||
    DeviceHealthState.authError => AppColors.red,
    DeviceHealthState.sleeping => AppColors.amber,
    DeviceHealthState.unknown => AppColors.textFaint,
  };
}

/// Centered success splash for the wall surface (desktop parity): dark card
/// with a green check that bounces in (scale + fade) and dismisses itself.
/// Success feedback goes through here; errors keep the plain SnackBar, same
/// contract as the desktop detail pane.
Future<void> showWallSuccessSplash(
  BuildContext context, {
  required String message,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: message,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _WallSuccessSplash(message: message),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: 0.7, end: 1).animate(curved),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class _WallSuccessSplash extends StatefulWidget {
  const _WallSuccessSplash({required this.message});

  final String message;

  @override
  State<_WallSuccessSplash> createState() => _WallSuccessSplashState();
}

class _WallSuccessSplashState extends State<_WallSuccessSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          decoration: BoxDecoration(
            color: AppColors.toastDark,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.statusEncendido,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
