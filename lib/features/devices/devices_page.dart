import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../adaptive/adaptive_scope.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../areas/areas_page.dart';
import 'desktop_devices_page.dart';
import '../../data/device_inventory.dart';
import '../../data/http_device_inventory_repository.dart';
import 'legacy_devices_page.dart';
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
  late final AdaptiveFeatureController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AdaptiveFeatureController(widget.repository)
      ..addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  /// Surface-aware first load: the wall surface owns its own controller
  /// (WallDevicesPage), so this controller stays inert there to avoid a
  /// duplicate inventory fetch. Every other surface (or no scope at all)
  /// loads exactly once.
  void _maybeLoad() {
    final scope = AppAdaptiveScope.maybeOf(context);
    if (scope != null && scope.isWallPanel) return;
    if (_loaded) return;
    _loaded = true;
    _load();
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

  Future<void> _load() => _controller.loadDevices();

  Future<void> _discover() async {
    try {
      final ok = await _controller.discover();
      if (!ok || !mounted) return;
      final snapshot = _controller.snapshot!;
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
      return DesktopDevicesPage(controller: _controller);
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
    // El resumen de salud se basa en dispositivos de usuario, no en
    // infraestructura. unknown nunca equivale a "disponible": el health
    // local aún no se validó antes del smoke LAN.
    final userDevices = snapshot.userDevices;
    final onlineCount = userDevices
        .where((device) => device.health == DeviceHealthState.online)
        .length;
    final attentionCount = userDevices
        .where(
          (device) =>
              device.health == DeviceHealthState.offline ||
              device.health == DeviceHealthState.unreachable ||
              device.health == DeviceHealthState.authError,
        )
        .length;
    final unknownCount = userDevices
        .where((device) => device.health == DeviceHealthState.unknown)
        .length;
    final sleepingCount = userDevices
        .where((device) => device.health == DeviceHealthState.sleeping)
        .length;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _DevicesHeader(
                  discovering: _controller.discovering,
                  onDiscover: _discover,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Descubrimiento, asignación y estructura de la casa.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _PendingDevicesBanner(
                  count: snapshot.unassigned.length,
                  onTap: () => _open(
                    _PendingDevicesPage(
                      repository: widget.repository,
                      snapshot: snapshot,
                      onCanonicalDeviceChanged:
                          _controller.applyCanonicalDevice,
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 26, 20, 10),
                child: _SectionTitle(
                  title: 'ESPACIOS',
                  subtitle:
                      'Dispositivos físicos o endpoints asociados a cada área.',
                ),
              ),
            ),
            if (snapshot.areas.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Text('Todavía no hay espacios configurados.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 142,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final area = snapshot.areas[index];
                    final devices = snapshot.devicesInArea(area.id);
                    return _AreaCard(
                      area: area,
                      count: devices.length,
                      onTap: () => _open(
                        _AreaDevicesPage(
                          area: area,
                          snapshot: snapshot,
                          repository: widget.repository,
                          onCanonicalDeviceChanged:
                              _controller.applyCanonicalDevice,
                        ),
                      ),
                    );
                  }, childCount: snapshot.areas.length),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 10),
                child: _SectionTitle(
                  title: 'INFRAESTRUCTURA',
                  subtitle: 'Gateways y dispositivos que necesitan atención.',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(
                  children: [
                    _NavigationRow(
                      key: const Key('areas-row'),
                      icon: Icons.home_work_outlined,
                      title: 'Áreas',
                      subtitle:
                          'Gestiona espacios, nombres y organización de la casa.',
                      badge: snapshot.areas.length.toString(),
                      onTap: () =>
                          _open(AreasPage(repository: widget.repository)),
                    ),
                    const SizedBox(height: 10),
                    _NavigationRow(
                      key: const Key('gateways-row'),
                      icon: Icons.hub_outlined,
                      title: 'Gateways',
                      subtitle: snapshot.gateways.isEmpty
                          ? 'Ningún gateway registrado'
                          : '${snapshot.gateways.length} registrado${snapshot.gateways.length == 1 ? '' : 's'}',
                      badge: snapshot.gateways.length.toString(),
                      onTap: () => _open(_GatewaysPage(snapshot: snapshot)),
                    ),
                    const SizedBox(height: 10),
                    _NavigationRow(
                      key: const Key('offline-row'),
                      icon: Icons.cloud_off_outlined,
                      title: 'Desconectados',
                      subtitle: _healthSummaryLabel(
                        onlineCount: onlineCount,
                        attentionCount: attentionCount,
                        unknownCount: unknownCount,
                        sleepingCount: sleepingCount,
                        userCount: userDevices.length,
                      ),
                      badge: attentionCount.toString(),
                      badgeColor: attentionCount == 0
                          ? AppColors.green
                          : AppColors.amber,
                      onTap: () => _open(
                        _SimpleDeviceListPage(
                          title: 'Desconectados',
                          emptyMessage:
                              'No hay dispositivos que requieran revisión.',
                          devices: snapshot.devices
                              .where(
                                (device) =>
                                    device.health ==
                                        DeviceHealthState.offline ||
                                    device.health ==
                                        DeviceHealthState.unreachable ||
                                    device.health ==
                                        DeviceHealthState.authError,
                              )
                              .toList(),
                          snapshot: snapshot,
                          repository: widget.repository,
                          onCanonicalDeviceChanged:
                              _controller.applyCanonicalDevice,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _NavigationRow(
                      key: const Key('legacy-control-row'),
                      icon: Icons.tune,
                      title: 'Control actual',
                      subtitle:
                          'Abre la vista conectada al catálogo y estado de la API existente.',
                      badge: 'API',
                      badgeColor: AppColors.textDim,
                      onTap: () => _open(LegacyDevicesPage(api: widget.api)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicesHeader extends StatelessWidget {
  const _DevicesHeader({required this.discovering, required this.onDiscover});

  final bool discovering;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
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
        ToolButton(
          icon: discovering ? Icons.sync : Icons.radar,
          label: compact ? 'Buscar' : 'Buscar dispositivos',
          onTap: discovering ? () {} : onDiscover,
          filled: true,
        ),
      ],
    );
  }
}

class _PendingDevicesBanner extends StatelessWidget {
  const _PendingDevicesBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPending = count > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('pending-devices-banner'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: hasPending ? AppColors.accentTint : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasPending ? AppColors.accentTintActive : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasPending ? Colors.white : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  hasPending ? Icons.auto_awesome : Icons.check_circle_outline,
                  color: hasPending ? AppColors.accentStrong : AppColors.green,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPending
                          ? '$count dispositivo${count == 1 ? '' : 's'} nuevo${count == 1 ? '' : 's'}'
                          : 'Todo configurado',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasPending
                          ? 'Asígnalos a la casa para que Gamma pueda utilizarlos.'
                          : 'No hay dispositivos pendientes de asignación.',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                      ),
                    ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textDim,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
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
                    child: Icon(locationIcon(area.id), color: AppColors.accent),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.textFaint),
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
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.badgeColor = AppColors.accentStrong,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  final Color badgeColor;

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
              const Icon(Icons.chevron_right, color: AppColors.textFaint),
            ],
          ),
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

class _AreaDevicesPage extends StatelessWidget {
  const _AreaDevicesPage({
    required this.area,
    required this.snapshot,
    required this.repository,
    this.onCanonicalDeviceChanged,
  });

  final HomeArea area;
  final DeviceInventorySnapshot snapshot;
  final DeviceInventoryRepository repository;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  @override
  Widget build(BuildContext context) {
    return _DeviceListScaffold(
      title: area.name,
      subtitle: 'Dispositivos físicos y endpoints relacionados con esta área.',
      devices: snapshot.devicesInArea(area.id),
      snapshot: snapshot,
      repository: repository,
      emptyMessage: 'No hay dispositivos asignados a ${area.name}.',
      areaId: area.id,
      onCanonicalDeviceChanged: onCanonicalDeviceChanged,
    );
  }
}

class _SimpleDeviceListPage extends StatelessWidget {
  const _SimpleDeviceListPage({
    required this.title,
    required this.emptyMessage,
    required this.devices,
    required this.snapshot,
    required this.repository,
    this.onCanonicalDeviceChanged,
  });

  final String title;
  final String emptyMessage;
  final List<PhysicalDevice> devices;
  final DeviceInventorySnapshot snapshot;
  final DeviceInventoryRepository repository;
  final ValueChanged<PhysicalDevice>? onCanonicalDeviceChanged;

  @override
  Widget build(BuildContext context) {
    return _DeviceListScaffold(
      title: title,
      subtitle: 'Vista de diagnóstico del inventario de Gamma.',
      devices: devices,
      snapshot: snapshot,
      repository: repository,
      emptyMessage: emptyMessage,
      offlineOnly: title == 'Desconectados',
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
    this.areaId,
    this.pendingOnly = false,
    this.offlineOnly = false,
    this.onCanonicalDeviceChanged,
  });

  final String title;
  final String subtitle;
  final List<PhysicalDevice> devices;
  final DeviceInventorySnapshot snapshot;
  final DeviceInventoryRepository repository;
  final String emptyMessage;
  final String? areaId;
  final bool pendingOnly;
  final bool offlineOnly;
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
    } else if (widget.areaId != null) {
      refreshed = latest.devicesInArea(widget.areaId!);
    } else if (widget.offlineOnly) {
      refreshed = latest.devices
          .where((device) => device.health == DeviceHealthState.offline)
          .toList();
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
                child: Icon(
                  deviceKindMeta(device.kind).icon,
                  color: AppColors.accent,
                ),
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
              const Icon(Icons.chevron_right, color: AppColors.textFaint),
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
    if (_identifying) return;
    setState(() => _identifying = true);
    try {
      await widget.repository.identify(_device.id, endpointId: endpointId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            endpointId == null
                ? 'Se envió la orden de identificación al dispositivo.'
                : 'Se envió la orden de identificación a $endpointId.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _identifying = false);
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
                      : null,
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
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
                  onIdentify: widget.repository.supportsIdentify
                      ? () => _identify(endpointId: _device.endpoints[index].id)
                      : null,
                  onRename: () => _renameEndpoint(_device.endpoints[index]),
                  onRoleChanged: widget.repository.supportsSemanticRole
                      ? (role) =>
                            _setEndpointRole(_device.endpoints[index], role)
                      : null,
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
        if (widget.repository.supportsIdentify) ...[
          OutlinedButton.icon(
            onPressed: _identifying ? null : () => _identify(),
            icon: _identifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(
              _identifying ? 'Identificando…' : 'Identificar dispositivo',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'En el backend real, “Identificar” podrá parpadear una luz, activar un LED o escuchar actividad del endpoint según el adaptador.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: null,
            icon: Icon(Icons.wifi_tethering),
            label: Text('Identificar dispositivo'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Disponible después de validar el control local.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
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
                        : null,
                    icon: const Icon(Icons.copy_all_outlined, size: 17),
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
    final meta = deviceKindMeta(device.kind);
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
                child: Icon(meta.icon, size: 30, color: AppColors.accent),
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
    final meta = deviceKindMeta(endpoint.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(meta.icon, size: 20, color: AppColors.accent),
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
              onPressed: busy ? null : onRename,
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
                        icon: const Icon(
                          Icons.edit_outlined,
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
  });

  final DeviceEndpoint endpoint;
  final List<HomeArea> areas;
  final bool busy;
  final ValueChanged<String?> onChanged;

  /// Null cuando el repositorio no soporta identify (F1: HTTP inert).
  final VoidCallback? onIdentify;

  /// F2-C rename affordance; null hides it.
  final VoidCallback? onRename;

  /// F2-D closure: user semantic-role override (null = clear). Null hides
  /// the role selector (e.g. unsupported repository).
  final ValueChanged<String?>? onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final meta = deviceKindMeta(endpoint.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(meta.icon, size: 20, color: AppColors.accent),
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
                onPressed: busy ? null : onRename,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
              ),
            if (onIdentify != null)
              TextButton.icon(
                onPressed: busy ? null : onIdentify,
                icon: const Icon(Icons.wifi_tethering, size: 16),
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
              onPressed: null,
              icon: const Icon(Icons.link, size: 17),
              label: const Text('Vincular entidad'),
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Disponible cuando el backend publique el catálogo de entidades.',
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
    return Column(
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
    return Column(
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
          initialValue: _semanticRoleOptions.containsKey(current) ? current : null,
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
                  child: const Icon(
                    Icons.hub_outlined,
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

/// Resumen honesto de salud de los dispositivos de usuario.
///
/// Invariante central: un dispositivo solo cuenta como "disponible" si su
/// health es explícitamente ONLINE. Desconocido nunca equivale a disponible;
/// sleeping nunca equivale a online; offline/unreachable/authError cuentan
/// como "requieren revisión". "Todos los dispositivos están disponibles"
/// solo puede aparecer si TODOS los dispositivos de usuario están online.
String _healthSummaryLabel({
  required int onlineCount,
  required int attentionCount,
  required int unknownCount,
  required int sleepingCount,
  required int userCount,
}) {
  if (attentionCount > 0) {
    return '$attentionCount requieren revisión';
  }

  if (unknownCount > 0 && sleepingCount > 0) {
    final parts = <String>[];
    if (onlineCount > 0) parts.add('$onlineCount disponibles');
    parts.add('$unknownCount con estado local aún no validado');
    parts.add('$sleepingCount en reposo');
    return parts.join(' · ');
  }

  if (unknownCount > 0) {
    return unknownCount == userCount
        ? 'Estado local aún no validado'
        : '$unknownCount con estado local aún no validado';
  }

  if (sleepingCount > 0) {
    return sleepingCount == userCount
        ? '$sleepingCount dispositivos en reposo'
        : '$sleepingCount en reposo · $onlineCount disponibles';
  }

  if (onlineCount == userCount) {
    return 'Todos los dispositivos están disponibles';
  }
  // Fail-safe: nunca afirmar disponibilidad sin evidencia explícita online.
  return '$onlineCount disponibles';
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
    'luz' || 'foco' => (icon: Icons.lightbulb, label: 'Luz'),
    'enchufe' => (icon: Icons.power, label: 'Enchufe'),
    'ventilador' => (icon: Icons.air, label: 'Ventilador'),
    'sensor' => (icon: Icons.thermostat, label: 'Sensor'),
    'camara' => (icon: Icons.videocam, label: 'Cámara'),
    _ => (icon: Icons.devices, label: 'Dispositivo'),
  };
}

String formatDeviceName(String deviceId) {
  final parts = deviceId.split('_');
  final meta = deviceTypeMeta(deviceId);
  final number = parts.length > 1 ? parts[1] : '';
  return number.isEmpty ? meta.label : '${meta.label} $number';
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
