import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../adaptive/adaptive_layout.dart';
import '../../adaptive/adaptive_scope.dart';
import '../../adaptive/adaptive_surface_preferences.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../modules/modules_section.dart';
import '../../ui/shared_widgets.dart';
import 'cameras_module_screen.dart';
import 'llm_module_screen.dart';
import 'module_config_widgets.dart';
import 'news_module_screen.dart';
import 'spotify_module_screen.dart';
import 'tts_preview_player.dart';

/// System-only Settings page. Module-scoped configuration lives in its own
/// screens, reached from the gear next to each module switch in Módulos.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    this.surfaceModeController,
    this.ttsPreviewPlayer,
  });

  final ApiClient api;
  final AdaptiveSurfaceModeController? surfaceModeController;

  /// Injectable WAV player for the voice preview. Tests pass a fake so the
  /// fetch/synthesis path is exercised without native media playback; when
  /// null the page owns a [MediaKitTtsPreviewPlayer] and disposes it.
  final TtsPreviewPlayer? ttsPreviewPlayer;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  String? _error;

  // Voz del asistente
  List<Map<String, dynamic>> _edgeVoices = [];
  String? _selectedLang;
  String? _selectedVoice;
  bool _savingVoice = false;
  bool _previewingVoice = false;
  String _voiceStatus = '';
  bool _voiceStatusOk = true;

  // Sistema
  Map<String, dynamic>? _systemHealth;
  String? _systemError;
  bool _systemLoading = true;

  late AdaptiveSurfaceModeController _surfaceModeController;
  bool _ownsSurfaceModeController = false;
  bool _surfaceModeControllerResolved = false;

  late final TtsPreviewPlayer _ttsPlayer =
      widget.ttsPreviewPlayer ?? MediaKitTtsPreviewPlayer();
  bool get _ownsTtsPlayer => widget.ttsPreviewPlayer == null;

  /// Modules that have their own configuration screen (and therefore a gear).
  static const _configurableModules = <String>{
    'spotify',
    'news',
    'llm',
    'cameras',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve the controller once: explicit param → adaptive scope → own.
    if (!_surfaceModeControllerResolved) {
      _surfaceModeControllerResolved = true;
      final fromScope = AppAdaptiveScope.maybeOf(context)?.controller;
      _surfaceModeController =
          widget.surfaceModeController ??
          fromScope ??
          AdaptiveSurfaceModeController();
      _ownsSurfaceModeController =
          widget.surfaceModeController == null && fromScope == null;
      if (_ownsSurfaceModeController) _surfaceModeController.load();
    }
  }

  @override
  void dispose() {
    if (_ownsSurfaceModeController) _surfaceModeController.dispose();
    if (_ownsTtsPlayer) _ttsPlayer.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _systemLoading = true;
        _systemError = null;
      });
    }
    // Runs independently: a health failure must never blank the page.
    final system = _loadSystem();
    try {
      final results = await Future.wait([
        widget.api.ttsSettings(),
        widget.api.ttsVoices(),
      ]);
      if (!mounted) return;
      final settings = results[0];
      final voices = results[1];
      setState(() {
        _edgeVoices =
            (voices['edge'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final current = settings['edge_voice']?.toString() ?? '';
        final currentVoice = _edgeVoices
            .where((v) => v['id']?.toString() == current)
            .firstOrNull;
        final selectedVoice = currentVoice ?? _edgeVoices.firstOrNull;
        _selectedLang = (selectedVoice?['locale']?.toString() ?? 'es')
            .split('-')
            .first;
        _selectedVoice = selectedVoice?['id']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
    await system;
  }

  /// Reads `/api/v1/health` for the compact Sistema card. Never throws: the
  /// card owns its error state and the rest of the page stays untouched.
  Future<void> _loadSystem() async {
    try {
      final health = await widget.api.health();
      if (!mounted) return;
      setState(() {
        _systemHealth = health;
        _systemError = null;
        _systemLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _systemError = e.toString();
        _systemLoading = false;
      });
    }
  }

  void _retrySystem() {
    setState(() {
      _systemLoading = true;
      _systemError = null;
    });
    _loadSystem();
  }

  /// Opens the configuration screen of a module. Modules outside
  /// [_configurableModules] never reach this (no gear is rendered).
  void _openModuleConfig(String module) {
    final Widget? screen = switch (module) {
      'spotify' => SpotifyModuleScreen(api: widget.api),
      'news' => NewsModuleScreen(api: widget.api),
      'llm' => LlmModuleScreen(api: widget.api),
      'cameras' => CamerasModuleScreen(api: widget.api),
      _ => null,
    };
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  // --- Voz del asistente ---------------------------------------------------

  static const _langNames = {
    'es': 'Español',
    'en': 'English',
    'pt': 'Portugués',
    'fr': 'Francés',
    'de': 'Deutsch',
    'it': 'Italiano',
    'ja': 'Japonés',
    'ko': 'Coreano',
    'zh': 'Chino',
    'ar': 'Árabe',
    'hi': 'Hindi',
    'ru': 'Ruso',
  };

  List<String> _sortedLangs() {
    final langs = _edgeVoices
        .map((v) => (v['locale']?.toString() ?? 'unknown').split('-').first)
        .toSet();
    final sorted = langs.toList()
      ..sort((a, b) {
        final na = _langNames[a] ?? a;
        final nb = _langNames[b] ?? b;
        return na.compareTo(nb);
      });
    return sorted;
  }

  List<Map<String, dynamic>> _voicesForLang(String lang) {
    return _edgeVoices
        .where((v) => (v['locale']?.toString() ?? '').startsWith(lang))
        .toList();
  }

  String _voiceLabel(Map<String, dynamic> v) {
    final gender = v['gender']?.toString() == 'Female'
        ? ' (F)'
        : v['gender']?.toString() == 'Male'
        ? ' (M)'
        : '';
    final name = v['name']?.toString().trim();
    final id = v['id']?.toString().trim();
    return '${name?.isNotEmpty == true ? name : (id ?? 'Voz')}$gender';
  }

  Future<void> _saveVoice() async {
    final voice = _selectedVoice;
    if (voice == null || voice.isEmpty) return;
    setState(() {
      _savingVoice = true;
      _voiceStatus = '';
    });
    try {
      await widget.api.updateTtsSettings({'edge_voice': voice});
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Voz guardada correctamente.';
        _voiceStatusOk = true;
        _savingVoice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Error: $e';
        _voiceStatusOk = false;
        _savingVoice = false;
      });
    }
  }

  /// Synthesizes and plays the fixed preview line with the selected voice.
  /// Synthesis errors (400 missing voice / 502 synth failure) surface the
  /// backend `detail`; playback failures surface their own message.
  Future<void> _previewVoice() async {
    if (_previewingVoice) return;
    final voice = _selectedVoice;
    if (voice == null || voice.isEmpty) {
      setState(() {
        _voiceStatus = 'Elegí una voz para probar.';
        _voiceStatusOk = false;
      });
      return;
    }
    setState(() {
      _previewingVoice = true;
      _voiceStatus = '';
    });
    try {
      final bytes = await widget.api.ttsPreview(
        voice,
        'Hola, soy GAMMA. Así suena mi voz.',
      );
      if (!mounted) return;
      await _ttsPlayer.play(bytes);
      if (!mounted) return;
      setState(() => _previewingVoice = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Error: ${_errorDetail(e)}';
        _voiceStatusOk = false;
        _previewingVoice = false;
      });
    }
  }

  String _errorDetail(Object error) {
    if (error is ApiException) {
      final body = error.body;
      final detail = body is Map ? body['detail'] : null;
      if (detail != null) return detail.toString();
      return 'Error del servidor (${error.statusCode}).';
    }
    return error.toString();
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView(message: _error!, onRetry: () => _load(refresh: true));
    }
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: HeaderRow(
                  title: 'Ajustes',
                  onRefresh: () => _load(refresh: true),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Configura la voz, el sistema y los módulos de GAMMA.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList.list(
                children: [
                  _voiceCard(),
                  const SizedBox(height: 14),
                  _surfaceModeCard(),
                  const SizedBox(height: 14),
                  _modulesCard(),
                  const SizedBox(height: 14),
                  _systemCard(),
                  const SizedBox(height: 14),
                  _aiCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceCard() {
    final langs = _sortedLangs();
    final voices = _selectedLang == null
        ? <Map<String, dynamic>>[]
        : _voicesForLang(_selectedLang!);
    return SettingsCard(
      icon: CupertinoIcons.waveform,
      title: 'Voz del asistente',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _settingsRow(
            label: 'Idioma',
            child: DropdownButtonFormField<String>(
              key: const ValueKey('lang-select'),
              initialValue: langs.contains(_selectedLang)
                  ? _selectedLang
                  : (langs.isEmpty ? null : langs.first),
              isExpanded: true,
              decoration: _selectDecoration(),
              items: [
                for (final lang in langs)
                  DropdownMenuItem(
                    value: lang,
                    child: Text(_langNames[lang] ?? lang.toUpperCase()),
                  ),
              ],
              onChanged: (lang) => setState(() {
                _selectedLang = lang;
                if (lang != null) {
                  final first = _voicesForLang(lang).firstOrNull;
                  _selectedVoice = first?['id']?.toString();
                }
              }),
            ),
          ),
          _settingsRow(
            label: 'Voz',
            child: DropdownButtonFormField<String>(
              key: ValueKey('voice-select-${_selectedLang ?? 'none'}'),
              initialValue:
                  voices.any((v) => v['id']?.toString() == _selectedVoice)
                  ? _selectedVoice
                  : (voices.isEmpty ? null : voices.first['id']?.toString()),
              isExpanded: true,
              decoration: _selectDecoration(),
              items: [
                for (final v in voices)
                  DropdownMenuItem(
                    value: v['id']?.toString(),
                    child: Text(
                      _voiceLabel(v),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (voice) => setState(() => _selectedVoice = voice),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ToolButton(
                icon: CupertinoIcons.play_circle,
                label: _previewingVoice ? 'Probando…' : 'Probar voz',
                onTap: () {
                  if (!_previewingVoice) _previewVoice();
                },
              ),
              const SizedBox(width: 10),
              ToolButton(
                icon: CupertinoIcons.checkmark,
                label: _savingVoice ? 'Guardando…' : 'Guardar',
                filled: true,
                onTap: () {
                  if (!_savingVoice) _saveVoice();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_voiceStatus.isNotEmpty)
            Text(
              _voiceStatus,
              style: TextStyle(
                fontSize: 13,
                color: _voiceStatusOk ? AppColors.green : AppColors.red,
              ),
            ),
        ],
      ),
    );
  }

  Widget _surfaceModeCard() {
    return SettingsCard(
      icon: CupertinoIcons.sparkles,
      title: 'Modo de interfaz',
      child: ListenableBuilder(
        listenable: _surfaceModeController,
        builder: (context, _) {
          final mode = _surfaceModeController.value;
          return Material(
            type: MaterialType.transparency,
            child: RadioGroup<AppSurfaceMode>(
              groupValue: mode,
              onChanged: (next) {
                if (next != null) _surfaceModeController.setMode(next);
              },
              child: Column(
                children: [
                  for (final (m, label) in const [
                    (AppSurfaceMode.auto, 'Automático'),
                    (AppSurfaceMode.mobile, 'Móvil'),
                    (AppSurfaceMode.desktop, 'Escritorio'),
                    (AppSurfaceMode.wallPanel, 'Panel de pared'),
                  ])
                    RadioListTile<AppSurfaceMode>(
                      key: ValueKey('surface-mode-${m.name}'),
                      value: m,
                      title: Text(label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _modulesCard() {
    return SettingsCard(
      // iOS approx: no puzzle/extension icon — layers read as modules stack.
      icon: CupertinoIcons.layers,
      title: 'Módulos',
      child: ModulesSection(
        api: widget.api,
        onConfigure: _openModuleConfig,
        configuredModules: _configurableModules,
      ),
    );
  }

  /// Compact entry for the system-level AI configuration (Gemini key). The
  /// LLM key has no backend module row: it lives here, next to Sistema.
  Widget _aiCard() {
    return SettingsCard(
      icon: CupertinoIcons.lightbulb,
      title: 'Inteligencia artificial',
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: const ValueKey('open-ai-config'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Clave de Gemini y ajustes del modelo',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
          trailing: const Icon(
            CupertinoIcons.chevron_right,
            color: AppColors.textFaint,
          ),
          onTap: () => _openModuleConfig('llm'),
        ),
      ),
    );
  }

  /// Compact runtime status fed by `/api/v1/health`. Independent from the
  /// page load: a failure here shows an inline retry with no fabricated
  /// values and never blanks the rest of Settings.
  Widget _systemCard() {
    return SettingsCard(
      icon: CupertinoIcons.info_circle,
      title: 'Sistema',
      child: _systemLoading
          ? const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Leyendo estado…',
                  style: TextStyle(fontSize: 13, color: AppColors.textDim),
                ),
              ],
            )
          : _systemError != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No se pudo leer el estado del sistema.',
                  style: TextStyle(fontSize: 13, color: AppColors.red),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _retrySystem,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _systemRow(
                  'Modo',
                  _deviceModeLabel(_systemHealth!['device_mode']),
                ),
                _systemRow(
                  'Escritura física',
                  _writesLabel(_systemHealth!['writes_enabled']),
                ),
                if (_systemHealth!['uptime_seconds'] is num)
                  _systemRow(
                    'Activo hace',
                    _uptimeLabel(_systemHealth!['uptime_seconds']),
                  ),
                if (_systemHealth!['active_modules'] is List)
                  _systemRow(
                    'Módulos activos',
                    '${(_systemHealth!['active_modules'] as List).length}',
                  ),
              ],
            ),
    );
  }

  Widget _systemRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDim,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _deviceModeLabel(Object? raw) {
    final mode = raw?.toString();
    return switch (mode) {
      'simulation' => 'Simulación',
      'local' => 'Control local',
      'disabled' => 'Control desactivado',
      null || '' => 'Desconocido',
      _ => mode,
    };
  }

  String _writesLabel(Object? raw) {
    if (raw == true) return 'Escritura habilitada';
    if (raw == false) return 'Escritura deshabilitada';
    return 'Desconocida';
  }

  String _uptimeLabel(Object? raw) {
    if (raw is! num) return 'Desconocido';
    final total = raw.toInt();
    if (total < 60) return '$total s';
    if (total < 3600) return '${total ~/ 60} min';
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  Widget _settingsRow({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDim,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  InputDecoration _selectDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    );
  }
}
