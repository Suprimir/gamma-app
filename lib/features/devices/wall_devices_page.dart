import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../data/device_inventory.dart';
import 'devices_page.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../ui/shared_widgets.dart';
import '../wall_home/wall_areas_page.dart';

/// Touch-first Devices management for the wall panel surface (F3-C Phase 5).
///
/// Owns its own [AdaptiveFeatureController] (same contract as [DevicesPage])
/// and renders large, fully tappable device cards in canonical snapshot order.
/// No search: the wall panel keeps this surface minimal (search is
/// desktop-only). Tapping a card opens the household-first wall detail
/// (presentation: wall) — primary vocabulary only, technical metadata
/// collapsed under 'Información técnica'. No physical ON/OFF anywhere.
class WallDevicesPage extends StatefulWidget {
  WallDevicesPage({
    super.key,
    required this.api,
    DeviceInventoryRepository? repository,
  }) : repository = repository ?? HttpDeviceInventoryRepository(api);

  final ApiClient api;
  final DeviceInventoryRepository repository;

  @override
  State<WallDevicesPage> createState() => _WallDevicesPageState();
}

class _WallDevicesPageState extends State<WallDevicesPage> {
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
          onCanonicalDeviceChanged: _controller.applyCanonicalDevice,
        ),
      ),
    );
    await _controller.loadDevices();
  }

  Future<void> _openAreas() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WallAreasPage(api: widget.api, repository: widget.repository),
      ),
    );
    // Converge nombres de áreas en las tarjetas al volver de Habitaciones.
    await _controller.loadDevices();
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
        final devices = snapshot.userDevices;
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: RefreshIndicator(
                onRefresh: _controller.loadDevices,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
                  children: [
                    _WallDevicesHeader(count: devices.length),
                    const SizedBox(height: 18),
                    if (devices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          'Todavía no hay dispositivos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
                          onTap: () => _openDevice(device),
                        ),
                        const SizedBox(height: 14),
                      ],
                    const SizedBox(height: 14),
                    _WallAreasNavCard(onTap: _openAreas),
                  ],
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
  const _WallDevicesHeader({required this.count});

  final int count;

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
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

/// Large navigation card to the touch-first Habitaciones management page.
class _WallAreasNavCard extends StatelessWidget {
  const _WallAreasNavCard({required this.onTap});

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
                child: const Icon(
                  Icons.home_work_outlined,
                  size: 28,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Habitaciones',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gestiona los nombres y la organización de la casa.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 14),
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

/// Large, fully tappable wall device card. Human vocabulary only: name, room,
/// configuration status, control count and plain-language health.
class _WallDeviceCard extends StatelessWidget {
  const _WallDeviceCard({
    super.key,
    required this.device,
    required this.roomName,
    required this.healthLabel,
    required this.onTap,
  });

  final PhysicalDevice device;
  final String roomName;
  final String? healthLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = deviceKindMeta(device.kind);
    final controls = device.endpoints.length;
    final healthColor = _wallHealthColor(device.health);
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
                        Flexible(
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

/// Household-first wall detail: [DeviceDetailView] rendered in the [wall]
/// presentation — display name, 'Nombre', 'Habitación física', 'Controles',
/// with technical metadata collapsed under 'Información técnica'.
class _WallDeviceDetailPage extends StatelessWidget {
  const _WallDeviceDetailPage({
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
        presentation: DeviceDetailPresentation.wall,
      ),
    );
  }
}

String _roomName(List<HomeArea> areas, String? physicalAreaId) {
  if (physicalAreaId == null) return 'Sin área';
  for (final area in areas) {
    if (area.id == physicalAreaId) return area.name;
  }
  return 'Sin área';
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
