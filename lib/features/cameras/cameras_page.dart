import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import 'cameras_player_page.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/app_colors.dart';

class CamerasPage extends StatefulWidget {
  const CamerasPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<CamerasPage> createState() => _CamerasPageState();
}

class _CamerasPageState extends State<CamerasPage> {
  List<Map<String, dynamic>> _cameras = [];
  Map<String, dynamic> _statuses = {};
  List<Map<String, dynamic>> _events = [];
  bool _enabled = true;
  bool _eventsUnavailable = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.cameraModule();
      if (!mounted) return;
      setState(() {
        _cameras = data.cameras;
        _enabled = data.enabled;
      });
      await _loadStatusAndEvents();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStatusAndEvents() async {
    Map<String, dynamic> statuses = {};
    var eventsUnavailable = false;
    List<Map<String, dynamic>> events = [];
    try {
      final status = await widget.api.cameraStatus();
      statuses = {
        for (final s
            in (status['statuses'] as List).cast<Map<String, dynamic>>())
          s['camera_id'].toString(): s,
      };
    } on ApiException {
      // Módulo no disponible (p. ej. simulación): tarjetas «Sin estado».
    }
    try {
      events = await widget.api.cameraEvents();
    } on ApiException {
      eventsUnavailable = true;
    }
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _events = events;
        _eventsUnavailable = eventsUnavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView(message: _error!, onRetry: _load);
    }
    if (!_enabled) {
      return const SafeArea(
        child: Center(child: Text('El módulo de cámaras está desactivado.')),
      );
    }
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: HeaderRow(title: 'Cámaras', onRefresh: _load),
            ),
          ),
          if (_cameras.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No hay cámaras configuradas en el catálogo.'),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 320,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _CameraCard(
                    camera: _cameras[i],
                    status: _statuses[_cameras[i]['camera_id']?.toString()],
                    api: widget.api,
                  ),
                  childCount: _cameras.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _EventsSection(
                  events: _events,
                  unavailable: _eventsUnavailable,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.camera,
    required this.status,
    required this.api,
  });

  final Map<String, dynamic> camera;
  final Map<String, dynamic>? status;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final cameraId = camera['camera_id'].toString();
    final (stateLabel, stateColor) = cameraState(status);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: const Color(0xFF141A24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    api.cameraSnapshotUrl(cameraId),
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stack) => const Center(
                      child: Text(
                        'Snapshot no disponible',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC141A24),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        stateLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: stateColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  camera['name'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  camera['location']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  height: 56,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CameraPlayerPage(api: api, camera: camera),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Ver en vivo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventsSection extends StatelessWidget {
  const _EventsSection({required this.events, required this.unavailable});

  final List<Map<String, dynamic>> events;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'EVENTOS RECIENTES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: AppColors.textDim,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: unavailable
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'El historial no está disponible.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                )
              : events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No hay eventos de movimiento registrados.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                )
              : Column(
                  children: [
                    for (final event in events) _EventRow(event: event),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final cameraId =
        event['camera_id']?.toString() ??
        'Canal ${event['channel']?.toString() ?? '?'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$cameraId · ${event['event_type']?.toString() ?? '?'}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            formatEventTime(event['occurred_at']?.toString() ?? ''),
            style: const TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

(String, Color) cameraState(Map<String, dynamic>? status) {
  final online = status?['online'];
  if (online == true) {
    return ('En línea', AppColors.green);
  }
  if (online == false) {
    return ('Fuera de línea', AppColors.textDim);
  }
  return ('Sin estado', AppColors.textDim);
}

String formatEventTime(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${parsed.year}-${pad(parsed.month)}-${pad(parsed.day)} '
      '${pad(parsed.hour)}:${pad(parsed.minute)}';
}
