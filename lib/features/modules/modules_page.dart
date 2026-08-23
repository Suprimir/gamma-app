import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/app_colors.dart';

class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _modules = [];
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
      if (event['event'] == 'module_changed') _load();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final modules = await widget.api.modules();
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(String name, bool enabled) async {
    if (_pending.containsKey(name)) return;
    // Optimistic: flip in place while the request runs.
    setState(() {
      _pending[name] = enabled;
      _actionErrors.remove(name);
      for (final m in _modules) {
        if (m['name'] == name) m['enabled'] = enabled;
      }
    });
    try {
      await widget.api.setModule(name, enabled);
      if (!mounted) return;
      setState(() {
        // Confirm with server truth (in case toggle is denied).
        for (final m in _modules) {
          if (m['name'] == name) {
            m['enabled'] = enabled;
            m['state'] = enabled ? 'enabled' : 'disabled';
          }
        }
        _pending.remove(name);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Revert on failure.
        for (final m in _modules) {
          if (m['name'] == name) m['enabled'] = !enabled;
        }
        _pending.remove(name);
        _actionErrors[name] = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView(message: _error!, onRetry: () => _load(refresh: true));
    }
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: HeaderRow(
                title: 'Módulos',
                onRefresh: () => _load(refresh: true),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Activa o desactiva las capacidades de GAMMA.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
          ),
          if (_modules.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No hay módulos disponibles.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  // Altura por contenido (no por ancho): escala con el
                  // tamaño de fuente del teléfono para evitar overflow.
                  mainAxisExtent: MediaQuery.textScalerOf(
                    context,
                  ).scale(MediaQuery.sizeOf(context).width < 600 ? 320 : 300),
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final m = _modules[i];
                  return _ModuleCard(
                    module: m,
                    pending: _pending.containsKey(m['name']),
                    actionError: _actionErrors[m['name']],
                    onToggle: (enabled) =>
                        _toggle(m['name'].toString(), enabled),
                  );
                }, childCount: _modules.length),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatefulWidget {
  const _ModuleCard({
    required this.module,
    required this.pending,
    required this.actionError,
    required this.onToggle,
  });

  final Map<String, dynamic> module;
  final bool pending;
  final String? actionError;
  final ValueChanged<bool> onToggle;

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final name = m['name'].toString();
    final displayName = m['display_name'].toString();
    final description = m['description']?.toString() ?? '';
    final enabled = m['enabled'] == true;
    final required = m['required'] == true;
    final busy = widget.pending;
    final error = widget.actionError;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 44 : 52,
                height: compact ? 44 : 52,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  moduleIcon(name),
                  size: compact ? 23 : 27,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              _ModuleSwitch(
                enabled: enabled,
                busy: busy,
                disabled: required,
                pulse: _pulse,
                onTap: (required || busy)
                    ? null
                    : () => widget.onToggle(!enabled),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12.5 : 13,
              height: 1.4,
              color: AppColors.textDim,
            ),
          ),
          const Spacer(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.red,
                  height: 1.3,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pill(
                enabled ? 'Activo' : 'Inactivo',
                enabled ? AppColors.green : AppColors.textDim,
              ),
              if (required) _pill('Necesario', AppColors.red),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ModuleSwitch extends StatelessWidget {
  const _ModuleSwitch({
    required this.enabled,
    required this.busy,
    required this.disabled,
    required this.pulse,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final bool disabled;
  final Animation<double> pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dimmed = disabled || (busy && !enabled);
    return Opacity(
      opacity: dimmed ? 0.52 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) => Opacity(
              opacity: busy ? 0.4 + 0.6 * pulse.value : 1,
              child: Container(
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: enabled ? AppColors.accent : AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: enabled
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
        ),
      ),
    );
  }
}

IconData moduleIcon(String name) {
  final key = name.toLowerCase();
  if (key.contains('camera')) return Icons.videocam;
  if (key.contains('spotify') || key.contains('media')) return Icons.music_note;
  if (key.contains('news')) return Icons.newspaper;
  if (key.contains('voice')) return Icons.mic;
  if (key.contains('domotic')) return Icons.home;
  return Icons.extension;
}
