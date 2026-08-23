import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../ui/app_colors.dart';
import '../areas/desktop_areas_page.dart';
import '../../data/device_inventory.dart';
import 'devices_page.dart';
import '../../ui/shared_widgets.dart';

/// Espacio de trabajo maestro/detalle de la feature Devices en superficie
/// desktop (Fase 3-C): lista de dispositivos de usuario a la izquierda, panel
/// de detalle editable a la derecha. La selección vive en el controlador; el
/// detalle es [DeviceDetailView] compartido con la navegación móvil.
class DesktopDevicesPage extends StatefulWidget {
  const DesktopDevicesPage({super.key, required this.controller});

  final AdaptiveFeatureController controller;

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

  Widget _buildMasterDetail(DeviceInventorySnapshot snapshot) {
    final controller = widget.controller;
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: _MasterList(
            devices: snapshot.userDevices,
            areas: snapshot.areas,
            selectedDeviceId: controller.selectedDeviceId,
            onSelect: (device) => controller.selectDevice(device.id),
            onOpenAreas: _openAreas,
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
        Expanded(child: _DetailPane(controller: controller)),
      ],
    );
  }
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
