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
import 'tts_preview_player.dart';

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

  // Configuración del núcleo (settings API, redacted view)
  Map<String, dynamic>? _configOverview;
  String? _configError;
  bool _configLoading = true;

  final _spotifyClientIdCtrl = TextEditingController();
  final _spotifyClientSecretCtrl = TextEditingController();
  final _spotifyDeviceNameCtrl = TextEditingController();
  final _spotifyMarketCtrl = TextEditingController();
  final _newsApiKeyCtrl = TextEditingController();
  final _llmApiKeyCtrl = TextEditingController();
  final _nvrHostCtrl = TextEditingController();
  final _nvrPortCtrl = TextEditingController();
  final _nvrIsapiPathCtrl = TextEditingController();
  final _nvrUserCtrl = TextEditingController();
  final _nvrPassCtrl = TextEditingController();

  bool _savingSpotifyConfig = false;
  String _spotifyConfigStatus = '';
  bool _spotifyConfigStatusOk = true;
  bool _spotifyReconnectRequired = false;

  bool _savingNewsConfig = false;
  String _newsConfigStatus = '';
  bool _newsConfigStatusOk = true;

  bool _savingLlmConfig = false;
  String _llmConfigStatus = '';
  bool _llmConfigStatusOk = true;

  bool _savingCamerasConfig = false;
  String _camerasConfigStatus = '';
  bool _camerasConfigStatusOk = true;

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

  late final TtsPreviewPlayer _ttsPlayer =
      widget.ttsPreviewPlayer ?? MediaKitTtsPreviewPlayer();
  bool get _ownsTtsPlayer => widget.ttsPreviewPlayer == null;

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
    if (_ownsTtsPlayer) _ttsPlayer.dispose();
    _spotifyClientIdCtrl.dispose();
    _spotifyClientSecretCtrl.dispose();
    _spotifyDeviceNameCtrl.dispose();
    _spotifyMarketCtrl.dispose();
    _newsApiKeyCtrl.dispose();
    _llmApiKeyCtrl.dispose();
    _nvrHostCtrl.dispose();
    _nvrPortCtrl.dispose();
    _nvrIsapiPathCtrl.dispose();
    _nvrUserCtrl.dispose();
    _nvrPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _systemLoading = true;
        _systemError = null;
        _configLoading = true;
        _configError = null;
      });
    }
    // Run independently: a health/config failure must never blank the page.
    final system = _loadSystem();
    final config = _loadConfig();
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
    await system;
    await config;
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

  // --- Configuración del núcleo (settings API) -----------------------------

  /// Reads the aggregated redacted settings view once. Never throws: every
  /// config card owns its loading/error state, so a failure here never blanks
  /// the page (same contract as [_loadSystem]).
  Future<void> _loadConfig() async {
    try {
      final overview = await widget.api.configOverview();
      if (!mounted) return;
      // Assign before hydrating: the field lookups read `_configOverview`.
      _configOverview = overview;
      _hydrateConfigFields(overview);
      setState(() {
        _configError = null;
        _configLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _configError = _errorDetail(e);
        _configLoading = false;
      });
    }
  }

  void _retryConfig() {
    setState(() {
      _configLoading = true;
      _configError = null;
    });
    _loadConfig();
  }

  Map<String, dynamic>? _configSection(String name) {
    final raw = _configOverview?[name];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Field entry map (`value`/`source`, or `configured`/`last4`) for [key].
  Map<String, dynamic>? _configEntry(String section, String key) {
    final raw = _configSection(section)?[key];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  String? _configValue(String section, String key) =>
      _configEntry(section, key)?['value']?.toString();

  /// Redacted-view source hint; `env` values stay editable (saving moves them
  /// into the store).
  String? _configSourceHint(String section, String key) {
    final source = _configEntry(section, key)?['source']?.toString();
    return switch (source) {
      'env' => 'definido en .env',
      'store' => 'Guardado en la app',
      _ => null,
    };
  }

  /// Secret helper. Secret values never reach the client: only
  /// configured/source/last4 are rendered.
  String? _secretHint(String section, String key) {
    final entry = _configEntry(section, key);
    if (entry == null) return null;
    if (entry['configured'] != true) return 'Sin configurar';
    final last4 = entry['last4'];
    return last4 == null || last4.toString().isEmpty
        ? 'Configurado'
        : 'Configurado · últimos 4: $last4';
  }

  /// Fills the form fields from the redacted view. Secret inputs always start
  /// empty: blank means "keep the stored value".
  void _hydrateConfigFields(Map<String, dynamic> overview) {
    _spotifyClientIdCtrl.text = _configValue('spotify', 'client_id') ?? '';
    _spotifyDeviceNameCtrl.text = _configValue('spotify', 'device_name') ?? '';
    _spotifyMarketCtrl.text = _configValue('spotify', 'market') ?? '';
    _spotifyClientSecretCtrl.clear();

    _newsApiKeyCtrl.clear();
    _llmApiKeyCtrl.clear();

    _nvrHostCtrl.text = _configValue('cameras', 'nvr_host') ?? '';
    _nvrPortCtrl.text = _configValue('cameras', 'nvr_port') ?? '';
    _nvrIsapiPathCtrl.text = _configValue('cameras', 'nvr_isapi_path') ?? '';
    _nvrUserCtrl.text = _configValue('cameras', 'nvr_user') ?? '';
    _nvrPassCtrl.clear();
  }

  /// True when [controller] holds a new, non-empty value. Blank never counts
  /// as a change (no clear/delete flows in this slice).
  bool _isNewValue(TextEditingController controller, String? current) {
    final text = controller.text.trim();
    return text.isNotEmpty && text != current;
  }

  void _showSavedMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _successMessage(Map<String, dynamic> response, String fallback) {
    final message = response['message']?.toString();
    return message == null || message.isEmpty ? fallback : message;
  }

  Future<void> _saveSpotifyConfig() async {
    if (_savingSpotifyConfig) return;
    final currentId = _configValue('spotify', 'client_id');
    final currentDevice = _configValue('spotify', 'device_name');
    final currentMarket = _configValue('spotify', 'market');
    final clientId = _spotifyClientIdCtrl.text.trim();
    final clientSecret = _spotifyClientSecretCtrl.text;
    final deviceName = _spotifyDeviceNameCtrl.text.trim();
    final market = _spotifyMarketCtrl.text.trim();
    final sendsClientId = _isNewValue(_spotifyClientIdCtrl, currentId);
    final sendsDeviceName = _isNewValue(_spotifyDeviceNameCtrl, currentDevice);
    final sendsMarket = _isNewValue(_spotifyMarketCtrl, currentMarket);
    if (!sendsClientId &&
        clientSecret.isEmpty &&
        !sendsDeviceName &&
        !sendsMarket) {
      setState(() {
        _spotifyConfigStatus = 'No hay cambios para guardar.';
        _spotifyConfigStatusOk = true;
      });
      return;
    }
    setState(() {
      _savingSpotifyConfig = true;
      _spotifyConfigStatus = '';
      _spotifyReconnectRequired = false;
    });
    try {
      final response = await widget.api.updateSpotifyConfig(
        clientId: sendsClientId ? clientId : null,
        clientSecret: clientSecret.isEmpty ? null : clientSecret,
        deviceName: sendsDeviceName ? deviceName : null,
        market: sendsMarket ? market : null,
      );
      if (!mounted) return;
      setState(() {
        _savingSpotifyConfig = false;
        _spotifyReconnectRequired = response['reconnect_required'] == true;
      });
      _showSavedMessage(
        _successMessage(response, 'Configuración de Spotify guardada.'),
      );
      await _loadConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingSpotifyConfig = false;
        _spotifyConfigStatus = _errorDetail(e);
        _spotifyConfigStatusOk = false;
      });
    }
  }

  Future<void> _saveNewsConfig() async {
    if (_savingNewsConfig) return;
    final apiKey = _newsApiKeyCtrl.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _newsConfigStatus = 'Ingresá una API key para guardar.';
        _newsConfigStatusOk = false;
      });
      return;
    }
    setState(() {
      _savingNewsConfig = true;
      _newsConfigStatus = '';
    });
    try {
      final response = await widget.api.updateNewsConfig(apiKey);
      if (!mounted) return;
      setState(() => _savingNewsConfig = false);
      _showSavedMessage(
        _successMessage(response, 'API key de noticias guardada.'),
      );
      await _loadConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingNewsConfig = false;
        _newsConfigStatus = _errorDetail(e);
        _newsConfigStatusOk = false;
      });
    }
  }

  Future<void> _saveLlmConfig() async {
    if (_savingLlmConfig) return;
    final apiKey = _llmApiKeyCtrl.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _llmConfigStatus = 'Ingresá una API key para guardar.';
        _llmConfigStatusOk = false;
      });
      return;
    }
    setState(() {
      _savingLlmConfig = true;
      _llmConfigStatus = '';
    });
    try {
      final response = await widget.api.updateLlmConfig(apiKey);
      if (!mounted) return;
      setState(() => _savingLlmConfig = false);
      _showSavedMessage(
        _successMessage(response, 'Se aplicará al reiniciar el núcleo'),
      );
      await _loadConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingLlmConfig = false;
        _llmConfigStatus = _errorDetail(e);
        _llmConfigStatusOk = false;
      });
    }
  }

  Future<void> _saveCamerasConfig() async {
    if (_savingCamerasConfig) return;
    final currentHost = _configValue('cameras', 'nvr_host');
    final currentPort = _configValue('cameras', 'nvr_port');
    final currentPath = _configValue('cameras', 'nvr_isapi_path');
    final currentUser = _configValue('cameras', 'nvr_user');
    final host = _nvrHostCtrl.text.trim();
    final portText = _nvrPortCtrl.text.trim();
    final path = _nvrIsapiPathCtrl.text.trim();
    final user = _nvrUserCtrl.text.trim();
    final pass = _nvrPassCtrl.text;
    int? port;
    if (portText.isNotEmpty) {
      port = int.tryParse(portText);
      if (port == null) {
        setState(() {
          _camerasConfigStatus = 'El puerto debe ser un número.';
          _camerasConfigStatusOk = false;
        });
        return;
      }
    }
    final sendsHost = _isNewValue(_nvrHostCtrl, currentHost);
    final sendsPort = portText.isNotEmpty && portText != currentPort;
    final sendsPath = _isNewValue(_nvrIsapiPathCtrl, currentPath);
    final sendsUser = _isNewValue(_nvrUserCtrl, currentUser);
    if (!sendsHost && !sendsPort && !sendsPath && !sendsUser && pass.isEmpty) {
      setState(() {
        _camerasConfigStatus = 'No hay cambios para guardar.';
        _camerasConfigStatusOk = true;
      });
      return;
    }
    setState(() {
      _savingCamerasConfig = true;
      _camerasConfigStatus = '';
    });
    try {
      final response = await widget.api.updateCamerasConfig(
        nvrHost: sendsHost ? host : null,
        nvrPort: sendsPort ? port : null,
        nvrIsapiPath: sendsPath ? path : null,
        nvrUser: sendsUser ? user : null,
        nvrPass: pass.isEmpty ? null : pass,
      );
      if (!mounted) return;
      setState(() => _savingCamerasConfig = false);
      _showSavedMessage(
        _successMessage(response, 'Configuración de cámaras guardada.'),
      );
      await _loadConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingCamerasConfig = false;
        _camerasConfigStatus = _errorDetail(e);
        _camerasConfigStatusOk = false;
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
                  const SizedBox(height: 14),
                  _systemCard(),
                  const SizedBox(height: 14),
                  _spotifyConfigCard(),
                  const SizedBox(height: 14),
                  _newsConfigCard(),
                  const SizedBox(height: 14),
                  _llmConfigCard(),
                  const SizedBox(height: 14),
                  _camerasConfigCard(),
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

  // --- Tarjetas de configuración del núcleo --------------------------------

  /// Wraps a config card body with the shared loading / failure isolation:
  /// a failed aggregated read (or a missing section) never blanks the page.
  Widget _configCardBody(
    String sectionName,
    Widget Function(Map<String, dynamic> section) builder,
  ) {
    if (_configLoading) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Leyendo configuración…',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ],
      );
    }
    if (_configError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No se pudo leer la configuración del núcleo.',
            style: TextStyle(fontSize: 13, color: AppColors.red),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _retryConfig,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    final section = _configSection(sectionName);
    if (section == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Esta sección no está disponible.',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _retryConfig,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    return builder(section);
  }

  Widget _configField({
    required Key key,
    required String label,
    required TextEditingController controller,
    String? helper,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          filled: true,
          fillColor: AppColors.surfaceRaised,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _configSaveRow({
    required Key key,
    required bool saving,
    required VoidCallback onSave,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ToolButton(
          key: key,
          icon: CupertinoIcons.checkmark,
          label: saving ? 'Guardando…' : 'Guardar',
          filled: true,
          onTap: () {
            if (!saving) onSave();
          },
        ),
      ],
    );
  }

  Widget _configStatusText(String status, bool ok) {
    if (status.isEmpty) return const SizedBox.shrink();
    return Text(
      status,
      style: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: ok ? AppColors.green : AppColors.red,
      ),
    );
  }

  Widget _spotifyReconnectWarning() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reconectá tu cuenta para usar las credenciales nuevas',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            TextButton.icon(
              key: const ValueKey('spotify-reconnect'),
              onPressed: _connecting ? null : _connectSpotify,
              icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 18),
              label: const Text('Reconectar con Spotify'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spotifyConfigCard() {
    return _settingsCard(
      icon: CupertinoIcons.lock,
      title: 'Configuración de Spotify',
      child: _configCardBody('spotify', (section) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _configField(
              key: const ValueKey('config-spotify-client-id'),
              label: 'Client ID',
              controller: _spotifyClientIdCtrl,
              helper: _configSourceHint('spotify', 'client_id'),
            ),
            _configField(
              key: const ValueKey('config-spotify-client-secret'),
              label: 'Client Secret',
              controller: _spotifyClientSecretCtrl,
              helper: _secretHint('spotify', 'client_secret'),
              obscure: true,
            ),
            _configField(
              key: const ValueKey('config-spotify-device-name'),
              label: 'Dispositivo',
              controller: _spotifyDeviceNameCtrl,
              helper: _configSourceHint('spotify', 'device_name'),
            ),
            _configField(
              key: const ValueKey('config-spotify-market'),
              label: 'Mercado',
              controller: _spotifyMarketCtrl,
              helper: _configSourceHint('spotify', 'market'),
            ),
            if (_spotifyReconnectRequired) _spotifyReconnectWarning(),
            _configSaveRow(
              key: const ValueKey('config-spotify-save'),
              saving: _savingSpotifyConfig,
              onSave: _saveSpotifyConfig,
            ),
            const SizedBox(height: 4),
            _configStatusText(_spotifyConfigStatus, _spotifyConfigStatusOk),
          ],
        );
      }),
    );
  }

  Widget _newsConfigCard() {
    return _settingsCard(
      icon: CupertinoIcons.news,
      title: 'Noticias',
      child: _configCardBody('news', (section) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _configField(
              key: const ValueKey('config-news-api-key'),
              label: 'API key',
              controller: _newsApiKeyCtrl,
              helper: _secretHint('news', 'api_key'),
              obscure: true,
            ),
            _configSaveRow(
              key: const ValueKey('config-news-save'),
              saving: _savingNewsConfig,
              onSave: _saveNewsConfig,
            ),
            const SizedBox(height: 4),
            _configStatusText(_newsConfigStatus, _newsConfigStatusOk),
          ],
        );
      }),
    );
  }

  Widget _llmConfigCard() {
    return _settingsCard(
      icon: CupertinoIcons.lightbulb,
      title: 'Inteligencia artificial',
      child: _configCardBody('llm', (section) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _configField(
              key: const ValueKey('config-llm-api-key'),
              label: 'Gemini API key',
              controller: _llmApiKeyCtrl,
              helper: _secretHint('llm', 'gemini_api_key'),
              obscure: true,
            ),
            _configSaveRow(
              key: const ValueKey('config-llm-save'),
              saving: _savingLlmConfig,
              onSave: _saveLlmConfig,
            ),
            const SizedBox(height: 4),
            _configStatusText(_llmConfigStatus, _llmConfigStatusOk),
          ],
        );
      }),
    );
  }

  Widget _camerasConfigCard() {
    return _settingsCard(
      icon: CupertinoIcons.videocam,
      title: 'Cámaras',
      child: _configCardBody('cameras', (section) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _configField(
              key: const ValueKey('config-cameras-host'),
              label: 'Host del NVR',
              controller: _nvrHostCtrl,
              helper: _configSourceHint('cameras', 'nvr_host'),
            ),
            _configField(
              key: const ValueKey('config-cameras-port'),
              label: 'Puerto',
              controller: _nvrPortCtrl,
              helper: _configSourceHint('cameras', 'nvr_port'),
              keyboardType: TextInputType.number,
            ),
            _configField(
              key: const ValueKey('config-cameras-isapi-path'),
              label: 'Ruta ISAPI',
              controller: _nvrIsapiPathCtrl,
              helper: _configSourceHint('cameras', 'nvr_isapi_path'),
            ),
            _configField(
              key: const ValueKey('config-cameras-user'),
              label: 'Usuario',
              controller: _nvrUserCtrl,
              helper: _configSourceHint('cameras', 'nvr_user'),
            ),
            _configField(
              key: const ValueKey('config-cameras-pass'),
              label: 'Contraseña',
              controller: _nvrPassCtrl,
              helper: _secretHint('cameras', 'nvr_pass'),
              obscure: true,
            ),
            _configSaveRow(
              key: const ValueKey('config-cameras-save'),
              saving: _savingCamerasConfig,
              onSave: _saveCamerasConfig,
            ),
            const SizedBox(height: 4),
            _configStatusText(_camerasConfigStatus, _camerasConfigStatusOk),
          ],
        );
      }),
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

  /// Compact runtime status fed by `/api/v1/health`. Independent from the
  /// page load: a failure here shows an inline retry with no fabricated
  /// values and never blanks the rest of Settings.
  Widget _systemCard() {
    return _settingsCard(
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
