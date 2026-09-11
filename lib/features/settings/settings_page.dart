import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../adaptive/adaptive_layout.dart';
import '../../adaptive/adaptive_scope.dart';
import '../../adaptive/adaptive_surface_preferences.dart';
import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../modules/modules_section.dart';
import '../../ui/shared_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    this.surfaceModeController,
  });

  final ApiClient api;
  final AdaptiveSurfaceModeController? surfaceModeController;

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
  String _voiceStatus = '';
  bool _voiceStatusOk = true;

  // Spotify
  Map<String, dynamic>? _spotifySettings;
  bool _connecting = false;
  bool _disconnecting = false;
  String _spotifyStatus = '';
  bool _spotifyStatusOk = true;
  Timer? _oauthPoll;
  late AdaptiveSurfaceModeController _surfaceModeController;
  bool _ownsSurfaceModeController = false;
  bool _surfaceModeControllerResolved = false;

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
    _oauthPoll?.cancel();
    if (_ownsSurfaceModeController) _surfaceModeController.dispose();
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
      final results = await Future.wait([
        widget.api.ttsSettings(),
        widget.api.ttsVoices(),
        widget.api.spotifySettings(),
      ]);
      if (!mounted) return;
      final settings = results[0];
      final voices = results[1];
      final spotify = results[2];
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
        _spotifySettings = spotify;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

  // --- Spotify -------------------------------------------------------------

  Future<void> _connectSpotify() async {
    setState(() {
      _connecting = true;
      _spotifyStatus = '';
    });
    try {
      final data = await widget.api.spotifyAuthStart();
      if (!mounted) return;
      final url = data['auth_url']?.toString();
      if (url == null || url.isEmpty) {
        throw StateError('URL de autorización vacía');
      }
      await _openExternalUrl(url);
      if (!mounted) return;
      setState(() {
        _spotifyStatus =
            'Se abrió una ventana de Spotify en tu navegador. '
            'Autoriza la aplicación y la conexión se realizará automáticamente.';
        _spotifyStatusOk = true;
      });
      _startOAuthPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _spotifyStatus = 'Error: $e';
        _spotifyStatusOk = false;
        _connecting = false;
      });
    }
  }

  static const _platformChannel = MethodChannel('gamma_app/external_url');

  Future<void> _openExternalUrl(String url) async {
    if (Platform.isAndroid) {
      await _platformChannel.invokeMethod<void>('openUrl', {'url': url});
      return;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [url]);
      if (result.exitCode != 0) {
        final details = result.stderr.toString().trim();
        throw StateError(
          details.isEmpty
              ? 'No se pudo abrir el navegador.'
              : 'No se pudo abrir el navegador: $details',
        );
      }
      return;
    }
    throw UnsupportedError('Abrir enlaces externos no está soportado aquí.');
  }

  void _startOAuthPolling() {
    _oauthPoll?.cancel();
    var attempts = 0;
    _oauthPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      try {
        final s = await widget.api.spotifySettings();
        if (!mounted) return;
        final connected =
            s['authenticated'] == true && s['client_id_configured'] == true;
        if (connected) {
          timer.cancel();
          setState(() {
            _spotifySettings = s;
            _connecting = false;
            _spotifyStatus = '';
          });
          return;
        }
        if (attempts >= 90) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _spotifyStatus =
                'El tiempo de espera ha expirado. Intenta de nuevo.';
            _spotifyStatusOk = false;
            _connecting = false;
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _spotifyStatus = 'Esperando autorización${'.' * (attempts % 3 + 1)}';
          _spotifyStatusOk = true;
        });
      } catch (_) {
        if (attempts >= 90) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _spotifyStatus =
                'El tiempo de espera ha expirado. Intenta de nuevo.';
            _spotifyStatusOk = false;
            _connecting = false;
          });
        }
      }
    });
  }

  Future<void> _disconnectSpotify() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar Spotify'),
        content: const Text('¿Desconectar la cuenta de Spotify?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Desconectar',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _disconnecting = true;
      _spotifyStatus = '';
    });
    try {
      await widget.api.spotifyAuthReset();
      final fresh = await widget.api.spotifySettings();
      if (!mounted) return;
      setState(() {
        _spotifySettings = fresh;
        _disconnecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _spotifyStatus = 'Error: $e';
        _spotifyStatusOk = false;
        _disconnecting = false;
      });
    }
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
                  'Configura la voz del asistente y tus servicios conectados.',
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
                  _spotifyCard(),
                  const SizedBox(height: 14),
                  _surfaceModeCard(),
                  const SizedBox(height: 14),
                  _modulesCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D14202D),
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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 27, color: AppColors.accent),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _voiceCard() {
    final langs = _sortedLangs();
    final voices = _selectedLang == null
        ? <Map<String, dynamic>>[]
        : _voicesForLang(_selectedLang!);
    return _settingsCard(
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
          Align(
            alignment: Alignment.centerRight,
            child: ToolButton(
              icon: CupertinoIcons.checkmark,
              label: _savingVoice ? 'Guardando…' : 'Guardar',
              filled: true,
              onTap: () {
                if (!_savingVoice) _saveVoice();
              },
            ),
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

  Widget _spotifyCard() {
    final s = _spotifySettings ?? const <String, dynamic>{};
    final connected =
        s['authenticated'] == true && s['client_id_configured'] == true;
    return _settingsCard(
      icon: CupertinoIcons.music_note,
      title: 'Spotify',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 28,
                decoration: BoxDecoration(
                  color: connected
                      ? AppColors.green.withValues(alpha: 0.09)
                      : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: connected
                        ? AppColors.green.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  connected ? 'Conectado' : 'No conectado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: connected ? AppColors.green : AppColors.textFaint,
                  ),
                ),
              ),
              const Spacer(),
              if (connected)
                ToolButton(
                  // iOS approx: no link-off icon — xmark reads as disconnect.
                  icon: CupertinoIcons.xmark,
                  label: _disconnecting ? 'Desconectando…' : 'Desconectar',
                  filled: false,
                  onTap: () {
                    if (!_disconnecting) _disconnectSpotify();
                  },
                )
              else
                ToolButton(
                  icon: CupertinoIcons.music_note,
                  label: _connecting ? 'Conectando…' : 'Conectar con Spotify',
                  filled: true,
                  onTap: () {
                    if (!_connecting) _connectSpotify();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (connected && s['account_name'] != null)
            _spotifyMeta('Cuenta: ${s['account_name']}'),
          if (connected && s['device_name'] != null)
            _spotifyMeta('Dispositivo: ${s['device_name']}'),
          if (_spotifyStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _spotifyStatus,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: _spotifyStatusOk ? AppColors.textDim : AppColors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _surfaceModeCard() {
    return _settingsCard(
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
    return _settingsCard(
      // iOS approx: no puzzle/extension icon — layers read as modules stack.
      icon: CupertinoIcons.layers,
      title: 'Módulos',
      child: ModulesSection(api: widget.api),
    );
  }

  Widget _spotifyMeta(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textDim),
      ),
    );
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
