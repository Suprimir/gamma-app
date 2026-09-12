import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/shared_widgets.dart';

/// Lista compacta de módulos para integrarla dentro de Ajustes.
class ModulesSection extends StatefulWidget {
  const ModulesSection({
    super.key,
    required this.api,
    this.onConfigure,
    this.configuredModules = const {},
  });

  final ApiClient api;

  /// Called with the module name when its gear is tapped. A gear is rendered
  /// only for names listed in [configuredModules]: modules without a
  /// configuration screen (e.g. `domotics`) never show one.
  final void Function(String module)? onConfigure;

  /// Module names that expose a configuration screen. Only meaningful
  /// together with [onConfigure].
  final Set<String> configuredModules;

  @override
  State<ModulesSection> createState() => _ModulesSectionState();
}

class _ModulesSectionState extends State<ModulesSection> {
  List<Map<String, dynamic>> _modules = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  final _pending = <String>{};
  final _actionErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = widget.api.events().listen((event) {
      if (event['event'] == 'module_changed') {
        _load(showSpinner: false);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
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
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!showSpinner && _modules.isNotEmpty) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String name, bool enabled) async {
    if (_pending.contains(name)) return;

    final previous = _moduleEnabled(name);
    setState(() {
      _pending.add(name);
      _actionErrors.remove(name);
      _setLocalState(name, enabled);
    });

    try {
      final result = await widget.api.setModule(name, enabled);
      if (!mounted) return;

      final confirmed = result['enabled'] is bool
          ? result['enabled'] as bool
          : enabled;
      final message = result['message']?.toString().trim() ?? '';

      setState(() {
        _setLocalState(name, confirmed);
        _pending.remove(name);
        if (confirmed != enabled) {
          _actionErrors[name] = message.isNotEmpty
              ? message
              : 'El servidor no aplicó el cambio solicitado.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _setLocalState(name, previous);
        _pending.remove(name);
        _actionErrors[name] = e.toString();
      });
    }
  }

  bool _moduleEnabled(String name) {
    for (final module in _modules) {
      if (module['name']?.toString() == name) return module['enabled'] == true;
    }
    return false;
  }

  void _setLocalState(String name, bool enabled) {
    for (final module in _modules) {
      if (module['name']?.toString() == name) {
        module['enabled'] = enabled;
        module['state'] = enabled ? 'enabled' : 'disabled';
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: MessageView(message: _error!, onRetry: _load),
      );
    }
    if (_modules.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No hay módulos disponibles.',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < _modules.length; i++) ...[
          _ModuleRow(
            module: _modules[i],
            pending: _pending.contains(_modules[i]['name']?.toString()),
            actionError: _actionErrors[_modules[i]['name']?.toString()],
            onToggle: (enabled) =>
                _toggle(_modules[i]['name'].toString(), enabled),
            onConfigure:
                widget.onConfigure != null &&
                    widget.configuredModules.contains(
                      _modules[i]['name']?.toString(),
                    )
                ? () => widget.onConfigure!(_modules[i]['name'].toString())
                : null,
          ),
          if (i < _modules.length - 1)
            const Divider(height: 1, color: AppColors.border),
        ],
      ],
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.module,
    required this.pending,
    required this.actionError,
    required this.onToggle,
    this.onConfigure,
  });

  final Map<String, dynamic> module;
  final bool pending;
  final String? actionError;
  final ValueChanged<bool> onToggle;

  /// Gear action; null hides the gear (module without a config screen).
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final name = module['name']?.toString() ?? '';
    final displayName = module['display_name']?.toString().trim();
    final description = module['description']?.toString().trim() ?? '';
    final enabled = module['enabled'] == true;
    final required = module['required'] == true;
    final title = displayName == null || displayName.isEmpty
        ? name
        : displayName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(moduleIcon(name), size: 21, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.01,
                        ),
                      ),
                    ),
                    if (required) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '· necesario',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
                if (actionError != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    actionError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onConfigure != null) ...[
            IconButton(
              key: ValueKey('module-configure-$name'),
              tooltip: 'Configurar',
              visualDensity: VisualDensity.compact,
              onPressed: pending ? null : onConfigure,
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
            const SizedBox(width: 2),
          ],
          Stack(
            alignment: Alignment.center,
            children: [
              Switch.adaptive(
                key: ValueKey('module-switch-$name'),
                value: enabled,
                onChanged: required || pending ? null : onToggle,
              ),
              if (pending)
                const IgnorePointer(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
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
