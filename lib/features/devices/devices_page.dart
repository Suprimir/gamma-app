import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../adaptive/adaptive_scope.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import 'desktop_devices_page.dart';
import '../../data/device_inventory.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../ui/device_status.dart';
import '../../ui/shared_widgets.dart';
import 'wall_devices_page.dart';

class DevicesPage extends StatefulWidget {
  DevicesPage({
    super.key,
    required this.api,
    DeviceInventoryRepository? repository,
  }) : repository = repository ?? HttpDeviceInventoryRepository(api);

  /// Se conserva en el constructor para mantener estable el contrato de
  /// AppShell. La pantalla nueva consume DeviceInventoryRepository; por
  /// defecto se usa el repositorio HTTP que mapea la API de DevicePlatform.
  final ApiClient api;
  final DeviceInventoryRepository repository;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late final AdaptiveFeatureController _controller = AdaptiveFeatureController(
    widget.repository,
  );
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wall surface owns its own controller (WallDevicesPage) — stay inert there.
    final scope = AppAdaptiveScope.maybeOf(context);
    if (scope != null && scope.isWallPanel) return;
    // Offstage guard: defer until ticking to avoid LazyPageHost duplicate/disposed race.
    if (_loadStarted) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    _loadStarted = true;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() => _controller.loadDevices();

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    await _controller.loadDevices();
  }

  /// Offline devices leave the controls landing: this keeps them reachable
  /// through the header icon button, with the existing no-connection copy.
  Future<void> _openOfflineList(DeviceInventorySnapshot snapshot) {
    return _open(
      _MobileDeviceGridPage(
        title: 'Desconectados',
        subtitle: 'Dispositivos sin conexión, con acción rápida.',
        devices: snapshot.offlineDevices,
        areas: snapshot.areas,
        gateways: snapshot.gateways,
        repository: widget.repository,
        controller: _controller,
        emptyMessage: 'No hay dispositivos desconectados.',
        onCanonicalDeviceChanged: _controller.applyCanonicalDevice,
      ),
    );
  }

  /// Grouped control slivers shared by the landing: every power channel of
  /// the active inventory, grouped by effective area (same contract as the
  /// old full-screen Controles page). The honest empty state points to the
  /// devices list for discovery/configuration.
  List<Widget> _controlSlivers(DeviceInventorySnapshot snapshot) {
    final channels = powerChannelsOf(snapshot.activeDevices);
    final groups = groupPowerChannels(channels, snapshot.areas);
    if (channels.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              children: [
                Text(
                  'Todavía no hay controles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 15),
                ),
                SizedBox(height: 8),
                Text(
                  'Abrí Dispositivos para buscar y configurar tus equipos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${group.channels.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ChannelTileGrid(
          channels: group.channels,
          repository: widget.repository,
          controller: _controller,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppAdaptiveScope.maybeOf(context);
    if (scope != null && scope.isWallPanel) {
      return WallDevicesPage(api: widget.api, repository: widget.repository);
    }
    if (scope != null && scope.isDesktopSurface) {
      return DesktopDevicesPage(controller: _controller, api: widget.api);
    }
    if (_controller.devicesLoading && _controller.snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.deviceError != null && _controller.snapshot == null) {
      // Never surface a raw exception: the load failure is presented in
      // household language with a retry path (same contract as wall).
      return MessageView(
        message: 'No se pudieron cargar los dispositivos',
        onRetry: _load,
      );
    }

    final snapshot = _controller.snapshot!;
    final offlineCount = snapshot.offlineDevices.length;
    // CONTROLES is the mobile landing: every power channel of the active
    // inventory, grouped by effective area. Device management (flat list,
    // pending devices, gateways, discovery, manual add) lives behind the
    // header icon buttons so the default surface stays a control surface.
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _controller.refreshStatesAndReload,
          color: AppColors.accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _HeaderIconButton(
                        key: const ValueKey('open-devices-list'),
                        tooltip: 'Dispositivos',
                        icon: Icons.devices_other,
                        onTap: () => _open(
                          _MobileDevicesListPage(
                            snapshot: snapshot,
                            repository: widget.repository,
                            controller: _controller,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _HeaderIconButton(
                        key: const ValueKey('open-offline-list'),
                        tooltip: 'Dispositivos sin acceso',
                        icon: Icons.wifi_off_rounded,
                        badge: offlineCount == 0 ? null : '$offlineCount',
                        onTap: () => _openOfflineList(snapshot),
                      ),
                    ],
                  ),
                ),
              ),
              ..._controlSlivers(snapshot),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact 48dp icon-only action for the mobile landing header, with an
/// optional small count badge (offline devices).
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final badgeText = badge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
          onPressed: onTap,
          icon: Icon(icon, size: 22, color: AppColors.textDim),
        ),
        if (badgeText != null)
          Positioned(
            top: 4,
            right: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Diálogo Agregar dispositivo (parity desktop +Agregar)
class _DashboardAddResult {
  const _DashboardAddResult({
    required this.name,
    required this.type,
    this.areaId,
  });
  final String name;
  final String type;
  final String? areaId;
}

class _DashboardAddDialog extends StatefulWidget {
  const _DashboardAddDialog({required this.areas, this.initialAreaId});
  final List<HomeArea> areas;
  final String? initialAreaId;
  @override
  State<_DashboardAddDialog> createState() => _DashboardAddDialogState();
}

class _DashboardAddDialogState extends State<_DashboardAddDialog> {
  late final TextEditingController _nameController = TextEditingController();
  String _type = 'Luz';
  String? _areaId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _areaId = widget.initialAreaId;
    if (_areaId != null && !widget.areas.any((a) => a.id == _areaId)) {
      _areaId = null;
    }
  }

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
    ).pop(_DashboardAddResult(name: name, type: _type, areaId: _areaId));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar dispositivo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nombre',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Luz', child: Text('Luz')),
                DropdownMenuItem(value: 'Enchufe', child: Text('Enchufe')),
                DropdownMenuItem(value: 'Sensor', child: Text('Sensor')),
                DropdownMenuItem(
                  value: 'Interruptor',
                  child: Text('Interruptor'),
                ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'Luz'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _areaId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Habitación',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin área'),
                ),
                for (final area in widget.areas)
                  DropdownMenuItem<String?>(
                    value: area.id,
                    child: Text(area.name, overflow: TextOverflow.ellipsis),
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
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Agregar')),
      ],
    );
  }
}

class _DashboardDeviceCard extends StatelessWidget {
  const _DashboardDeviceCard({
    required this.device,
    required this.areaName,
    required this.powerState,
    required this.canCommandPower,
    required this.onToggle,
    required this.onTap,
    required this.onMenu,
  });

  final PhysicalDevice device;
  final String? areaName;
  final PowerDisplayState powerState;

  /// Whether the repository exposes canonical commands. When true, an
  /// unknown/sleeping health still allows the quick power action (the toggle
  /// commands the backend and the label carries the truth).
  final bool canCommandPower;

  /// Primary action (only invoked with connectivity and a power channel).
  /// The requested value derives from [powerState]: unknown turns on (it is
  /// never presented as a confident off).
  final ValueChanged<bool> onToggle;

  /// Toque principal: alterna si es controlable, abre el detalle si no tiene
  /// canal de encendido, o informa falta de comunicación. Lo decide el padre
  /// con [_cardState]; la tarjeta solo refleja el estado.
  final VoidCallback onTap;

  /// Interacción secundaria (long-press o botón ···): controles avanzados.
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final kindIcon = iosKindIcon(device.kind);
    final displayName = device.userName ?? device.name;
    final channelNames = powerChannelNamesSummary(device);
    final state = _cardState(
      device,
      powerState,
      canCommandPower: canCommandPower,
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Semantics(
        button: true,
        label: '$displayName, ${state.label}',
        onLongPressHint: 'Mostrar más opciones',
        child: InkWell(
          // Toque normal = acción principal. Sin comunicación nunca alterna:
          // el padre muestra el motivo en lugar de fingir un apagado.
          onTap: onTap,
          onLongPress: onMenu,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F3F6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F5F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(kindIcon, size: 20, color: AppColors.textDim),
                    ),
                    const Spacer(),
                    if (state.controllable)
                      _DashboardToggle(
                        powerState: powerState,
                        onChanged: onToggle,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.2,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  areaName ?? 'Sin área',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // QoL 2: named channels at a glance (multi-channel devices
                // only; unnamed channels never add 'Canal N' noise).
                if (channelNames != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    channelNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: state.dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        state.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Más opciones',
                      onPressed: onMenu,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceRaised,
                        foregroundColor: AppColors.textDim,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(CupertinoIcons.ellipsis, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aggregate power state for a device with more than one power endpoint:
/// 'N de M encendidos', appending ' · K sin datos' while observations are
/// missing. Null for devices with fewer than two power endpoints (they keep
/// the single-state label) and for repositories without command support
/// (plain fakes keep their `powerOn ?? online` behavior).
({String label, Color dot})? _aggregatePowerState(
  PhysicalDevice device, {
  required bool canCommandPower,
}) {
  if (!canCommandPower) return null;
  final (on, total, unknown) = powerStateCounts(device);
  if (total <= 1) return null;
  final base = '$on de $total encendidos';
  return (
    label: unknown > 0 ? '$base · $unknown sin datos' : base,
    dot: on > 0
        ? AppColors.statusEncendido
        : unknown == total
        ? AppColors.textFaint
        : AppColors.statusApagado,
  );
}

/// Estado honesto de la tarjeta: la falta de comunicación nunca se presenta
/// como apagado, y una potencia sin observación confirmada se muestra como
/// 'Sin datos' (nunca como un apagado confiado). Solo [controllable] habilita
/// la acción rápida (tap/switch); sin canal de encendido el tap abre el
/// detalle; sin comunicación el tap informa.
///
/// [canCommandPower] is true when the repository exposes the canonical
/// command surface. With unknown/sleeping health and a real power channel the
/// device can still be commanded, so the honest label is 'Sin datos' and the
/// quick action stays enabled instead of a dead 'Estado desconocido'.
({String label, Color dot, bool controllable, bool opensDetail}) _cardState(
  PhysicalDevice device,
  PowerDisplayState powerState, {
  required bool canCommandPower,
}) {
  switch (device.health) {
    case DeviceHealthState.offline:
    case DeviceHealthState.unreachable:
    case DeviceHealthState.authError:
      return (
        label: 'Sin conexión',
        dot: AppColors.statusDesconectado,
        controllable: false,
        opensDetail: false,
      );
    case DeviceHealthState.unknown:
    case DeviceHealthState.sleeping:
      final canCommand =
          canCommandPower && device.endpoints.any(hasPowerCapability);
      if (!canCommand) {
        return (
          label: 'Estado desconocido',
          dot: AppColors.amber,
          controllable: false,
          opensDetail: false,
        );
      }
      return (
        label:
            _aggregatePowerState(
              device,
              canCommandPower: canCommandPower,
            )?.label ??
            'Sin datos',
        dot: AppColors.textFaint,
        controllable: true,
        opensDetail: false,
      );
    case DeviceHealthState.online:
      final hasPower = device.endpoints.any(hasPowerCapability);
      if (!hasPower) {
        return (
          label: 'Ver detalle',
          dot: AppColors.textFaint,
          controllable: false,
          opensDetail: true,
        );
      }
      final aggregate = _aggregatePowerState(
        device,
        canCommandPower: canCommandPower,
      );
      if (aggregate != null) {
        return (
          label: aggregate.label,
          dot: aggregate.dot,
          controllable: true,
          opensDetail: false,
        );
      }
      return switch (powerState) {
        PowerDisplayState.on => (
          label: 'Encendido',
          dot: AppColors.statusEncendido,
          controllable: true,
          opensDetail: false,
        ),
        PowerDisplayState.off => (
          label: 'Apagado',
          dot: AppColors.statusApagado,
          controllable: true,
          opensDetail: false,
        ),
        PowerDisplayState.unknown => (
          label: 'Sin datos',
          dot: AppColors.textFaint,
          controllable: true,
          opensDetail: false,
        ),
      };
  }
}

/// Resultado del menú secundario de la tarjeta.
enum _QuickAction { configure, identify }

/// Menú secundario: la tarjeta solo expone la acción principal; los controles
/// avanzados, la configuración y la información viven acá. Devuelve la acción
/// elegida para que el padre la ejecute con su propio Scaffold visible.
Future<_QuickAction?> _showDeviceQuickSheet({
  required BuildContext context,
  required PhysicalDevice device,
  required String? areaName,
  required PowerDisplayState powerState,
  required bool canCommandPower,
}) {
  final displayName = device.userName ?? device.name;
  final state = _cardState(
    device,
    powerState,
    canCommandPower: canCommandPower,
  );
  final meta = [device.provider, device.model, ?areaName].join(' · ');
  return showModalBottomSheet<_QuickAction>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    iosKindIcon(device.kind),
                    size: 22,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: state.dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            state.label,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              meta,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F3F6)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                CupertinoIcons.antenna_radiowaves_left_right,
                color: AppColors.accent,
              ),
              title: const Text('Identificar dispositivo'),
              subtitle: const Text(
                'Parpadea una luz o activa un LED según el adaptador.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_QuickAction.identify),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                CupertinoIcons.slider_horizontal_3,
                color: AppColors.accent,
              ),
              title: const Text('Configurar dispositivo'),
              subtitle: const Text(
                'Nombre, ubicación, canales e información técnica.',
              ),
              trailing: const Icon(
                CupertinoIcons.chevron_right,
                color: AppColors.textFaint,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_QuickAction.configure),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DashboardToggle extends StatelessWidget {
  const _DashboardToggle({required this.powerState, required this.onChanged});

  final PowerDisplayState powerState;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.accent;
    const trackOff = Color(0xFFE5E7EB);
    final isOn = powerState == PowerDisplayState.on;
    return Semantics(
      label: switch (powerState) {
        PowerDisplayState.on => 'Encendido',
        PowerDisplayState.off => 'Apagado',
        PowerDisplayState.unknown => 'Sin datos',
      },
      toggled: powerState == PowerDisplayState.unknown ? null : isOn,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!isOn),
        child: Container(
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isOn ? blue : trackOff,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
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

class _MobileDeviceGridPage extends StatefulWidget {
  const _MobileDeviceGridPage({
    required this.title,
    required this.subtitle,
    required this.devices,
    required this.areas,
    required this.gateways,
    required this.repository,
    required this.controller,
    required this.emptyMessage,
    // Area-scoped grids are not navigable from mobile anymore, but the
    // per-area 'Controles' section below is kept for the area pages contract.
    // ignore: unused_element_parameter
    this.hideAreaName = false,
    // ignore: unused_element_parameter
    this.areaId,
    this.onCanonicalDeviceChanged,
  });

  final String title;
  final String subtitle;
  final List<PhysicalDevice> devices;
  final List<HomeArea> areas;
  final List<GatewayInfo> gateways;
  final DeviceInventoryRepository repository;
  final AdaptiveFeatureController controller;
  final String emptyMessage;
  final bool hideAreaName;

  /// Effective area this grid is showing, when it is an area-scoped grid: the
  /// 'Controles' section renders the channels that command this room.
  final String? areaId;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  @override
  State<_MobileDeviceGridPage> createState() => _MobileDeviceGridPageState();
}

class _MobileDeviceGridPageState extends State<_MobileDeviceGridPage> {
  late final List<PhysicalDevice> _devices = List.of(widget.devices);
  final Map<String, bool> _powerOverrides = {};

  /// Local fallback used only when the repository has no command support
  /// (plain test fakes); production always takes the canonical command path.
  /// Computed from the repository in scope, which is also the one the
  /// controller wraps.
  bool get _commandsAvailable =>
      asDeviceCommandRepository(widget.repository) != null;

  void _showSnack(
    String message, {
    Color background = const Color(0xFF374151),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Future<void> _toggle(PhysicalDevice device, bool value) async {
    final displayName = device.userName ?? device.name;
    if (!_commandsAvailable) {
      setState(() => _powerOverrides[device.id] = value);
      _showSnack(
        '$displayName — ${value ? 'Encendido' : 'Apagado'}',
        background: value ? AppColors.accent : const Color(0xFF374151),
      );
      return;
    }
    try {
      final result = await widget.controller.setDevicePower(device.id, value);
      if (!mounted) return;
      _syncFromController(device.id);
      _showSnack(
        '$displayName — ${powerOutcomeMessage(result, requested: value)}',
        background: result.outcome == 'SUCCESS'
            ? (value ? AppColors.accent : const Color(0xFF374151))
            : const Color(0xFF374151),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('$displayName — ${powerFailureMessage(error)}');
    }
  }

  /// Mirrors the canonical device (with a merged observation) into the local
  /// list so the pushed grid reflects the same state as the shared snapshot.
  void _syncFromController(String deviceId) {
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) return;
    for (final updated in snapshot.devices) {
      if (updated.id != deviceId) continue;
      setState(() {
        final index = _devices.indexWhere((d) => d.id == deviceId);
        if (index >= 0) _devices[index] = updated;
      });
      return;
    }
  }

  /// Toque principal honesto: solo alterna con comunicación y un canal de
  /// encendido; sin canal abre el detalle; sin comunicación informa el estado
  /// real en vez de fingir un encendido/apagado. Con comandos disponibles un
  /// estado desconocido sigue siendo comandable (encender).
  void _handleTap(PhysicalDevice device, PowerDisplayState powerState) {
    final state = _cardState(
      device,
      powerState,
      canCommandPower: _commandsAvailable,
    );
    if (state.controllable) {
      _toggle(device, powerState != PowerDisplayState.on);
      return;
    }
    if (state.opensDetail) {
      _openDetail(device);
      return;
    }
    final displayName = device.userName ?? device.name;
    _showSnack('$displayName — ${state.label}');
  }

  Future<void> _showSheet(
    PhysicalDevice device,
    PowerDisplayState powerState,
  ) async {
    final action = await _showDeviceQuickSheet(
      context: context,
      device: device,
      areaName: widget.hideAreaName
          ? null
          : _areaName(widget.areas, device.physicalAreaId),
      powerState: powerState,
      canCommandPower: _commandsAvailable,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _QuickAction.configure:
        await _openDetail(device);
      case _QuickAction.identify:
        await _identify(device);
    }
  }

  Future<void> _identify(PhysicalDevice device) async {
    try {
      final result = await identifyDeviceWithFallback(
        widget.repository,
        device.id,
      );
      if (!mounted) return;
      if (!result.supported) {
        _showSnack(identifyUnsupportedMessage(result));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se envió la orden de identificación al dispositivo.'),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orden de identificación enviada (simulada)'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo identificar: $error')));
    }
  }

  Future<void> _openDetail(PhysicalDevice device) async {
    final current = _devices.firstWhere(
      (candidate) => candidate.id == device.id,
      orElse: () => device,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DeviceDetailPage(
          device: current,
          areas: widget.areas,
          gateways: widget.gateways,
          repository: widget.repository,
          onCanonicalDeviceChanged: (updated) {
            widget.onCanonicalDeviceChanged?.call(updated);
            if (!mounted) return;
            setState(() {
              final index = _devices.indexWhere((d) => d.id == updated.id);
              if (index >= 0) _devices[index] = updated;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Channels that command this room (endpoint effective area wins). The
    // section is additive: the device cards below stay the identity surface.
    final areaId = widget.areaId;
    final areaChannels = areaId == null
        ? const <PowerChannel>[]
        : powerChannelsOf(
            _devices,
          ).where((channel) => powerChannelAreaId(channel) == areaId).toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title),
      ),
      body: SafeArea(
        top: false,
        child: _devices.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.emptyMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textDim),
                  ),
                ),
              )
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text(
                        widget.subtitle,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  if (areaChannels.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Controles',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${areaChannels.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _ChannelTileGrid(
                      channels: areaChannels,
                      repository: widget.repository,
                      controller: widget.controller,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final device = _devices[index];
                        final areaName = widget.hideAreaName
                            ? null
                            : _areaName(widget.areas, device.physicalAreaId);
                        final powerState = _commandsAvailable
                            ? devicePowerDisplayState(device)
                            : (_powerOverrides[device.id] ?? device.online)
                            ? PowerDisplayState.on
                            : PowerDisplayState.off;
                        return _DashboardDeviceCard(
                          device: device,
                          areaName: areaName,
                          powerState: powerState,
                          canCommandPower: _commandsAvailable,
                          onToggle: (value) => _toggle(device, value),
                          onTap: () => _handleTap(device, powerState),
                          onMenu: () => _showSheet(device, powerState),
                        );
                      }, childCount: _devices.length),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Full-screen 'Controles' view: every power channel of the active inventory,
/// grouped by effective area. Tapping a tile toggles exactly that channel;
/// long-press opens the channel actions. Tiles are additive to the device
/// cards — the device stays the identity surface.
class _ChannelTileGrid extends StatefulWidget {
  const _ChannelTileGrid({
    required this.channels,
    required this.repository,
    required this.controller,
  });

  final List<PowerChannel> channels;
  final DeviceInventoryRepository repository;
  final AdaptiveFeatureController controller;

  @override
  State<_ChannelTileGrid> createState() => _ChannelTileGridState();
}

class _ChannelTileGridState extends State<_ChannelTileGrid> {
  /// In-flight toggles, keyed by device/endpoint.
  final Set<String> _busy = {};

  /// Local fallback used only when the repository has no command support
  /// (plain test fakes); production always takes the canonical path.
  final Map<String, PowerDisplayState> _overrides = {};
  bool _renaming = false;

  bool get _commandsAvailable =>
      asDeviceCommandRepository(widget.repository) != null;

  /// Identify is offered only when the repository can actually run it: the
  /// legacy contract flag or the segregated command layer.
  bool get _identifyAvailable =>
      widget.repository.supportsIdentify ||
      asDeviceCommandRepository(widget.repository) != null;

  String _key(String deviceId, String endpointId) => '$deviceId/$endpointId';

  /// Newest canonical device for [id] so confirmed observations and renames
  /// converge without waiting for the parent list to refresh.
  PhysicalDevice _freshDevice(String id, PhysicalDevice fallback) {
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) return fallback;
    for (final device in snapshot.devices) {
      if (device.id == id) return device;
    }
    return fallback;
  }

  DeviceEndpoint _freshEndpoint(
    PhysicalDevice device,
    DeviceEndpoint fallback,
  ) {
    for (final endpoint in device.endpoints) {
      if (endpoint.id == fallback.id) return endpoint;
    }
    return fallback;
  }

  /// Honest display state for one channel: command surfaces trust confirmed
  /// observations; plain fakes keep the legacy `powerOn ?? online` projection.
  PowerDisplayState _displayState(
    PhysicalDevice device,
    DeviceEndpoint endpoint,
  ) {
    final override = _overrides[_key(device.id, endpoint.id)];
    if (override != null) return override;
    if (!_commandsAvailable) {
      return (device.powerOn ?? device.online)
          ? PowerDisplayState.on
          : PowerDisplayState.off;
    }
    return endpointPowerDisplayState(endpoint);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF374151),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  /// Tap = toggle this channel (unknown turns on). The command merges a
  /// confirmed observation into the shared controller; the honest outcome
  /// drives the notice. Plain fakes keep the legacy local toggle.
  Future<void> _toggle(PhysicalDevice device, DeviceEndpoint endpoint) async {
    final key = _key(device.id, endpoint.id);
    if (_busy.contains(key)) return;
    final state = _displayState(device, endpoint);
    final value = state != PowerDisplayState.on;
    final name = endpointChannelName(endpoint);
    if (!_commandsAvailable) {
      setState(() {
        _overrides[key] = value ? PowerDisplayState.on : PowerDisplayState.off;
      });
      _showSnack('$name — ${value ? 'Encendido' : 'Apagado'}');
      return;
    }
    setState(() => _busy.add(key));
    try {
      final result = await widget.controller.setEndpointPower(
        device.id,
        endpoint.id,
        value,
      );
      if (!mounted) return;
      _showSnack('$name — ${powerOutcomeMessage(result, requested: value)}');
    } catch (error) {
      if (!mounted) return;
      _showSnack(powerFailureMessage(error));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _openSheet(
    PhysicalDevice device,
    DeviceEndpoint endpoint,
  ) async {
    final action = await _showChannelQuickSheet(
      context: context,
      device: device,
      endpoint: endpoint,
      state: _displayState(device, endpoint),
      canIdentify: _identifyAvailable,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ChannelQuickAction.open:
        await _openDetail(device);
      case _ChannelQuickAction.rename:
        await _rename(device, endpoint);
      case _ChannelQuickAction.identify:
        await _identify(device, endpoint);
    }
  }

  Future<void> _openDetail(PhysicalDevice device) async {
    final fresh = _freshDevice(device.id, device);
    final snapshot = widget.controller.snapshot;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DeviceDetailPage(
          device: fresh,
          areas: snapshot?.areas ?? const <HomeArea>[],
          gateways: snapshot?.gateways ?? const <GatewayInfo>[],
          repository: widget.repository,
          onCanonicalDeviceChanged: widget.controller.applyCanonicalDevice,
        ),
      ),
    );
  }

  Future<void> _rename(PhysicalDevice device, DeviceEndpoint endpoint) async {
    if (_renaming) return;
    setState(() => _renaming = true);
    try {
      final result = await showDialog<_RenameResult>(
        context: context,
        builder: (_) => _RenameDialog(
          title: 'Cambiar nombre del canal',
          initialName: endpoint.userName,
          fallbackName: endpoint.displayName,
          canReset: endpoint.userName != null,
        ),
      );
      if (result is _RenameCancelled || result == null) return;
      final userName = switch (result) {
        _RenameSet(:final name) => name,
        _RenameClear() => null,
        _RenameCancelled() => null,
      };
      final updated = await widget.repository.renameEndpoint(
        device.id,
        endpoint.id,
        userName,
      );
      if (!mounted) return;
      widget.controller.applyCanonicalDevice(updated);
    } catch (error) {
      if (!mounted) return;
      _showSnack(deviceMutationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  Future<void> _identify(PhysicalDevice device, DeviceEndpoint endpoint) async {
    try {
      final result = await identifyDeviceWithFallback(
        widget.repository,
        device.id,
        endpointId: endpoint.id,
      );
      if (!mounted) return;
      if (!result.supported) {
        _showSnack(identifyUnsupportedMessage(result));
        return;
      }
      _showSnack(
        'Se envió la orden de identificación a '
        '${endpointChannelName(endpoint)}.',
      );
    } on UnsupportedError {
      if (!mounted) return;
      _showSnack('Orden de identificación enviada (simulada)');
    } catch (error) {
      if (!mounted) return;
      _showSnack('No se pudo identificar: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final channel = widget.channels[index];
            final device = _freshDevice(channel.device.id, channel.device);
            final endpoint = _freshEndpoint(device, channel.endpoint);
            final state = _displayState(device, endpoint);
            final key = _key(device.id, endpoint.id);
            return _MobileChannelTile(
              key: ValueKey('mobile-channel-${device.id}-${endpoint.id}'),
              name: endpointChannelName(endpoint),
              icon: endpointChannelIcon(endpoint),
              state: state,
              busy: _busy.contains(key),
              onTap: () => _toggle(device, endpoint),
              onLongPress: () => _openSheet(device, endpoint),
            );
          }, childCount: widget.channels.length),
        ),
      ),
    );
  }
}

/// Resultado del menú secundario de un tile de canal.
enum _ChannelQuickAction { open, rename, identify }

/// Channel actions sheet: open the device detail, rename the channel, and
/// identify it only when the repository can actually run it.
Future<_ChannelQuickAction?> _showChannelQuickSheet({
  required BuildContext context,
  required PhysicalDevice device,
  required DeviceEndpoint endpoint,
  required PowerDisplayState state,
  required bool canIdentify,
}) {
  final name = endpointChannelName(endpoint);
  final deviceName = device.userName ?? device.name;
  final stateColor = switch (state) {
    PowerDisplayState.on => AppColors.statusEncendido,
    PowerDisplayState.off => AppColors.statusApagado,
    PowerDisplayState.unknown => AppColors.textFaint,
  };
  return showModalBottomSheet<_ChannelQuickAction>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    iosKindIcon(endpoint.kind),
                    size: 22,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: stateColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            endpointPowerLabel(state),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              deviceName,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F3F6)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                CupertinoIcons.device_phone_portrait,
                color: AppColors.accent,
              ),
              title: const Text('Ver dispositivo'),
              subtitle: const Text('Estado, conexión y configuración.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ChannelQuickAction.open),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                CupertinoIcons.pencil_outline,
                color: AppColors.accent,
              ),
              title: const Text('Renombrar canal'),
              subtitle: const Text('Poné un nombre para reconocerlo.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ChannelQuickAction.rename),
            ),
            if (canIdentify)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  CupertinoIcons.antenna_radiowaves_left_right,
                  color: AppColors.accent,
                ),
                title: const Text('Identificar'),
                subtitle: const Text(
                  'Parpadea una luz o activa un LED según el adaptador.',
                ),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_ChannelQuickAction.identify),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Compact mobile channel tile: kind icon, channel name and honest state
/// (color + text). Tap toggles the channel; long-press opens its actions.
/// The grid keeps every tile at a comfortable >= 48dp target.
class _MobileChannelTile extends StatelessWidget {
  const _MobileChannelTile({
    super.key,
    required this.name,
    required this.icon,
    required this.state,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
  });

  final String name;
  final IconData icon;
  final PowerDisplayState state;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      PowerDisplayState.on => AppColors.statusEncendido,
      PowerDisplayState.off => AppColors.statusApagado,
      PowerDisplayState.unknown => AppColors.textFaint,
    };
    final label = endpointPowerLabel(state);
    return Semantics(
      button: true,
      enabled: !busy,
      label: '$name, $label',
      onLongPressHint: 'Mostrar más opciones',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F3F6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F5F8),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon, size: 18, color: AppColors.textDim),
                ),
                const Spacer(),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    height: 1.2,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.areas,
    required this.onTap,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final areaName = _areaName(areas, device.physicalAreaId);
    final endpointAreaCount = device.endpoints
        .where((endpoint) => endpoint.controlledAreaId != null)
        .length;
    final subtitle = device.needsConfiguration
        ? '${device.provider} · ${device.model} · ${device.provisioningState == DeviceProvisioningState.partiallyConfigured ? 'Configuración incompleta' : 'Sin configurar'}'
        : areaName != null
        ? '${device.provider} · Ubicado en $areaName'
        : '${device.provider} · $endpointAreaCount endpoint${endpointAreaCount == 1 ? '' : 's'} asignado${endpointAreaCount == 1 ? '' : 's'}';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iosKindIcon(device.kind), color: AppColors.accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _OnlineDot(health: device.health),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filters of the flat mobile devices list. Gateways are infrastructure:
/// they only render under their own chip, never mixed into the device list.
enum _MobileDevicesFilter { all, unconfigured, unassigned, gateways }

/// Flat device management behind the landing's devices button: search, filter
/// chips (Todos / Sin configurar / Sin ubicación / Gateways), discovery and
/// manual add. Every row opens the existing device detail.
class _MobileDevicesListPage extends StatefulWidget {
  const _MobileDevicesListPage({
    required this.snapshot,
    required this.repository,
    required this.controller,
  });

  final DeviceInventorySnapshot snapshot;
  final DeviceInventoryRepository repository;
  final AdaptiveFeatureController controller;

  @override
  State<_MobileDevicesListPage> createState() => _MobileDevicesListPageState();
}

class _MobileDevicesListPageState extends State<_MobileDevicesListPage> {
  _MobileDevicesFilter _filter = _MobileDevicesFilter.all;
  String _query = '';

  /// Newest canonical snapshot so discovery/renames converge without leaving
  /// the page (the controller is shared with the landing).
  DeviceInventorySnapshot get _snapshot =>
      widget.controller.snapshot ?? widget.snapshot;

  Future<void> _showAddDeviceDialog() async {
    final areas = _snapshot.areas;
    final result = await showDialog<_DashboardAddResult>(
      context: context,
      builder: (_) => _DashboardAddDialog(areas: areas, initialAreaId: null),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dispositivo "${result.name}" agregado')),
    );
  }

  Future<void> _discover() async {
    if (widget.controller.discovering) return;
    try {
      final ok = await widget.controller.discover();
      if (!ok || !mounted) return;
      final pending = _snapshot.unassigned.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending == 0
                ? 'No se encontraron dispositivos pendientes.'
                : '$pending dispositivos pendientes de configurar.',
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

  Future<void> _openDetail(PhysicalDevice device) async {
    final snapshot = _snapshot;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DeviceDetailPage(
          device: device,
          areas: snapshot.areas,
          gateways: snapshot.gateways,
          repository: widget.repository,
          onCanonicalDeviceChanged: widget.controller.applyCanonicalDevice,
        ),
      ),
    );
    await widget.controller.loadDevices();
  }

  /// Search covers the display name, the user name and every channel name
  /// (user names included), matching the rows the user actually sees.
  bool _matchesQuery(PhysicalDevice device, String query) {
    if (query.isEmpty) return true;
    if (device.name.toLowerCase().contains(query)) return true;
    if ((device.userName ?? '').toLowerCase().contains(query)) return true;
    return device.endpoints.any(
      (endpoint) => endpointChannelName(endpoint).toLowerCase().contains(query),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final query = _query.trim().toLowerCase();
    final showGateways = _filter == _MobileDevicesFilter.gateways;
    final devices = showGateways
        ? const <PhysicalDevice>[]
        : snapshot.userDevices.where((device) {
            if (!_matchesQuery(device, query)) return false;
            return switch (_filter) {
              _MobileDevicesFilter.all => true,
              _MobileDevicesFilter.unconfigured => device.needsConfiguration,
              _MobileDevicesFilter.unassigned => device.physicalAreaId == null,
              _MobileDevicesFilter.gateways => false,
            };
          }).toList();
    final gateways = showGateways
        ? snapshot.gateways
              .where(
                (gateway) =>
                    query.isEmpty || gateway.name.toLowerCase().contains(query),
              )
              .toList()
        : const <GatewayInfo>[];
    final discovering = widget.controller.discovering;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Dispositivos'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _MobileFilterChip(
                    key: const ValueKey('mobile-devices-chip-all'),
                    label: 'Todos',
                    selected: _filter == _MobileDevicesFilter.all,
                    onSelected: () =>
                        setState(() => _filter = _MobileDevicesFilter.all),
                  ),
                  _MobileFilterChip(
                    key: const ValueKey('mobile-devices-chip-unconfigured'),
                    label: 'Sin configurar',
                    selected: _filter == _MobileDevicesFilter.unconfigured,
                    onSelected: () => setState(
                      () => _filter = _MobileDevicesFilter.unconfigured,
                    ),
                  ),
                  _MobileFilterChip(
                    key: const ValueKey('mobile-devices-chip-unassigned'),
                    label: 'Sin ubicación',
                    selected: _filter == _MobileDevicesFilter.unassigned,
                    onSelected: () => setState(
                      () => _filter = _MobileDevicesFilter.unassigned,
                    ),
                  ),
                  _MobileFilterChip(
                    key: const ValueKey('mobile-devices-chip-gateways'),
                    label: 'Gateways',
                    selected: _filter == _MobileDevicesFilter.gateways,
                    onSelected: () =>
                        setState(() => _filter = _MobileDevicesFilter.gateways),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mobile-devices-search'),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o canal',
                prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('mobile-devices-discover'),
              onPressed: discovering ? null : _discover,
              icon: discovering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar_outlined, size: 20),
              label: Text(discovering ? 'Buscando…' : 'Buscar dispositivos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentStrong,
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: AppColors.accentTintActive),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('mobile-devices-add'),
              onPressed: _showAddDeviceDialog,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Agregar dispositivo'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (showGateways)
              if (gateways.isEmpty)
                const _MobileListEmpty(message: 'No hay gateways.')
              else
                for (final gateway in gateways) ...[
                  _GatewayCard(gateway: gateway),
                  const SizedBox(height: 10),
                ]
            else if (devices.isEmpty)
              _MobileListEmpty(
                message: query.isNotEmpty
                    ? 'No hay dispositivos que coincidan.'
                    : switch (_filter) {
                        _MobileDevicesFilter.unconfigured =>
                          'No hay dispositivos sin configurar.',
                        _MobileDevicesFilter.unassigned =>
                          'No hay dispositivos sin ubicación.',
                        _ => 'No hay dispositivos.',
                      },
              )
            else
              for (final device in devices) ...[
                _DeviceRow(
                  device: device,
                  areas: snapshot.areas,
                  onTap: () => _openDetail(device),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

/// Filter chip of the mobile devices list; >= 40dp tall with the label as the
/// touch target.
class _MobileFilterChip extends StatelessWidget {
  const _MobileFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
    );
  }
}

class _MobileListEmpty extends StatelessWidget {
  const _MobileListEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textDim),
      ),
    );
  }
}

class _DeviceDetailPage extends StatelessWidget {
  const _DeviceDetailPage({
    required this.device,
    required this.areas,
    required this.gateways,
    required this.repository,
    this.onCanonicalDeviceChanged,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final List<GatewayInfo> gateways;
  final DeviceInventoryRepository repository;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Configurar dispositivo'),
      ),
      body: DeviceDetailView(
        device: device,
        areas: areas,
        gateways: gateways,
        repository: repository,
        onCanonicalDeviceChanged: onCanonicalDeviceChanged,
      ),
    );
  }
}

/// How [DeviceDetailView] presents the same canonical device.
enum DeviceDetailPresentation {
  /// Full technical detail (device hero, DISPOSITIVO FÍSICO, ENDPOINTS /
  /// CANALES, INTEGRACIÓN, identify). Used by mobile and desktop surfaces.
  standard,

  /// Household-first detail for the wall panel: display name, 'Nombre',
  /// 'Habitación física', 'Controles', with technical metadata collapsed under
  /// 'Información técnica'. Reuses the same canonical mutation handlers.
  wall,
}

/// Cuerpo de detalle de dispositivo: hero, paneles DISPOSITIVO FÍSICO,
/// ENDPOINTS / CANALES e INTEGRACIÓN y acciones de identificación. Reutilizado
/// por la navegación secuencial móvil (envuelto en Scaffold) y por el panel
/// maestro/detalle de escritorio (Fase 3-C). Sin Scaffold propio: lo aporta el
/// anfitrión. Mantiene su estado local de mutación por dispositivo.
class DeviceDetailView extends StatefulWidget {
  const DeviceDetailView({
    super.key,
    required this.device,
    required this.areas,
    required this.gateways,
    required this.repository,
    this.onCanonicalDeviceChanged,
    this.presentation = DeviceDetailPresentation.standard,
  });

  final PhysicalDevice device;
  final List<HomeArea> areas;
  final List<GatewayInfo> gateways;
  final DeviceInventoryRepository repository;

  /// Called with the canonical device after every successful mutation so the
  /// shared feature state converges immediately (no extra fetch).
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  /// Wall panels render the household-first presentation; everything else
  /// keeps the standard technical detail unchanged.
  final DeviceDetailPresentation presentation;

  @override
  State<DeviceDetailView> createState() => DeviceDetailViewState();
}

class DeviceDetailViewState extends State<DeviceDetailView> {
  late PhysicalDevice _device;
  bool _identifying = false;
  String? _savingEndpoint;
  bool _savingPhysicalArea = false;
  bool _renaming = false;

  /// Endpoint ids with an in-flight power command: only that channel's switch
  /// is disabled while the command is running.
  final Set<String> _powerBusyEndpoints = {};

  /// Last device reference the parent supplied. A parent update that reuses
  /// the same object (bare rebuild) must never clobber a just-committed local
  /// mutation; only a genuinely new reference (e.g. the canonical A' put back
  /// by applyCanonicalDevice) syncs [_device].
  PhysicalDevice? _lastParentDevice;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _lastParentDevice = widget.device;
  }

  @override
  void didUpdateWidget(DeviceDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync only when the parent supplied a NEWER device reference for the
    // same id (after convergence the parent passes the canonical A'). Bare
    // rebuilds with the same old object are identical() and do NOT clobber.
    if (!identical(widget.device, _lastParentDevice)) {
      _lastParentDevice = widget.device;
      if (widget.device.id == _device.id) {
        _device = widget.device;
      }
    }
  }

  Future<void> _renameDevice() async {
    if (_renaming) return;
    setState(() => _renaming = true);
    try {
      final result = await showDialog<_RenameResult>(
        context: context,
        builder: (_) => _RenameDialog(
          title: 'Cambiar nombre del dispositivo',
          initialName: _device.userName,
          fallbackName: _device.name,
          canReset: _device.userName != null,
        ),
      );
      if (result is _RenameCancelled || result == null) return;
      final userName = switch (result) {
        _RenameSet(:final name) => name,
        _RenameClear() => null,
        _RenameCancelled() => null,
      };
      final updated = await widget.repository.renameDevice(
        _device.id,
        userName,
      );
      if (mounted) setState(() => _device = updated);
      widget.onCanonicalDeviceChanged?.call(updated);
      if (mounted) _showSaved('Nombre actualizado');
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
      final result = await showDialog<_RenameResult>(
        context: context,
        builder: (_) => _RenameDialog(
          title: widget.presentation == DeviceDetailPresentation.wall
              ? 'Cambiar nombre del control'
              : 'Cambiar nombre del canal',
          initialName: endpoint.userName,
          fallbackName: endpoint.displayName,
          canReset: endpoint.userName != null,
        ),
      );
      if (result is _RenameCancelled || result == null) return;
      final userName = switch (result) {
        _RenameSet(:final name) => name,
        _RenameClear() => null,
        _RenameCancelled() => null,
      };
      final updated = await widget.repository.renameEndpoint(
        _device.id,
        endpoint.id,
        userName,
      );
      if (mounted) setState(() => _device = updated);
      widget.onCanonicalDeviceChanged?.call(updated);
      if (mounted) _showSaved('Nombre actualizado');
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
      if (mounted) setState(() => _device = updated);
      widget.onCanonicalDeviceChanged?.call(updated);
      if (mounted) _showSaved('Habitación actualizada');
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
      if (mounted) setState(() => _device = updated);
      widget.onCanonicalDeviceChanged?.call(updated);
      if (mounted) _showSaved('Habitación actualizada');
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
      if (mounted) setState(() => _device = updated);
      widget.onCanonicalDeviceChanged?.call(updated);
      if (mounted) _showSaved('Control actualizado');
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
      // Escrituras secuenciales explícitas; tras cada éxito se aplica el
      // estado canónico devuelto por el backend. Si una mutación posterior
      // falla, la UI ya refleja los éxitos previos y solo muestra el error
      // para el resto: nunca queda un estado optimista obsoleto.
      var updated = _device;
      for (final endpoint in _device.endpoints) {
        updated = await widget.repository.assignEndpointArea(
          _device.id,
          endpoint.id,
          areaId,
        );
        if (mounted) setState(() => _device = updated);
        widget.onCanonicalDeviceChanged?.call(updated);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingEndpoint = null);
    }
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

  /// QoL 4: immediate confirmation after a successful mutation (mobile
  /// previously saved silently). Failures keep the existing [_showError] path.
  void _showSaved(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _identify({String? endpointId}) async {
    if (_identifying) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Identificando...')));
      return;
    }
    setState(() => _identifying = true);
    try {
      final result = await identifyDeviceWithFallback(
        widget.repository,
        _device.id,
        endpointId: endpointId,
      );
      if (!mounted) return;
      if (!result.supported) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(identifyUnsupportedMessage(result))),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            endpointId == null
                ? 'Se envió la orden de identificación al dispositivo.'
                : 'Se envió la orden de identificación a $endpointId.',
          ),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orden de identificación enviada (simulada)'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _identifying = false);
    }
  }

  /// Binds a catalog entity to [endpoint] through the segregated command
  /// layer. Only wired when the repository supports commands; the returned
  /// canonical device converges into the shared snapshot. Capability prefers
  /// the canonical `POWER`, falling back to the first declared capability.
  Future<void> _bindEntity(DeviceEndpoint endpoint, String entityId) async {
    final commands = asDeviceCommandRepository(widget.repository);
    if (commands == null) return;
    final capability = endpoint.capabilities.contains('POWER')
        ? 'POWER'
        : endpoint.capabilities.firstOrNull;
    if (capability == null || capability.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El canal no declara capacidades para vincular.'),
        ),
      );
      return;
    }
    try {
      final updated = await commands.bindEntity(
        _device.id,
        endpointId: endpoint.id,
        entityId: entityId,
        capability: capability,
      );
      if (!mounted) return;
      setState(() => _device = updated);
      widget.onCanonicalDeviceChanged?.call(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entidad vinculada')));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  /// Per-channel power command: calls the canonical `set_power` for the
  /// selected endpoint and merges a confirmed observation into the local
  /// canonical device. The typed outcome drives the honest Spanish notice;
  /// failures surface through [powerFailureMessage]. Only the targeted
  /// channel's switch is disabled while the command is in flight.
  Future<void> _setEndpointPower(DeviceEndpoint endpoint, bool value) async {
    if (_powerBusyEndpoints.contains(endpoint.id)) return;
    final commands = asDeviceCommandRepository(widget.repository);
    if (commands == null) return;
    setState(() => _powerBusyEndpoints.add(endpoint.id));
    try {
      final result = await commands.setEndpointPower(
        _device.id,
        endpoint.id,
        value,
      );
      if (!mounted) return;
      _applyEndpointPowerObservation(endpoint.id, result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(powerOutcomeMessage(result, requested: value))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(powerFailureMessage(error))));
    } finally {
      if (mounted) setState(() => _powerBusyEndpoints.remove(endpoint.id));
    }
  }

  /// Merges the confirmed power observation of [result] into the local
  /// canonical device and propagates it to the shared surface state. An
  /// unparsed or unconfirmed answer changes nothing (never a fabricated
  /// state).
  void _applyEndpointPowerObservation(
    String endpointId,
    EndpointPowerResult result,
  ) {
    if (!result.responseParsed ||
        result.observedPower == null ||
        result.observedQuality == null) {
      return;
    }
    final updated = _device.copyWith(
      endpoints: [
        for (final candidate in _device.endpoints)
          if (candidate.id == endpointId)
            candidate.copyWith(
              observedPower: result.observedPower,
              observedQuality: result.observedQuality,
              observedAt: result.observedAt,
            )
          else
            candidate,
      ],
    );
    setState(() => _device = updated);
    widget.onCanonicalDeviceChanged?.call(updated);
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
    if (widget.presentation == DeviceDetailPresentation.wall) {
      return _buildWallDetail(gateway);
    }
    return _buildStandardDetail(gateway);
  }

  /// Standard detail shared by the mobile flow and the narrow desktop push.
  /// Wall surfaces take the household-first [_buildWallDetail] branch instead.
  ///
  /// Household-first order (Pattern C): Control first, then Estado, then a
  /// collapsed Configuración. The per-channel switches live in the CONTROLES
  /// panel; the per-channel editors keep only rename/area/role/bindings.
  Widget _buildStandardDetail(GatewayInfo? gateway) {
    final powerChannels = powerEndpoints(_device);
    final commands = asDeviceCommandRepository(widget.repository);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
      children: [
        _DeviceHero(device: _device, onRename: _renameDevice),
        const SizedBox(height: 18),
        if (powerChannels.isNotEmpty) ...[
          _Panel(
            title: 'CONTROLES',
            child: Column(
              children: [
                for (var index = 0; index < powerChannels.length; index++) ...[
                  _ChannelControlRow(
                    key: ValueKey('channel-control-${powerChannels[index].id}'),
                    endpoint: powerChannels[index],
                    busy: _powerBusyEndpoints.contains(powerChannels[index].id),
                    onPowerChanged: commands == null
                        ? null
                        : (value) =>
                              _setEndpointPower(powerChannels[index], value),
                  ),
                  if (index != powerChannels.length - 1)
                    const Divider(height: 24, color: AppColors.border),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _Panel(
          title: 'ESTADO',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _OnlineDot(health: _device.health),
                  const SizedBox(width: 7),
                  Text(
                    deviceConnectionLabel(_device.health),
                    style: TextStyle(
                      color: healthToColor(_device.health),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_device.lastSeenLabel != null) ...[
                    const Text(
                      ' · ',
                      style: TextStyle(color: AppColors.textFaint),
                    ),
                    Flexible(
                      child: Text(
                        _device.lastSeenLabel!,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // The hero already carries identity; credentials/gateway live
              // in the Estado block so the control surface stays uncluttered.
              if (_device.pendingKey == true) ...[
                const SizedBox(height: 10),
                const PendingCredentialsBadge(),
              ],
              if (gateway != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.hub_outlined,
                      size: 16,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Gateway: ${gateway.name}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _identify(),
                icon: _identifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.antenna_radiowaves_left_right),
                label: Text(
                  _identifying ? 'Identificando…' : 'Identificar dispositivo',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '“Identificar” envía una orden al dispositivo para parpadear una luz o activar un LED según el adaptador.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Configuration is progressive disclosure: collapsed by default, the
        // body is removed from the tree until expanded (same contract as the
        // wall 'Información técnica' tile).
        _ConfigSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AreaDropdown(
                key: const Key('physical-area-dropdown'),
                label: 'Ubicación física',
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
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Guardando cambios, espera un momento...',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(CupertinoIcons.doc_on_doc, size: 17),
                  label: const Text('Usar también para todos los canales'),
                ),
              ],
              for (
                var index = 0;
                index < _device.endpoints.length;
                index++
              ) ...[
                const Divider(height: 30, color: AppColors.border),
                _EndpointEditor(
                  endpoint: _device.endpoints[index],
                  areas: widget.areas,
                  busy: _savingEndpoint == _device.endpoints[index].id,
                  onChanged: (areaId) =>
                      _setEndpointArea(_device.endpoints[index], areaId),
                  onIdentify: () =>
                      _identify(endpointId: _device.endpoints[index].id),
                  onRename: () => _renameEndpoint(_device.endpoints[index]),
                  onRoleChanged: widget.repository.supportsSemanticRole
                      ? (role) =>
                            _setEndpointRole(_device.endpoints[index], role)
                      : null,
                  onBindEntity: commands == null
                      ? null
                      : (entityId) =>
                            _bindEntity(_device.endpoints[index], entityId),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'INTEGRACIÓN',
          child: Column(
            children: [
              _MetadataRow(
                label: 'Tipo de dispositivo',
                value: deviceClassLabel(_device.deviceClass),
              ),
              if (_device.deviceClassSource == 'provider')
                const _MetadataRow(label: 'Detectado por', value: 'Proveedor'),
              _MetadataRow(label: 'Proveedor', value: _device.provider),
              _MetadataRow(label: 'ID Gamma', value: _device.id),
              if (_device.providerDeviceId.isNotEmpty)
                _MetadataRow(
                  label: 'ID proveedor',
                  value: _device.providerDeviceId,
                ),
              _MetadataRow(label: 'Modelo', value: _device.model),
              if (_device.manufacturer != null)
                _MetadataRow(label: 'Fabricante', value: _device.manufacturer!),
            ],
          ),
        ),
      ],
    );
  }

  /// Household-first wall detail: display name + 'Nombre' rename, 'Habitación
  /// física', 'Controles', and technical metadata collapsed under 'Información
  /// técnica'. Same mutation handlers as the standard branch.
  Widget _buildWallDetail(GatewayInfo? gateway) {
    // SingleChildScrollView builds every section up front (the collapsed
    // 'Información técnica' tile included) while staying non-clipping at any
    // text scale; natural heights, no fixed sizes.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WallDeviceHero(device: _device, onRename: _renameDevice),
          const SizedBox(height: 14),
          _WallCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AreaDropdown(
                  key: const Key('physical-area-dropdown'),
                  label: 'Habitación física',
                  value: _device.physicalAreaId,
                  areas: widget.areas,
                  enabled: !_savingPhysicalArea,
                  onChanged: _setPhysicalArea,
                  verticalContentPadding: 22,
                ),
                if (_device.physicalAreaId != null &&
                    _device.endpoints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _savingEndpoint == null
                        ? _applyPhysicalAreaToEndpoints
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Guardando cambios, espera un momento...',
                                ),
                              ),
                            );
                          },
                    icon: const Icon(CupertinoIcons.doc_on_doc, size: 17),
                    label: const Text('Usar también para todos los controles'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Controles',
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < _device.endpoints.length;
                  index++
                ) ...[
                  _WallEndpointEditor(
                    endpoint: _device.endpoints[index],
                    areas: widget.areas,
                    busy: _savingEndpoint == _device.endpoints[index].id,
                    showPowerState: powerEndpoints(_device).length > 1,
                    onAreaChanged: (areaId) =>
                        _setEndpointArea(_device.endpoints[index], areaId),
                    onRoleChanged: widget.repository.supportsSemanticRole
                        ? (role) =>
                              _setEndpointRole(_device.endpoints[index], role)
                        : null,
                    onRename: () => _renameEndpoint(_device.endpoints[index]),
                  ),
                  if (index != _device.endpoints.length - 1)
                    const Divider(height: 28, color: AppColors.border),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _WallTechnicalSection(gateway: gateway, device: _device),
        ],
      ),
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
                    if (device.pendingKey == true) ...[
                      const SizedBox(height: 6),
                      const PendingCredentialsBadge(),
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
            icon: const Icon(CupertinoIcons.pencil_outline, size: 26),
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
    this.showPowerState = false,
  });

  final DeviceEndpoint endpoint;
  final List<HomeArea> areas;
  final bool busy;
  final ValueChanged<String?> onAreaChanged;
  final VoidCallback onRename;
  final ValueChanged<String?>? onRoleChanged;

  /// Whether the device has more than one power endpoint: only then is the
  /// per-control state shown (single-control devices already surface it in
  /// the device-level power card).
  final bool showPowerState;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    endpoint.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (showPowerState && hasPowerCapability(endpoint)) ...[
                    const SizedBox(height: 3),
                    EndpointPowerBadge(
                      endpoint: endpoint,
                      onColor: AppColors.green,
                      offColor: AppColors.red,
                      fontSize: 13,
                    ),
                  ],
                ],
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
              icon: const Icon(CupertinoIcons.pencil_outline, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (onRoleChanged != null) ...[
          _RoleDropdown(
            value: endpoint.semanticRole,
            enabled: !busy,
            onChanged: onRoleChanged!,
            verticalContentPadding: 22,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              _roleSourceLabel(endpoint),
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _AreaDropdown(
          label: 'Habitación que controla',
          value: endpoint.controlledAreaId,
          areas: areas,
          enabled: !busy,
          onChanged: onAreaChanged,
          verticalContentPadding: 22,
        ),
      ],
    );
  }
}

/// Collapsed-by-default technical metadata for the wall surface. The body is
/// removed from the tree until expanded (ExpansionTile maintainState:false),
/// so raw IDs/providers never leak into the primary wall view.
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
            _MetadataRow(
              label: 'Tipo de dispositivo',
              value: deviceClassLabel(device.deviceClass),
            ),
            if (device.deviceClassSource == 'provider')
              const _MetadataRow(label: 'Detectado por', value: 'Proveedor'),
            _MetadataRow(label: 'Proveedor', value: device.provider),
            _MetadataRow(label: 'ID Gamma', value: device.id),
            if (device.providerDeviceId.isNotEmpty)
              _MetadataRow(
                label: 'ID proveedor',
                value: device.providerDeviceId,
              ),
            _MetadataRow(label: 'Modelo', value: device.model),
            if (device.manufacturer != null)
              _MetadataRow(label: 'Fabricante', value: device.manufacturer!),
            if (gatewayName != null)
              _MetadataRow(label: 'Gateway', value: gatewayName),
          ],
        ),
      ),
    );
  }
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({required this.device, this.onRename});

  final PhysicalDevice device;

  /// When provided, shows a rename affordance.
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final meta = deviceKindMeta(device.kind);
    final primaryName = device.userName ?? device.name;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(meta.icon, size: 30, color: AppColors.accent),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        primaryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onRename != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Cambiar nombre',
                        onPressed: onRename,
                        icon: Icon(
                          CupertinoIcons.pencil_outline,
                          size: 18,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${meta.label} · ${device.model}',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
                // F2-C: provider name is read-only secondary metadata.
                if (device.providerName != null &&
                    device.providerName != primaryName) ...[
                  const SizedBox(height: 2),
                  Text(
                    device.providerName!,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    _OnlineDot(health: device.health),
                    const SizedBox(width: 5),
                    Text(
                      healthLabel(device.health),
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11.5,
                      ),
                    ),
                    if (device.lastSeenLabel != null) ...[
                      const Text(
                        ' · ',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                      Flexible(
                        child: Text(
                          device.lastSeenLabel!,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (device.health == DeviceHealthState.unknown) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Cloud observado · control local no validado',
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
                // The 'Sin credenciales' chip lives in the Estado block of
                // the standard detail; the hero keeps identity only.
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.15,
            ),
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}

/// Collapsed-by-default configuration group of the standard detail. The body
/// is removed from the tree until expanded, so the primary view stays
/// control-first (same ExpansionTile contract as the wall technical tile).
class _ConfigSection extends StatelessWidget {
  const _ConfigSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
          key: const Key('device-config-section'),
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
          title: const Text('Configuración'),
          children: [child],
        ),
      ),
    );
  }
}

/// One household control row of the CONTROLES panel: role icon, channel name,
/// honest power state (color + text) and the per-channel switch. The switch
/// keeps the canonical command path and the per-channel busy guard; when the
/// repository exposes no command layer the switch is omitted instead of
/// faking a control.
class _ChannelControlRow extends StatelessWidget {
  const _ChannelControlRow({
    super.key,
    required this.endpoint,
    required this.busy,
    this.onPowerChanged,
  });

  final DeviceEndpoint endpoint;
  final bool busy;
  final ValueChanged<bool>? onPowerChanged;

  @override
  Widget build(BuildContext context) {
    final state = endpointPowerDisplayState(endpoint);
    final color = switch (state) {
      PowerDisplayState.on => AppColors.statusEncendido,
      PowerDisplayState.off => AppColors.statusApagado,
      PowerDisplayState.unknown => AppColors.textFaint,
    };
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            endpointChannelIcon(endpoint),
            size: 22,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                endpointChannelName(endpoint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    endpointPowerLabel(state),
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (onPowerChanged != null)
          Switch(
            value: state == PowerDisplayState.on,
            activeTrackColor: AppColors.accent,
            onChanged: busy ? null : onPowerChanged,
          ),
      ],
    );
  }
}

class _EndpointEditor extends StatelessWidget {
  const _EndpointEditor({
    required this.endpoint,
    required this.areas,
    required this.busy,
    required this.onChanged,
    required this.onIdentify,
    this.onRename,
    this.onRoleChanged,
    this.onBindEntity,
  });

  final DeviceEndpoint endpoint;
  final List<HomeArea> areas;
  final bool busy;
  final ValueChanged<String?> onChanged;

  /// Always visible — when the repository does not support identify, the
  /// callback shows an informational SnackBar instead of being null.
  final VoidCallback onIdentify;

  /// F2-C rename affordance; null hides it.
  final VoidCallback? onRename;

  /// F2-D closure: user semantic-role override (null = clear). Null hides
  /// the role selector (e.g. unsupported repository).
  final ValueChanged<String?>? onRoleChanged;

  /// Real binding through the command layer. Null keeps the legacy simulated
  /// confirmation (plain test fakes without command support).
  final Future<void> Function(String entityId)? onBindEntity;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    endpoint.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    endpoint.capabilities.join(' · '),
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (onRename != null)
              IconButton(
                tooltip: 'Cambiar nombre del canal',
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
                icon: Icon(
                  CupertinoIcons.pencil_outline,
                  size: 18,
                  color: AppColors.accent,
                ),
              ),
            TextButton.icon(
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
                  : onIdentify,
              icon: const Icon(
                CupertinoIcons.antenna_radiowaves_left_right,
                size: 16,
              ),
              label: const Text('Identificar'),
            ),
          ],
        ),
        // F2-C: global backend-computed display, rendered exactly.
        if (endpoint.displayNameGlobal != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 29),
            child: Text(
              endpoint.displayNameGlobal!,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ),
        ],
        if (endpoint.userName != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 29),
            child: Text(
              'Nombre personalizado: ${endpoint.userName}',
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _AreaDropdown(
          label: endpoint.kind == DeviceKind.sensor
              ? 'Área semántica'
              : 'Área que controla',
          value: endpoint.controlledAreaId,
          areas: areas,
          enabled: !busy,
          onChanged: onChanged,
        ),
        if (onRoleChanged != null) ...[
          const SizedBox(height: 10),
          _RoleDropdown(
            value: endpoint.semanticRole,
            enabled: !busy,
            onChanged: onRoleChanged!,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              _roleSourceLabel(endpoint),
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
        ],
        if (_hasActionableCapability(endpoint)) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => _LinkEntityDialog(endpointId: endpoint.id),
                );
                if (result == null) return;
                if (!context.mounted) return;
                final bindEntity = onBindEntity;
                if (bindEntity != null) {
                  await bindEntity(result);
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Vinculación simulada con éxito: $result'),
                  ),
                );
              },
              icon: const Icon(CupertinoIcons.link, size: 17),
              label: const Text('Vincular entidad'),
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Vincula este canal con una entidad del catálogo.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 10.5),
            ),
          ),
        ],
        if (endpoint.bindings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final binding in endpoint.bindings)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                binding.label,
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AreaDropdown extends StatelessWidget {
  const _AreaDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.areas,
    required this.enabled,
    required this.onChanged,
    this.verticalContentPadding = 16,
  });

  final String label;
  final String? value;
  final List<HomeArea> areas;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// Extra vertical padding raises the touch target; wall passes 22 to reach
  /// >= 64dp. Standard keeps the compact 16.
  final double verticalContentPadding;

  @override
  Widget build(BuildContext context) {
    final dropdown = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceRaised,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: verticalContentPadding,
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

/// Canonical semantic-role options (F2-D closure). Only backend-supported
/// roles appear; "Sin configurar" clears the user override.
const _semanticRoleOptions = <String, String>{
  'light': 'Luz',
  'switch': 'Interruptor',
  'fan': 'Ventilador',
  'extractor': 'Extractor',
  'sensor': 'Sensor',
};

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.verticalContentPadding = 16,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// Wall raises the touch target to >= 64dp; standard keeps the compact 16.
  final double verticalContentPadding;

  @override
  Widget build(BuildContext context) {
    final current = value ?? 'unknown';
    final dropdown = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            'Qué controla',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _semanticRoleOptions.containsKey(current)
              ? current
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceRaised,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: verticalContentPadding,
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
            for (final entry in _semanticRoleOptions.entries)
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

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

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

/// Gateway summary card: infraestructura de la casa, rendered inline under
/// the 'Gateways' chip of the flat device list.
class _GatewayCard extends StatelessWidget {
  const _GatewayCard({required this.gateway});

  final GatewayInfo gateway;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              CupertinoIcons.personalhotspot,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gateway.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${gateway.provider} · ${gateway.childDeviceIds.length} subdispositivos',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  healthLabel(gateway.health),
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          _OnlineDot(health: gateway.health),
        ],
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.health});

  final DeviceHealthState health;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: switch (health) {
          DeviceHealthState.online => AppColors.green,
          DeviceHealthState.offline => AppColors.red,
          _ => AppColors.amber,
        },
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Capacidades canónicas con capacidad de control/acción; un endpoint que
/// las expone es candidato a binding, independientemente de su DeviceKind.
const _actionableCapabilities = {
  'POWER',
  'BRIGHTNESS',
  'COLOR',
  'COLOR_TEMPERATURE',
  'SPEED',
  'MODE',
  'POSITION',
  'OPEN_CLOSE',
};

bool _hasActionableCapability(DeviceEndpoint endpoint) =>
    endpoint.capabilities.any(_actionableCapabilities.contains);

String healthLabel(DeviceHealthState health) {
  return switch (health) {
    DeviceHealthState.online => 'Online',
    DeviceHealthState.offline => 'Sin conexión',
    DeviceHealthState.unknown => 'Estado desconocido',
    DeviceHealthState.sleeping => 'En reposo',
    DeviceHealthState.unreachable => 'No accesible',
    DeviceHealthState.authError => 'Error de acceso',
  };
}

String? _areaName(List<HomeArea> areas, String? areaId) {
  if (areaId == null) return null;
  for (final area in areas) {
    if (area.id == areaId) return area.name;
  }
  return areaId;
}

const _locationAliases = {
  'bano': 'Baño',
  'baño': 'Baño',
  'recamara': 'Recámara',
  'comedor': 'Comedor',
  'cocina': 'Cocina',
  'patio': 'Patio',
  'sala': 'Sala',
  'garaje': 'Garaje',
  'entrada': 'Entrada',
  'pasillo': 'Pasillo',
};

String formatLocationName(String location) {
  // Canonical AreaStore IDs (area_<hex>) carry no readable name; the
  // catalog provides display_name for them. If one leaks through (e.g. a
  // status device location), never render the raw id: show a neutral label.
  if (RegExp(r'^area_[0-9a-f]+$').hasMatch(location)) return 'Área';
  final name = location
      .replaceAll(RegExp(r'_\d+$'), '')
      .replaceAll('_', ' ')
      .trim();
  if (name.isEmpty) return 'Sin ubicación';
  final normalized = name.toLowerCase();
  return _locationAliases[normalized] ??
      '${name[0].toUpperCase()}${name.substring(1)}';
}

/// Localized label for a canonical DeviceClass value. Raw enum values are
/// never shown to the user; UNKNOWN renders as "Desconocido".
String deviceClassLabel(String deviceClass) {
  return switch (deviceClass) {
    'light' => 'Luz',
    'switch' => 'Interruptor',
    'relay' => 'Relé',
    'outlet' => 'Enchufe',
    'fan' => 'Ventilador',
    'sensor' => 'Sensor',
    _ => 'Desconocido',
  };
}

/// User-facing provenance label for the endpoint semantic role. Uses the
/// backend ``semantic_role_source``; never inferred from role equality.
String _roleSourceLabel(DeviceEndpoint endpoint) {
  switch (endpoint.semanticRoleSource) {
    case 'user':
      return 'Configurado manualmente';
    case 'provider':
      return 'Detectado automáticamente';
    default:
      return 'Sin configurar';
  }
}

IconData locationIcon(String location) {
  final name = location.toLowerCase();
  if (name.contains('cocina')) return Icons.soup_kitchen;
  if (name.contains('recamara')) return Icons.bed;
  if (name.contains('baño') || name.contains('bano')) return Icons.bathtub;
  if (name.contains('patio')) return Icons.park;
  if (name.contains('pasillo')) return Icons.meeting_room_outlined;
  if (name.contains('comedor')) return Icons.table_restaurant_outlined;
  return Icons.home;
}

/// iOS-style (SF Symbols via CupertinoIcons) variants for the MOBILE surface.
///
/// The Material [locationIcon]/[deviceKindMeta] originals stay untouched
/// because the wall panel ([WallDevicesPage]) consumes them; mobile call
/// sites use these instead so desktop/wall rendering never changes.
IconData iosLocationIcon(String location) {
  final name = location.toLowerCase();
  // iOS approx: no kitchen icon — flame reads as stove.
  if (name.contains('cocina')) return CupertinoIcons.flame;
  if (name.contains('recamara')) return CupertinoIcons.bed_double;
  // iOS approx: no bathtub icon — drop reads as water/bathroom.
  if (name.contains('baño') || name.contains('bano')) {
    return CupertinoIcons.drop;
  }
  if (name.contains('patio')) return CupertinoIcons.tree;
  // iOS approx: no hallway icon — passage arrows read as corridor.
  if (name.contains('pasillo')) return CupertinoIcons.arrow_left_right;
  if (name.contains('comedor')) return CupertinoIcons.table;
  return CupertinoIcons.house;
}

/// iOS-style device-kind icon for the MOBILE surface (see [iosLocationIcon]).
IconData iosKindIcon(DeviceKind kind) {
  return switch (kind) {
    DeviceKind.light => CupertinoIcons.lightbulb,
    // iOS approx: no on/off-switch icon — sliders read as switch controls.
    DeviceKind.switchController => CupertinoIcons.slider_horizontal_3,
    DeviceKind.outlet => CupertinoIcons.power,
    DeviceKind.sensor => CupertinoIcons.eye,
    // iOS approx: no hub icon — shared-connection point reads as gateway.
    DeviceKind.gateway => CupertinoIcons.personalhotspot,
    DeviceKind.unknown => CupertinoIcons.square_stack,
  };
}

({IconData icon, String label}) deviceKindMeta(DeviceKind kind) {
  return switch (kind) {
    DeviceKind.light => (icon: Icons.lightbulb, label: 'Luz'),
    DeviceKind.switchController => (
      icon: Icons.toggle_on_outlined,
      label: 'Interruptor',
    ),
    DeviceKind.outlet => (icon: Icons.power, label: 'Enchufe'),
    DeviceKind.sensor => (icon: Icons.sensors, label: 'Sensor'),
    DeviceKind.gateway => (icon: Icons.hub_outlined, label: 'Gateway'),
    DeviceKind.unknown => (icon: Icons.devices, label: 'Dispositivo'),
  };
}

({IconData icon, String label}) deviceTypeMeta(String deviceId) {
  final family = deviceId.split('_').first.toLowerCase();
  return switch (family) {
    'luz' || 'foco' => (icon: CupertinoIcons.lightbulb, label: 'Luz'),
    'enchufe' => (icon: CupertinoIcons.power, label: 'Enchufe'),
    'ventilador' => (icon: CupertinoIcons.wind, label: 'Ventilador'),
    'sensor' => (icon: CupertinoIcons.thermometer, label: 'Sensor'),
    'camara' => (icon: CupertinoIcons.videocam, label: 'Cámara'),
    _ => (icon: CupertinoIcons.square_stack, label: 'Dispositivo'),
  };
}

String formatDeviceName(String deviceId) {
  final parts = deviceId.split('_');
  final meta = deviceTypeMeta(deviceId);
  final number = parts.length > 1 ? parts[1] : '';
  return number.isEmpty ? meta.label : '${meta.label} $number';
}

class _LinkEntityDialog extends StatefulWidget {
  const _LinkEntityDialog({required this.endpointId});
  final String endpointId;
  @override
  State<_LinkEntityDialog> createState() => _LinkEntityDialogState();
}

class _LinkEntityDialogState extends State<_LinkEntityDialog> {
  late final TextEditingController _controller = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Ingresá un identificador de entidad.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vincular entidad'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Entidad',
          hintText: 'ej: light.cocina_principal',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Vincular')),
      ],
    );
  }
}

/// F2-C rename outcome: set, clear (null) or cancelled.
sealed class _RenameResult {
  const _RenameResult();
}

class _RenameSet extends _RenameResult {
  const _RenameSet(this.name);
  final String name;
}

class _RenameClear extends _RenameResult {
  const _RenameClear();
}

class _RenameCancelled extends _RenameResult {
  const _RenameCancelled();
}

/// F2-C rename dialog with explicit null-clear semantics.
///
/// Returns a [_RenameResult]: set (non-empty string), clear (null sentinel)
/// or cancelled. The repository translates clear to the backend null.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
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
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
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
    Navigator.of(context).pop(_RenameSet(value));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nombre personalizado',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            Text(
              'El nombre del fabricante/proveedor no se modifica. '
              'Sin nombre personalizado se muestra: ${widget.fallbackName}',
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _RenameClear()),
            child: const Text('Restablecer nombre'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(const _RenameCancelled()),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
