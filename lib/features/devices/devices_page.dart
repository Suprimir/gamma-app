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
  String _query = '';

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

  Future<void> _showAddDeviceDialog() async {
    final snapshot = _controller.snapshot;
    final areas = snapshot?.areas ?? const <HomeArea>[];
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
    _controller.addLocalDevice(device);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dispositivo "${result.name}" agregado')),
    );
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    await _controller.loadDevices();
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
    // Móvil area-first: la pantalla principal muestra las ubicaciones de la
    // casa; al seleccionar una se accede a sus dispositivos con tarjetas de
    // acción rápida. Mismo lenguaje visual del dashboard (search pill, botón
    // + azul, tarjetas blancas, toggle y badge de conteo).
    final devices = snapshot.userDevices;
    final query = _query.trim().toLowerCase();
    final areas = snapshot.areas
        .where(
          (area) => query.isEmpty || area.name.toLowerCase().contains(query),
        )
        .toList();
    final unassigned = snapshot.unassigned;
    final noAreaDevices = devices
        .where((device) => device.physicalAreaId == null)
        .toList();
    final offlineDevices = devices
        .where((device) => device.health == DeviceHealthState.offline)
        .toList();

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Búsqueda de ubicaciones (mismo Search pill) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: TextField(
                    key: const Key('mobile-device-search'),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Buscar ubicaciones',
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
                ),
              ),
              // ── + agregar + encabezado "Tus ubicaciones" ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Agregar dispositivo',
                        child: GestureDetector(
                          onTap: _showAddDeviceDialog,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.accent),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.add,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Tus ubicaciones',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          letterSpacing: -0.01,
                        ),
                      ),
                      const SizedBox(width: 8),
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
                          '${areas.length}',
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
              // ── Grid 2 columnas de ubicaciones ──
              if (areas.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                    child: Text(
                      'No hay ubicaciones que mostrar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.95,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final area = areas[index];
                      return _AreaCard(
                        area: area,
                        count: snapshot.devicesInArea(area.id).length,
                        onTap: () => _open(
                          _MobileDeviceGridPage.forArea(
                            area: area,
                            snapshot: snapshot,
                            repository: widget.repository,
                            controller: _controller,
                            onCanonicalDeviceChanged:
                                _controller.applyCanonicalDevice,
                          ),
                        ),
                      );
                    }, childCount: areas.length),
                  ),
                ),
              // ── Explorar: accesos al resto del inventario ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'EXPLORAR',
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.25,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  child: Column(
                    children: [
                      _NavigationRow(
                        icon: CupertinoIcons.square_stack,
                        title: 'Todos los dispositivos',
                        subtitle:
                            '${devices.length} en casa · acción rápida incluida',
                        badge: '${devices.length}',
                        onTap: () => _open(
                          _MobileDeviceGridPage.all(
                            snapshot: snapshot,
                            repository: widget.repository,
                            controller: _controller,
                            onCanonicalDeviceChanged:
                                _controller.applyCanonicalDevice,
                          ),
                        ),
                      ),
                      if (noAreaDevices.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _NavigationRow(
                          icon: CupertinoIcons.question_circle,
                          title: 'Sin ubicación',
                          subtitle: 'Sin área asignada',
                          badge: '${noAreaDevices.length}',
                          onTap: () => _open(
                            _MobileDeviceGridPage(
                              title: 'Sin ubicación',
                              subtitle:
                                  'Dispositivos sin área asignada, con acción rápida.',
                              devices: noAreaDevices,
                              areas: snapshot.areas,
                              gateways: snapshot.gateways,
                              repository: widget.repository,
                              controller: _controller,
                              emptyMessage:
                                  'No hay dispositivos sin ubicación.',
                              onCanonicalDeviceChanged:
                                  _controller.applyCanonicalDevice,
                            ),
                          ),
                        ),
                      ],
                      if (unassigned.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _NavigationRow(
                          icon: CupertinoIcons.sparkles,
                          title: 'Nuevos dispositivos',
                          subtitle: 'Pendientes de configurar',
                          badge: '${unassigned.length}',
                          onTap: () => _open(
                            _PendingDevicesPage(
                              repository: widget.repository,
                              snapshot: snapshot,
                              onCanonicalDeviceChanged:
                                  _controller.applyCanonicalDevice,
                            ),
                          ),
                        ),
                      ],
                      if (offlineDevices.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _NavigationRow(
                          icon: CupertinoIcons.wifi_slash,
                          title: 'Desconectados',
                          subtitle: 'Requieren revisión',
                          badge: '${offlineDevices.length}',
                          badgeColor: AppColors.red,
                          onTap: () => _open(
                            _MobileDeviceGridPage(
                              title: 'Desconectados',
                              subtitle:
                                  'Dispositivos sin conexión, con acción rápida.',
                              devices: offlineDevices,
                              areas: snapshot.areas,
                              gateways: snapshot.gateways,
                              repository: widget.repository,
                              controller: _controller,
                              emptyMessage:
                                  'No hay dispositivos desconectados.',
                              onCanonicalDeviceChanged:
                                  _controller.applyCanonicalDevice,
                            ),
                          ),
                        ),
                      ],
                      if (snapshot.gateways.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _NavigationRow(
                          icon: CupertinoIcons.personalhotspot,
                          title: 'Gateways',
                          subtitle: 'Infraestructura de la casa',
                          badge: '${snapshot.gateways.length}',
                          onTap: () => _open(_GatewaysPage(snapshot: snapshot)),
                        ),
                      ],
                    ],
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
        label: 'Sin datos',
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

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.area,
    required this.count,
    required this.onTap,
  });

  final HomeArea area;
  final int count;
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.accentTint,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      iosLocationIcon(area.id),
                      color: AppColors.accent,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    color: AppColors.textFaint,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                area.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count ${count == 1 ? 'elemento' : 'elementos'}',
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.badgeColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final badgeColor = this.badgeColor ?? AppColors.accentStrong;
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
              Icon(icon, color: AppColors.textDim),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 6),
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
    this.hideAreaName = false,
    this.onCanonicalDeviceChanged,
  });

  /// Grid de una ubicación: filtra por área y oculta el subtítulo de área
  /// porque todas las tarjetas pertenecen a la misma ubicación.
  factory _MobileDeviceGridPage.forArea({
    required HomeArea area,
    required DeviceInventorySnapshot snapshot,
    required DeviceInventoryRepository repository,
    required AdaptiveFeatureController controller,
    ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged,
  }) {
    return _MobileDeviceGridPage(
      title: area.name,
      subtitle: 'Dispositivos de ${area.name}, con acción rápida.',
      devices: snapshot.devicesInArea(area.id),
      areas: snapshot.areas,
      gateways: snapshot.gateways,
      repository: repository,
      controller: controller,
      emptyMessage: 'No hay dispositivos asignados a ${area.name}.',
      hideAreaName: true,
      onCanonicalDeviceChanged: onCanonicalDeviceChanged,
    );
  }

  /// Grid con todo el inventario de usuario.
  factory _MobileDeviceGridPage.all({
    required DeviceInventorySnapshot snapshot,
    required DeviceInventoryRepository repository,
    required AdaptiveFeatureController controller,
    ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged,
  }) {
    return _MobileDeviceGridPage(
      title: 'Todos los dispositivos',
      subtitle: 'Todo el inventario de la casa, con acción rápida.',
      devices: snapshot.userDevices,
      areas: snapshot.areas,
      gateways: snapshot.gateways,
      repository: repository,
      controller: controller,
      emptyMessage: 'No hay dispositivos configurados.',
      onCanonicalDeviceChanged: onCanonicalDeviceChanged,
    );
  }

  final String title;
  final String subtitle;
  final List<PhysicalDevice> devices;
  final List<HomeArea> areas;
  final List<GatewayInfo> gateways;
  final DeviceInventoryRepository repository;
  final AdaptiveFeatureController controller;
  final String emptyMessage;
  final bool hideAreaName;
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

class _PendingDevicesPage extends StatelessWidget {
  const _PendingDevicesPage({
    required this.repository,
    required this.snapshot,
    this.onCanonicalDeviceChanged,
  });

  final DeviceInventoryRepository repository;
  final DeviceInventorySnapshot snapshot;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  @override
  Widget build(BuildContext context) {
    return _DeviceListScaffold(
      title: 'Nuevos dispositivos',
      subtitle:
          'Todavía no forman parte de la estructura semántica de la casa.',
      devices: snapshot.unassigned,
      snapshot: snapshot,
      repository: repository,
      emptyMessage: 'No hay dispositivos nuevos.',
      pendingOnly: true,
      onCanonicalDeviceChanged: onCanonicalDeviceChanged,
    );
  }
}

class _DeviceListScaffold extends StatefulWidget {
  const _DeviceListScaffold({
    required this.title,
    required this.subtitle,
    required this.devices,
    required this.snapshot,
    required this.repository,
    required this.emptyMessage,
    this.pendingOnly = false,
    this.onCanonicalDeviceChanged,
  });

  final String title;
  final String subtitle;
  final List<PhysicalDevice> devices;
  final DeviceInventorySnapshot snapshot;
  final DeviceInventoryRepository repository;
  final String emptyMessage;
  final bool pendingOnly;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  @override
  State<_DeviceListScaffold> createState() => _DeviceListScaffoldState();
}

class _DeviceListScaffoldState extends State<_DeviceListScaffold> {
  late List<PhysicalDevice> _devices;

  @override
  void initState() {
    super.initState();
    _devices = List.of(widget.devices);
  }

  Future<void> _openDevice(PhysicalDevice device) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DeviceDetailPage(
          device: device,
          areas: widget.snapshot.areas,
          gateways: widget.snapshot.gateways,
          repository: widget.repository,
          onCanonicalDeviceChanged: widget.onCanonicalDeviceChanged,
        ),
      ),
    );
    DeviceInventorySnapshot latest;
    try {
      latest = await widget.repository.load();
    } catch (_) {
      // Refrescar tras volver del detalle no debe romper la vista si el
      // backend no responde; la lista conserva el último estado canónico.
      return;
    }
    if (!mounted) return;
    final ids = _devices.map((device) => device.id).toSet();
    var refreshed = latest.devices
        .where((device) => ids.contains(device.id))
        .toList();
    if (widget.pendingOnly) {
      refreshed = latest.unassigned;
    }
    setState(() => _devices = refreshed);
  }

  @override
  Widget build(BuildContext context) {
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
                  child: Text(widget.emptyMessage, textAlign: TextAlign.center),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final device in _devices) ...[
                    _DeviceRow(
                      device: device,
                      areas: widget.snapshot.areas,
                      onTap: () => _openDevice(device),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
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

  /// Byte-identical standard detail (mobile/desktop). Wall surfaces take the
  /// household-first [_buildWallDetail] branch instead.
  Widget _buildStandardDetail(GatewayInfo? gateway) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
      children: [
        _DeviceHero(device: _device, onRename: _renameDevice),
        const SizedBox(height: 18),
        _Panel(
          title: 'DISPOSITIVO FÍSICO',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dónde está instalado el hardware. Esto no limita qué área controla cada canal.',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
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
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'ENDPOINTS / CANALES',
          child: Column(
            children: [
              for (
                var index = 0;
                index < _device.endpoints.length;
                index++
              ) ...[
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
                  onBindEntity:
                      asDeviceCommandRepository(widget.repository) == null
                      ? null
                      : (entityId) =>
                            _bindEntity(_device.endpoints[index], entityId),
                ),
                if (index != _device.endpoints.length - 1)
                  const Divider(height: 28, color: AppColors.border),
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
              if (gateway != null)
                _MetadataRow(label: 'Gateway', value: gateway.name),
            ],
          ),
        ),
        const SizedBox(height: 16),
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

class _GatewaysPage extends StatelessWidget {
  const _GatewaysPage({required this.snapshot});

  final DeviceInventorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Gateways'),
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        itemCount: snapshot.gateways.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final gateway = snapshot.gateways[index];
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
        },
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
