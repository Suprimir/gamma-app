import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/device_status.dart';
import '../areas/area_editor.dart';
import '../areas/desktop_areas_page.dart';
import '../../data/device_inventory.dart';
import 'desktop_device_detail_pane.dart';
import 'desktop_master_pane.dart';
import 'devices_page.dart';
import '../../ui/shared_widgets.dart';

/// Espacio de trabajo maestro/detalle de la feature Devices en superficie
/// desktop (Fase 3-C): lista de dispositivos de usuario a la izquierda, panel
/// de detalle editable a la derecha. La selección vive en el controlador; el
/// detalle es [DeviceDetailView] compartido con la navegación móvil.
class DesktopDevicesPage extends StatefulWidget {
  const DesktopDevicesPage({
    super.key,
    required this.controller,
    this.api,
    this.initialLocationId,
  });

  final AdaptiveFeatureController controller;

  /// Optional API client forwarded to the detail pane (Rutinas navigation).
  final ApiClient? api;

  /// Pre-selected area filter for the master pane (Inicio → Ver dispositivos).
  final String? initialLocationId;

  @override
  State<DesktopDevicesPage> createState() => _DesktopDevicesPageState();
}

class _DesktopDevicesPageState extends State<DesktopDevicesPage> {
  // ponytail: feature-specific pane split; desktop surface with insufficient
  // width falls back to list-detail push, never switches the app surface.
  static const _narrowBreakpoint = 880.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.devicesLoading && controller.snapshot == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.deviceError != null && controller.snapshot == null) {
          // Never surface a raw exception: the load failure is presented in
          // household language with a retry path (same contract as wall).
          return MessageView(
            message: 'No se pudieron cargar los dispositivos',
            onRetry: controller.loadDevices,
          );
        }
        final snapshot = controller.snapshot!;
        return Material(
          color: AppColors.bg,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < _narrowBreakpoint) {
                return _buildNarrow(snapshot);
              }
              return _buildMasterDetail(snapshot);
            },
          ),
        );
      },
    );
  }

  Widget _buildNarrow(DeviceInventorySnapshot snapshot) {
    return _MasterList(
      devices: snapshot.userDevices,
      areas: snapshot.areas,
      selectedDeviceId: null,
      onSelect: (device) => _openNarrowDetail(snapshot, device),
      onOpenAreas: _openAreas,
    );
  }

  /// Production route to the desktop Areas workspace sharing the same
  /// controller: loads areas once (DesktopAreasPage renders null-areas as a
  /// spinner) and reconciles area names on the device list on return.
  Future<void> _openAreas() async {
    if (widget.controller.areas == null) {
      await widget.controller.loadAreas();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DesktopAreasPage(controller: widget.controller),
      ),
    );
    await widget.controller.loadDevices();
  }

  /// Navegación secuencial lista → detalle: empuja el detalle y al volver
  /// refresca el inventario canónico (mismo contrato que la navegación móvil).
  Future<void> _openNarrowDetail(
    DeviceInventorySnapshot snapshot,
    PhysicalDevice device,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            surfaceTintColor: Colors.transparent,
            title: const Text('Configurar dispositivo'),
          ),
          body: DeviceDetailView(
            device: device,
            areas: snapshot.areas,
            gateways: snapshot.gateways,
            repository: widget.controller.repository,
            onCanonicalDeviceChanged: widget.controller.applyCanonicalDevice,
          ),
        ),
      ),
    );
    await widget.controller.loadDevices();
  }

  Future<void> _showAddDeviceDialog() async {
    final areas = widget.controller.snapshot?.areas ?? const <HomeArea>[];
    final result = await showDialog<_DesktopAddResult>(
      context: context,
      builder: (_) => _DesktopAddDialog(areas: areas),
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
    widget.controller.addLocalDevice(device);
    widget.controller.selectDevice(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dispositivo "${result.name}" agregado')),
    );
  }

  /// Wall parity: discovery runs through the shared controller; this page
  /// only decides the household-language feedback (desktop SnackBar).
  Future<void> _discover() async {
    final controller = widget.controller;
    if (controller.discovering) return;
    try {
      final ok = await controller.discover();
      if (!ok || !mounted) return;
      final snapshot = controller.snapshot!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snapshot.unassigned.isEmpty
                ? 'No se encontraron dispositivos pendientes.'
                : '${snapshot.unassigned.length} dispositivos pendientes de configurar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo buscar dispositivos: $error')),
      );
    }
  }

  /// Wall parity: creates a new area with the shared dialog style, then
  /// reloads devices so device subtitles converge without leaving the page.
  Future<void> _showAddAreaDialog() async {
    final controller = widget.controller;
    if (controller.areaMutating) return;
    final result = await showDialog<({String name, List<String> aliases})>(
      context: context,
      builder: (_) => const AreaEditorDialog(
        title: 'Nueva área',
        submitLabel: 'Crear',
        showAliases: false,
        decorated: true,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await controller.createArea(result.name, result.aliases);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área creada.')));
      await controller.loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  /// Wall parity: edits an area in place, then reloads devices so the list
  /// converges without leaving this page.
  Future<void> _editArea(HomeArea area) async {
    final controller = widget.controller;
    if (controller.areaMutating) return;
    final result = await showDialog<({String name, List<String> aliases})>(
      context: context,
      builder: (_) => AreaEditorDialog(
        title: 'Editar área',
        submitLabel: 'Guardar',
        initialName: area.name,
        initialAliases: area.aliases,
        showAliases: false,
        decorated: true,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await controller.updateArea(
        area.id,
        name: result.name,
        aliases: result.aliases,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área actualizada.')));
      await controller.loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  /// Wall parity: deletes an area with confirmation, then reloads devices.
  Future<void> _deleteArea(HomeArea area) async {
    final controller = widget.controller;
    if (controller.areaMutating) return;
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (!confirmed || !mounted) return;
    try {
      await controller.deleteArea(area.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área eliminada.')));
      await controller.loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  Widget _buildMasterDetail(DeviceInventorySnapshot snapshot) {
    final controller = widget.controller;
    final selected = controller.selectedDevice;
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => DesktopMasterPane(
              devices: snapshot.userDevices,
              areas: snapshot.areas,
              selectedDeviceId: controller.selectedDeviceId,
              onSelect: _guardSelectDevice,
              onAddDevice: _showAddDeviceDialog,
              controller: controller,
              discovering: controller.discovering,
              onDiscover: _discover,
              onAddArea: _showAddAreaDialog,
              onEditArea: _editArea,
              onDeleteArea: _deleteArea,
              initialLocationId: widget.initialLocationId,
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
        Expanded(
          child: selected == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Selecciona un dispositivo',
                          style: TextStyle(
                            color: AppColors.textDim,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Elige un dispositivo de la lista para ver y editar su configuración.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : DesktopDeviceDetailPane(
                  key: ValueKey(selected.id),
                  device: selected,
                  areas: snapshot.areas,
                  gateways: snapshot.gateways,
                  controller: controller,
                  api: widget.api,
                ),
        ),
      ],
    );
  }

  /// Selección con resguardo de cambios sin guardar: si el detalle tiene
  /// pendientes (ubicación/tipo), se pregunta en el centro de la pantalla
  /// antes de cambiar de dispositivo.
  Future<void> _guardSelectDevice(PhysicalDevice device) async {
    final controller = widget.controller;
    if (controller.selectedDeviceId == device.id ||
        !controller.hasPendingChanges) {
      controller.selectDevice(device.id);
      return;
    }
    final action = await showDialog<_PendingSwitchAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar cambios'),
        content: const Text(
          'Tienes cambios sin guardar en este dispositivo. '
          '¿Qué quieres hacer?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_PendingSwitchAction.discard),
            child: const Text('Descartar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_PendingSwitchAction.save),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gammaIndigo,
              foregroundColor: Colors.white,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    final fromId = controller.selectedDeviceId;
    switch (action) {
      case _PendingSwitchAction.save:
        if (fromId != null) {
          try {
            await controller.commitPendingChanges(fromId);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(e.toString())));
            return;
          }
        }
        controller.selectDevice(device.id);
      case _PendingSwitchAction.discard:
        controller.discardPendingChanges();
        controller.selectDevice(device.id);
    }
  }

  // Kept for reference; desktop now uses DesktopDeviceDetailPane with batched Save.
  // ignore: unused_element
  Widget _legacyDetail(AdaptiveFeatureController controller) =>
      _DetailPane(controller: controller);
}

class _MasterList extends StatefulWidget {
  const _MasterList({
    required this.devices,
    required this.areas,
    required this.selectedDeviceId,
    required this.onSelect,
    required this.onOpenAreas,
  });

  final List<PhysicalDevice> devices;
  final List<HomeArea> areas;
  final String? selectedDeviceId;
  final ValueChanged<PhysicalDevice> onSelect;
  final VoidCallback onOpenAreas;

  @override
  State<_MasterList> createState() => _MasterListState();
}

class _MasterListState extends State<_MasterList> {
  // ponytail: local UI filter only; never mutates the canonical model and
  // never becomes a backend query.
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final areaById = {for (final area in widget.areas) area.id: area};
    final query = _query.trim().toLowerCase();
    final devices = query.isEmpty
        ? widget.devices
        : widget.devices
              .where(
                (device) =>
                    (device.userName ?? device.name).toLowerCase().contains(
                      query,
                    ) ||
                    (device.providerName ?? '').toLowerCase().contains(query) ||
                    (areaById[device.physicalAreaId]?.name ?? '')
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Dispositivos',
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
                  '${devices.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: widget.onOpenAreas,
                icon: const Icon(Icons.home_work_outlined, size: 17),
                label: const Text('Habitaciones'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.accentStrong,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: const Key('desktop-device-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Buscar',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          ),
        ),
        if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Sin resultados',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
        for (final device in devices) ...[
          _DesktopDeviceRow(
            key: ValueKey('desktop-device-${device.id}'),
            title: device.userName ?? device.name,
            subtitle: areaById[device.physicalAreaId]?.name ?? 'Sin área',
            health: device.health,
            selected: device.id == widget.selectedDeviceId,
            onSelect: () => widget.onSelect(device),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DesktopDeviceRow extends StatefulWidget {
  const _DesktopDeviceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.health,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final DeviceHealthState health;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_DesktopDeviceRow> createState() => _DesktopDeviceRowState();
}

class _DesktopDeviceRowState extends State<_DesktopDeviceRow> {
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
                  _healthDot(widget.health),
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

Widget _healthDot(DeviceHealthState health) {
  return Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: switch (health) {
        DeviceHealthState.online => AppColors.green,
        DeviceHealthState.offline ||
        DeviceHealthState.unreachable ||
        DeviceHealthState.authError => AppColors.red,
        DeviceHealthState.sleeping => AppColors.amber,
        DeviceHealthState.unknown => AppColors.textFaint,
      },
      shape: BoxShape.circle,
    ),
  );
}

class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.controller});

  final AdaptiveFeatureController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    final snapshot = controller.snapshot;
    if (selected == null || snapshot == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selecciona un dispositivo',
                style: TextStyle(color: AppColors.textDim, fontSize: 15),
              ),
              SizedBox(height: 8),
              Text(
                'Elige un dispositivo de la lista para ver y editar su configuración.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return DeviceDetailView(
      key: ValueKey(selected.id),
      device: selected,
      areas: snapshot.areas,
      gateways: snapshot.gateways,
      repository: controller.repository,
      onCanonicalDeviceChanged: controller.applyCanonicalDevice,
    );
  }
}

enum _PendingSwitchAction { save, discard }

class _DesktopAddResult {
  const _DesktopAddResult({
    required this.name,
    required this.type,
    this.areaId,
  });
  final String name;
  final String type;
  final String? areaId;
}

class _DesktopAddDialog extends StatefulWidget {
  const _DesktopAddDialog({required this.areas});
  final List<HomeArea> areas;
  @override
  State<_DesktopAddDialog> createState() => _DesktopAddDialogState();
}

class _DesktopAddDialogState extends State<_DesktopAddDialog> {
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
    ).pop(_DesktopAddResult(name: name, type: _type, areaId: _areaId));
  }

  @override
  Widget build(BuildContext context) {
    // Ícono dinámico del encabezado: mismo mapeo por DeviceKind que la lista
    // lateral; se reconstruye con setState al cambiar el dropdown de Tipo.
    final typeKind = switch (_type) {
      'Luz' => DeviceKind.light,
      'Enchufe' => DeviceKind.outlet,
      'Sensor' => DeviceKind.sensor,
      _ => DeviceKind.switchController,
    };
    final fieldFill = AppColors.surfaceRaised;
    final dimText = AppColors.textDim;
    final faintText = AppColors.textFaint;
    final hintText = AppColors.textFaint;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C6FF0), Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    kindIcon(typeKind),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Agregar dispositivo',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Nombre', style: TextStyle(color: dimText, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'ej. Luz techo living',
                hintStyle: TextStyle(color: hintText),
                errorText: _error,
                errorStyle: const TextStyle(color: AppColors.statusApagado),
                filled: true,
                fillColor: fieldFill,
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            Text('Tipo', style: TextStyle(color: dimText, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _type,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: dimText),
              decoration: InputDecoration(
                filled: true,
                fillColor: fieldFill,
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                for (final entry in const [
                  ('Luz', DeviceKind.light),
                  ('Enchufe', DeviceKind.outlet),
                  ('Sensor', DeviceKind.sensor),
                  ('Interruptor', DeviceKind.switchController),
                ])
                  DropdownMenuItem(
                    value: entry.$1,
                    child: Row(
                      children: [
                        Icon(kindIcon(entry.$2), size: 18, color: dimText),
                        const SizedBox(width: 10),
                        Text(
                          entry.$1,
                          style: const TextStyle(color: AppColors.text),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'Luz'),
            ),
            const SizedBox(height: 6),
            Text(
              'Esto define qué controles vas a poder usar '
              '(brillo, velocidad, temperatura, etc.).',
              style: TextStyle(color: faintText, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            Text('Ubicación', style: TextStyle(color: dimText, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              value: _areaId,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: dimText),
              decoration: InputDecoration(
                filled: true,
                fillColor: fieldFill,
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_off_outlined,
                        size: 18,
                        color: dimText,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Sin área',
                        style: TextStyle(color: AppColors.text),
                      ),
                    ],
                  ),
                ),
                for (final area in widget.areas)
                  DropdownMenuItem<String?>(
                    value: area.id,
                    child: Row(
                      children: [
                        Icon(
                          _dialogAreaIcon(area.name),
                          size: 18,
                          color: dimText,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            area.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.text),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _areaId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: dimText),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gammaIndigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

/// Ícono por área para el dropdown de Ubicación del diálogo desktop.
/// Réplica local del mapeo del dashboard (misma correspondencia nombre →
/// ícono) para no acoplar ambas pantallas.
IconData _dialogAreaIcon(String? name) {
  final key = (name ?? '').toLowerCase();
  if (key.contains('cocina') || key.contains('kitchen')) return Icons.kitchen;
  if (key.contains('living') || key.contains('sala') || key.contains('estar')) {
    return Icons.weekend;
  }
  if (key.contains('patio') ||
      key.contains('jard') ||
      key.contains('terraza')) {
    return Icons.grass;
  }
  if (key.contains('recámara') ||
      key.contains('recamara') ||
      key.contains('dormitorio') ||
      key.contains('habitaci') ||
      key.contains('bedroom')) {
    return Icons.bed;
  }
  if (key.contains('baño') || key.contains('bano') || key.contains('bath')) {
    return Icons.bathtub_outlined;
  }
  if (key.contains('oficina') ||
      key.contains('estudio') ||
      key.contains('office')) {
    return Icons.work_outline;
  }
  if (key.contains('comedor') || key.contains('dining')) {
    return Icons.restaurant_outlined;
  }
  if (key.contains('cochera') ||
      key.contains('garage') ||
      key.contains('garaje')) {
    return Icons.garage_outlined;
  }
  return Icons.home_outlined;
}
