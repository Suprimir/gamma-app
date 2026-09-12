import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/app_colors.dart';

class LegacyDevicesPage extends StatefulWidget {
  const LegacyDevicesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<LegacyDevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<LegacyDevicesPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _locations = [];
  Map<String, Map<String, dynamic>> _statusByDevice = {};
  Map<String, dynamic>? _health;
  String? _selected;
  String? _error;
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  final _pending = <String, bool>{};
  final _actionErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = widget.api.events().listen((event) {
      final name = event['event'];
      if (name == 'device_state_changed' || name == 'status_updated') {
        _loadStatus();
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.catalog(),
        widget.api.status(refresh: refresh),
        widget.api.health(),
      ]);
      if (!mounted) return;
      _locations = (results[0]['locations'] as List)
          .cast<Map<String, dynamic>>();
      _applyStatus(results[1]);
      _health = results[2];
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Display name of a catalog location: prefer the canonical `display_name`
  /// (AreaStore name like "Baño"); fall back to the raw `name`/`id`.
  String _locationDisplay(Map<String, dynamic> loc) {
    final display = loc['display_name'];
    if (display is String && display.trim().isNotEmpty) return display;
    return formatLocationName(loc['name'].toString());
  }

  String _locationName(Map<String, dynamic> loc) {
    final name = loc['name'];
    if (name is String && name.isNotEmpty) return name;
    return loc['id']?.toString() ?? '';
  }

  Future<void> _loadStatus() async {
    try {
      final data = await widget.api.status();
      if (mounted) {
        setState(() => _applyStatus(data));
      }
    } catch (_) {}
  }

  void _applyStatus(Map<String, dynamic> data) {
    _statusByDevice = {
      for (final d in (data['devices'] as List).cast<Map<String, dynamic>>())
        '${d['location']}/${d['device_id']}': d,
    };
  }

  Future<void> _toggle(String location, String deviceId, bool enabled) async {
    final key = '$location/$deviceId';
    if (_pending.containsKey(key)) return;
    setState(() {
      _pending[key] = enabled;
      _actionErrors.remove(key);
    });
    try {
      final result = await widget.api.setPower(location, deviceId, enabled);
      final expected = enabled ? 'on' : 'off';
      final ok =
          result['success'] == true &&
          result['confirmed'] == true &&
          result['actual_value']?.toString() == expected;
      if (!mounted) return;
      if (ok) {
        setState(() {
          _statusByDevice[key] = {
            ..._statusByDevice[key] ?? {},
            'location': location,
            'device_id': deviceId,
            'estado': expected,
            'sync_state': 'CONFIRMED',
            'confirmed': true,
            'available': true,
          };
        });
      } else {
        setState(() {
          _actionErrors[key] =
              result['message']?.toString() ??
              'No se pudo confirmar el estado.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionErrors[key] = e.toString());
      }
    } finally {
      if (mounted) setState(() => _pending.remove(key));
    }
  }

  Map<String, dynamic> _merged(
    String location,
    Map<String, dynamic> catalogDevice,
  ) {
    final deviceId = (catalogDevice['id'] ?? catalogDevice['device_id'])
        .toString();
    final key = '$location/$deviceId';
    final current =
        _statusByDevice[key] ??
        {
          'estado': 'unknown',
          'sync_state': 'UNKNOWN',
          'confirmed': false,
          'available': null,
        };
    return {
      'location': location,
      'device_id': deviceId,
      'capabilities': catalogDevice['capabilities'] ?? const [],
      'display_name': catalogDevice['display_name'],
      ...current,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView(message: _error!, onRetry: () => _load());
    }
    return PopScope(
      // Sin ubicación seleccionada, el back del sistema fluye normal (sale
      // de la pestaña). Con una ubicación abierta, lo interceptamos y
      // volvemos al directorio — igual que el gesto de back en rutinas.
      canPop: _selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected != null) {
          setState(() => _selected = null);
        }
      },
      child: SafeArea(
        // Fondo explícito de la app: cuando LegacyDevicesPage se navega como
        // página empujada, el CustomScrollView no provee fondo propio y el
        // route puede heredar un fondo oscuro del theme del host (pantalla
        // negra con texto rojo en desktop/Pixel).
        child: ColoredBox(
          color: AppColors.bg,
          child: _selected == null
              ? _directoryView(context)
              : _locationView(context, _selected!),
        ),
      ),
    );
  }

  Widget _directoryView(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: HeaderRow(
              title: 'Dispositivos',
              onRefresh: () => _load(refresh: true),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Selecciona una ubicación para ver sus dispositivos.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
        ),
        if (_locations.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No hay ubicaciones configuradas.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final loc = _locations[i];
                final key = _locationName(loc);
                return _LocationCard(
                  name: _locationDisplay(loc),
                  onTap: () => setState(() => _selected = key),
                );
              }, childCount: _locations.length),
            ),
          ),
      ],
    );
  }

  Widget _locationView(BuildContext context, String location) {
    final loc = _locations
        .where((l) => _locationName(l) == location)
        .cast<Map<String, dynamic>?>();
    final devices = loc.isNotEmpty
        ? (loc.first!['devices'] as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    final displayName = loc.isNotEmpty
        ? _locationDisplay(loc.first!)
        : formatLocationName(location);
    // En móvil el botón "Ubicaciones" no se muestra: el back del sistema
    // (PopScope) ya vuelve al directorio. Solo queda "Actualizar", y el
    // header gana espacio para el contenido.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 20,
              compact ? 12 : 16,
              compact ? 16 : 20,
              0,
            ),
            child: Row(
              children: [
                if (!compact) ...[
                  ToolButton(
                    icon: Icons.arrow_back,
                    label: 'Ubicaciones',
                    onTap: () => setState(() => _selected = null),
                  ),
                  const SizedBox(width: 10),
                ],
                ToolButton(
                  icon: Icons.refresh,
                  label: 'Actualizar',
                  onTap: () => _load(refresh: true),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UBICACIÓN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.02,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${devices.length} ${devices.length == 1 ? 'dispositivo' : 'dispositivos'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _runtimeBadge(),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (devices.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: ColoredBox(
              color: AppColors.bg,
              child: Center(
                child: Text(
                  'No hay dispositivos en esta ubicación.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 14),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 215,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                // Altura fija por contenido (icono + nombre + toggle + error),
                // escalada con la fuente del teléfono. El aspectRatio depende
                // del ancho y en móvil deja celdas de ~133px → overflow.
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(240),
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final device = devices[i];
                final deviceId = (device['id'] ?? device['device_id'])
                    .toString();
                return _DeviceCard(
                  device: _merged(location, device),
                  health: _health,
                  pending: _pending['$location/$deviceId'],
                  actionError: _actionErrors['$location/$deviceId'],
                  onToggle: (enabled) => _toggle(location, deviceId, enabled),
                );
              }, childCount: devices.length),
            ),
          ),
      ],
    );
  }

  Widget _runtimeBadge() {
    final health = _health;
    if (health == null) return const SizedBox.shrink();
    final mode = health['device_mode']?.toString();
    final writes = health['writes_enabled'] == true;
    final (label, color) = switch (mode) {
      'simulation' => ('Simulación', AppColors.accentStrong),
      'local' when writes => ('Control local', AppColors.green),
      'local' => ('Solo lectura', AppColors.amber),
      _ => ('Control desactivado', AppColors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  locationIcon(name),
                  size: 27,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              Text(
                formatLocationName(name),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    required this.device,
    required this.health,
    required this.pending,
    required this.actionError,
    required this.onToggle,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic>? health;
  final bool? pending;
  final String? actionError;
  final ValueChanged<bool> onToggle;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    final syncState = widget.device['sync_state']?.toString() ?? 'UNKNOWN';
    final busy = widget.pending != null || syncState == 'PENDING';
    if (busy) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final meta = deviceTypeMeta(device['device_id'].toString());
    final displayName = _displayName(device['display_name']?.toString() ?? '');
    final syncState = device['sync_state']?.toString() ?? 'UNKNOWN';
    final state = device['estado']?.toString() ?? 'unknown';
    final unavailable =
        device['available'] == false || syncState == 'UNAVAILABLE';
    final reliable =
        device['confirmed'] == true &&
        syncState == 'CONFIRMED' &&
        !unavailable &&
        (state == 'on' || state == 'off');
    final capabilities =
        (device['capabilities'] as List?)?.map((e) => e.toString()).toSet() ??
        <String>{};
    final supportsPower =
        capabilities.contains('TURN_ON') && capabilities.contains('TURN_OFF');
    final health = widget.health;
    final writesBlocked =
        health == null ||
        health['device_mode']?.toString() == 'disabled' ||
        (health['device_mode']?.toString() == 'local' &&
            health['writes_enabled'] != true);
    final busy = widget.pending != null || syncState == 'PENDING';

    String label;
    if (busy) {
      label = widget.pending != null
          ? (widget.pending! ? 'Encendiendo…' : 'Apagando…')
          : 'Confirmando…';
    } else if (writesBlocked) {
      label = 'Solo lectura';
    } else if (unavailable) {
      label = 'No disponible';
    } else if (reliable) {
      label = state == 'on' ? 'Encendido' : 'Apagado';
    } else if (syncState == 'STALE') {
      label = 'Estado sin confirmar';
    } else {
      label = 'Sin estado';
    }
    final isOn = reliable && state == 'on' && !busy;
    final String? disabledReason;
    if (busy) {
      disabledReason = 'Confirmando...';
    } else if (writesBlocked) {
      disabledReason = 'Control en solo lectura — habilita el control local';
    } else if (unavailable) {
      disabledReason = 'No disponible';
    } else if (!reliable) {
      disabledReason = syncState == 'STALE'
          ? 'Estado sin confirmar — intenta actualizar'
          : 'Sin estado — intenta actualizar';
    } else {
      disabledReason = null;
    }
    final disabled = disabledReason != null;
    final error = widget.actionError;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOn ? AppColors.accentTintActive : AppColors.border,
        ),
        boxShadow: isOn
            ? [
                BoxShadow(
                  color: AppColors.accentTintHover,
                  blurRadius: 20,
                  offset: Offset(0, 6),
                  spreadRadius: 2,
                ),
              ]
            : const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(meta.icon, size: 27, color: AppColors.accent),
          ),
          const SizedBox(height: 10),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01,
            ),
          ),
          const Spacer(),
          if (supportsPower)
            _TogglePill(
              isOn: isOn,
              busy: busy,
              disabled: disabled,
              label: label,
              pulse: _pulse,
              onTap: () {
                if (disabled) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(disabledReason!)));
                  return;
                }
                widget.onToggle(state != 'on');
              },
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.red,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _displayName(String catalogName) {
    if (catalogName.isNotEmpty && !catalogName.contains('_')) {
      return catalogName;
    }
    return formatDeviceName(widget.device['device_id'].toString());
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.isOn,
    required this.busy,
    required this.disabled,
    required this.label,
    required this.pulse,
    required this.onTap,
  });

  final bool isOn;
  final bool busy;
  final bool disabled;
  final String label;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.52 : 1,
      // InkWell requires a Material ancestor; the _DeviceCard host is a
      // plain Container, so provide a transparent Material here (same fix
      // as ToolButton) to avoid "No Material widget found" debug errors
      // (yellow-underlined red text).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: double.infinity,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isOn ? AppColors.accent : AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              border: isOn ? null : Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) => Opacity(
                    opacity: busy ? 0.4 + 0.6 * pulse.value : 1,
                    child: Container(
                      width: 48,
                      height: 28,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isOn
                            ? Colors.white.withValues(alpha: 0.4)
                            : AppColors.borderStrong,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: isOn
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.border.withValues(alpha: 0.25),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isOn ? Colors.white : AppColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      name[0].toUpperCase() + name.substring(1);
}

IconData locationIcon(String location) {
  final name = location.toLowerCase();
  if (name.contains('cocina')) return Icons.soup_kitchen;
  if (name.contains('recamara')) return Icons.bed;
  if (name.contains('baño') || name.contains('bano')) return Icons.bathtub;
  if (name.contains('patio')) return Icons.park;
  return Icons.home;
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
