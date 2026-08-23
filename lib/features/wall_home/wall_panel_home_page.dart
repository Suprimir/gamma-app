import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../adaptive/adaptive_scope.dart';
import '../dashboard/dashboard_page.dart';
import '../../data/device_inventory.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../ui/shared_widgets.dart';
import 'wall_area_overview_page.dart';
import '../devices/wall_devices_page.dart';
import 'wall_home_clock.dart';
import 'wall_home_projection.dart';

/// Surface-aware Home destination.
///
/// Only the effective wall panel experience renders the dedicated Wall Home;
/// mobile and desktop keep the existing voice [DashboardPage]. Compact wall
/// panels never reach here (AppShell already falls back to mobile).
class AdaptiveHomePage extends StatelessWidget {
  const AdaptiveHomePage({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final scope = AppAdaptiveScope.of(context);
    if (scope.isWallPanel) {
      return WallPanelHomePage(api: api);
    }
    return DashboardPage(api: api);
  }
}

/// Dedicated room-first Home for the wall panel surface.
///
/// Loads canonical inventory through [DeviceInventoryRepository] and renders
/// a pure [WallHomeSnapshot] projection. Navigation-only: no physical
/// controls, no power state, no provider vocabulary.
class WallPanelHomePage extends StatefulWidget {
  WallPanelHomePage({
    super.key,
    required this.api,
    DeviceInventoryRepository? repository,
  }) : repository = repository ?? HttpDeviceInventoryRepository(api);

  final ApiClient api;
  final DeviceInventoryRepository repository;

  @override
  State<WallPanelHomePage> createState() => _WallPanelHomePageState();
}

class _WallPanelHomePageState extends State<WallPanelHomePage> {
  DeviceInventorySnapshot? _snapshot;
  WallHomeSnapshot? _wall;
  Object? _error;
  bool _loading = true;

  /// Non-destructive refresh failure shown while a previous snapshot stays.
  Object? _refreshError;

  /// Set on the first active load; offstage pages stay inert until activated.
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted && TickerMode.valuesOf(context).enabled) {
      _loadStarted = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _refreshError = null;
    });
    try {
      final snapshot = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _wall = projectWallHome(snapshot);
      });
    } catch (error) {
      if (!mounted) return;
      if (_wall == null) {
        setState(() => _error = error);
      } else {
        // Refresh failed after a good snapshot: keep the snapshot and surface
        // a non-destructive error. Never fall back to mocks.
        setState(() => _refreshError = error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _wall == null) {
      return const _WallHomeScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _wall == null) {
      return _WallHomeScaffold(
        child: MessageView(
          message: 'No se pudo cargar la casa',
          onRetry: _load,
        ),
      );
    }
    return _WallHomeScaffold(
      child: _WallHomeBody(
        snapshot: _snapshot!,
        wall: _wall!,
        refreshError: _refreshError,
        onRefresh: _load,
        onOpenArea: _openArea,
        onOpenAttention: _openAttention,
      ),
    );
  }

  void _openArea(WallAreaSummary area) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WallAreaOverviewPage(
          snapshot: snapshot,
          areaId: area.areaId,
          areaName: area.name,
        ),
      ),
    );
  }

  void _openAttention() {
    // Configuration attention routes to the touch-first wall Devices flow,
    // which surfaces the pending-device configuration.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WallDevicesPage(api: widget.api, repository: widget.repository),
      ),
    );
  }
}

/// Stable outer shell for every wall home state: same header and content
/// width regardless of loading/error/data, so transitions are calm.
class _WallHomeScaffold extends StatelessWidget {
  const _WallHomeScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: child,
        ),
      ),
    );
  }
}

class _WallHomeBody extends StatelessWidget {
  const _WallHomeBody({
    required this.snapshot,
    required this.wall,
    required this.onOpenArea,
    required this.onOpenAttention,
    this.refreshError,
    this.onRefresh,
  });

  final DeviceInventorySnapshot snapshot;
  final WallHomeSnapshot wall;
  final ValueChanged<WallAreaSummary> onOpenArea;
  final VoidCallback onOpenAttention;

  /// Non-destructive refresh failure shown above the retained snapshot.
  final Object? refreshError;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await onRefresh?.call();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 120),
        children: [
          const WallHomeClock(),
          const SizedBox(height: 20),
          const Text(
            'Mi casa',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          if (refreshError != null) ...[
            const SizedBox(height: 12),
            _RefreshErrorBanner(onRetry: onRefresh),
          ],
          if (wall.attentionCount > 0) ...[
            const SizedBox(height: 12),
            _WallAttentionCard(
              attentionCount: wall.attentionCount,
              onTap: onOpenAttention,
            ),
          ],
          const SizedBox(height: 16),
          _WallAreaGrid(
            areas: wall.areas,
            onOpenArea: onOpenArea,
            onOpenDevices: onOpenAttention,
          ),
        ],
      ),
    );
  }
}

/// Non-destructive refresh failure: the previous snapshot stays visible.
class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.sync_problem, color: AppColors.textDim),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No se pudo actualizar',
                style: TextStyle(fontSize: 15, color: AppColors.textDim),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Actionable configuration attention, household language only.
class _WallAttentionCard extends StatelessWidget {
  const _WallAttentionCard({required this.attentionCount, required this.onTap});

  final int attentionCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          alignment: Alignment.centerLeft,
          backgroundColor: AppColors.surfaceRaised,
          foregroundColor: AppColors.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.amber),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.amber),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Necesita atención',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(
              _attentionLabel(attentionCount),
              style: const TextStyle(fontSize: 16, color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

String _attentionLabel(int count) {
  if (count == 1) return '1 dispositivo por configurar';
  return '$count dispositivos por configurar';
}

/// Room-first grid with large touch tiles. Adaptive max extent, wall-only
/// density: medium -> usually 2 columns, expanded -> 3, large -> 3-4 with the
/// max card extent capping stretch on very wide displays.
class _WallAreaGrid extends StatelessWidget {
  const _WallAreaGrid({
    required this.areas,
    required this.onOpenArea,
    required this.onOpenDevices,
  });

  final List<WallAreaSummary> areas;
  final ValueChanged<WallAreaSummary> onOpenArea;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    if (areas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aún no hay habitaciones configuradas',
              style: TextStyle(fontSize: 17, color: AppColors.textDim),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpenDevices,
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Ver dispositivos'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 150,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
      ),
      itemCount: areas.length,
      itemBuilder: (context, index) {
        final area = areas[index];
        return _WallAreaCard(
          key: ValueKey('wall-area-${area.areaId}'),
          area: area,
          onTap: () => onOpenArea(area),
        );
      },
    );
  }
}

class _WallAreaCard extends StatelessWidget {
  const _WallAreaCard({super.key, required this.area, required this.onTap});

  final WallAreaSummary area;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The semantic label is merged onto the button; the Texts below carry the
    // visible wording and fold into one readable node via MergeSemantics.
    return MergeSemantics(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(24),
          alignment: Alignment.centerLeft,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              area.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${area.controlCount} '
              '${area.controlCount == 1 ? 'control' : 'controles'}',
              style: const TextStyle(fontSize: 16, color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
