import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/open_in_new_tab.dart';
import '../../ui/shared_widgets.dart';
import 'module_config_widgets.dart';

/// Spotify module configuration: the account connection (auth flow) plus the
/// app credentials (client id/secret, device name, market).
class SpotifyModuleScreen extends StatefulWidget {
  const SpotifyModuleScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SpotifyModuleScreen> createState() => _SpotifyModuleScreenState();
}

class _SpotifyModuleScreenState extends State<SpotifyModuleScreen>
    with ModuleConfigLoader<SpotifyModuleScreen> {
  // Credentials
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  final _deviceNameCtrl = TextEditingController();
  final _marketCtrl = TextEditingController();
  bool _savingCredentials = false;
  String _credentialsStatus = '';
  bool _credentialsStatusOk = true;
  bool _reconnectRequired = false;

  // Connection (auth flow moved from the main Settings page)
  Map<String, dynamic>? _spotifySettings;
  bool _connecting = false;
  bool _disconnecting = false;
  String _connectionStatus = '';
  bool _connectionStatusOk = true;
  String _callbackWarning = '';
  Timer? _oauthPoll;

  // Local renderer (Soloist onboarding without SSH)
  Map<String, dynamic>? _soloistStatus;
  final _soloistKeyCtrl = TextEditingController();
  bool _savingSoloistKey = false;
  String _soloistKeyStatus = '';
  bool _soloistKeyStatusOk = true;
  Timer? _soloistPoll;
  Duration? _soloistPollInterval;
  String? _soloistJobId;
  String _soloistJobStatus = '';
  bool _soloistWorking = false;
  String _soloistActionStatus = '';
  bool _soloistActionOk = true;

  @override
  ApiClient get moduleApi => widget.api;

  @override
  String get moduleConfigSection => 'spotify';

  @override
  void initState() {
    super.initState();
    _loadSpotifySettings();
    _loadSoloistStatus();
  }

  Future<void> _loadSpotifySettings() async {
    try {
      final settings = await widget.api.spotifySettings();
      if (!mounted) return;
      setState(() => _spotifySettings = settings);
    } catch (_) {
      // The connection card keeps its neutral 'No conectado' state; the
      // credentials card owns any configuration-read failure.
    }
  }

  @override
  void applyModuleSection(Map<String, dynamic> section) {
    _clientIdCtrl.text = configValueOf(section, 'client_id') ?? '';
    _deviceNameCtrl.text = configValueOf(section, 'device_name') ?? '';
    _marketCtrl.text = configValueOf(section, 'market') ?? '';
    // Secrets are never seeded: blank means "keep the stored value".
    _clientSecretCtrl.clear();
  }

  @override
  void dispose() {
    _oauthPoll?.cancel();
    _soloistPoll?.cancel();
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    _deviceNameCtrl.dispose();
    _marketCtrl.dispose();
    _soloistKeyCtrl.dispose();
    super.dispose();
  }

  // --- Connection ----------------------------------------------------------

  Future<void> _connectSpotify() async {
    setState(() {
      _connecting = true;
      _connectionStatus = '';
      _callbackWarning = '';
    });
    try {
      final data = await widget.api.spotifyAuthStart();
      if (!mounted) return;
      final url = data['auth_url']?.toString();
      if (url == null || url.isEmpty) {
        throw StateError('URL de autorización vacía');
      }
      final warning = data['callback_warning']?.toString() ?? '';
      if (warning.isNotEmpty) {
        setState(() => _callbackWarning = warning);
      }
      await _openExternalUrl(url);
      if (!mounted) return;
      setState(() {
        _connectionStatus =
            'Se abrió una ventana de Spotify en tu navegador. '
            'Autoriza la aplicación y la conexión se realizará automáticamente.';
        _connectionStatusOk = true;
      });
      _startOAuthPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionStatus = 'Error: $e';
        _connectionStatusOk = false;
        _connecting = false;
      });
    }
  }

  static const _platformChannel = MethodChannel('gamma_app/external_url');

  Future<void> _openExternalUrl(String url) async {
    if (kIsWeb) {
      openInNewTab(url);
      return;
    }
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
            _connectionStatus = '';
            _callbackWarning = '';
          });
          return;
        }
        if (attempts >= 90) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _connectionStatus =
                'El tiempo de espera ha expirado. Intenta de nuevo.';
            _connectionStatusOk = false;
            _connecting = false;
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _connectionStatus =
              'Esperando autorización${'.' * (attempts % 3 + 1)}';
          _connectionStatusOk = true;
        });
      } catch (_) {
        if (attempts >= 90) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _connectionStatus =
                'El tiempo de espera ha expirado. Intenta de nuevo.';
            _connectionStatusOk = false;
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
      _connectionStatus = '';
      _callbackWarning = '';
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
        _connectionStatus = 'Error: $e';
        _connectionStatusOk = false;
        _disconnecting = false;
      });
    }
  }

  // --- Local renderer (Soloist onboarding) ---------------------------------

  Future<void> _loadSoloistStatus() async {
    try {
      final status = await widget.api.spotifySoloistStatus();
      if (!mounted) return;
      setState(() => _soloistStatus = status);
    } catch (_) {
      // The card keeps its neutral state; a failed read is never fatal.
    }
    _syncSoloistPoll();
  }

  /// Polls the onboarding state: fast (5s) while incomplete or a job runs,
  /// slow (30s) once ready so a lost WS connection converges back without
  /// user action. Cheap and read-only; never shows the API key.
  void _syncSoloistPoll() {
    final ready =
        _soloistStatus != null &&
        _soloistStatus!['ready'] == true &&
        _soloistJobId == null;
    final wanted = ready
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5);
    if (_soloistPoll != null && _soloistPollInterval == wanted) return;
    _soloistPoll?.cancel();
    _soloistPollInterval = wanted;
    _soloistPoll = Timer.periodic(wanted, (_) => _soloistTick());
  }

  Future<void> _soloistTick() async {
    if (_soloistJobId != null) await _pollSoloistJob();
    await _loadSoloistStatus();
  }

  Future<void> _pollSoloistJob() async {
    final jobId = _soloistJobId;
    if (jobId == null) return;
    try {
      final job = await widget.api.spotifySoloistJob(jobId);
      if (!mounted) return;
      final state = job['state']?.toString() ?? 'running';
      setState(() {
        final log = (job['log'] as List?)?.cast<String>() ?? const [];
        _soloistJobStatus = state == 'running'
            ? 'Instalando…'
            : state == 'done'
            ? 'Instalación completa.'
            : 'Falló: ${log.isNotEmpty ? log.last : 'sin detalle'}';
        if (state != 'running') _soloistJobId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _soloistJobStatus = 'Error consultando el trabajo: $e');
    }
  }

  Future<void> _saveSoloistKey() async {
    final key = _soloistKeyCtrl.text.trim();
    if (key.isEmpty || _savingSoloistKey) return;
    setState(() {
      _savingSoloistKey = true;
      _soloistKeyStatus = '';
    });
    try {
      await widget.api.spotifySoloistSaveKey(key);
      if (!mounted) return;
      setState(() {
        _savingSoloistKey = false;
        _soloistKeyStatusOk = true;
        _soloistKeyStatus = 'Clave guardada.';
      });
      _soloistKeyCtrl.clear();
      await _loadSoloistStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingSoloistKey = false;
        _soloistKeyStatus = configErrorMessage(e);
        _soloistKeyStatusOk = false;
      });
    }
  }

  Future<void> _soloistService(String action) async {
    if (_soloistWorking) return;
    setState(() {
      _soloistWorking = true;
      _soloistActionStatus = '';
    });
    try {
      final result = await widget.api.spotifySoloistService(action);
      if (!mounted) return;
      setState(() {
        _soloistWorking = false;
        _soloistActionOk = true;
        _soloistActionStatus = (result['message'] ?? 'Listo.').toString();
      });
      await _loadSoloistStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _soloistWorking = false;
        _soloistActionStatus = configErrorMessage(e);
        _soloistActionOk = false;
      });
    }
  }

  Future<void> _soloistInstall({bool update = false}) async {
    if (_soloistWorking || _soloistJobId != null) return;
    setState(() {
      _soloistWorking = true;
      _soloistActionStatus = '';
    });
    try {
      final result = await widget.api.spotifySoloistInstall(update: update);
      if (!mounted) return;
      setState(() {
        _soloistWorking = false;
        _soloistJobId = result['job_id']?.toString();
        _soloistJobStatus = 'Instalando…';
      });
      _syncSoloistPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _soloistWorking = false;
        _soloistActionStatus = configErrorMessage(e);
        _soloistActionOk = false;
      });
    }
  }

  // --- Credentials ---------------------------------------------------------

  Future<void> _saveCredentials() async {
    if (_savingCredentials) return;
    final section = moduleConfigData ?? const <String, dynamic>{};
    final currentId = configValueOf(section, 'client_id');
    final currentDevice = configValueOf(section, 'device_name');
    final currentMarket = configValueOf(section, 'market');
    final clientId = _clientIdCtrl.text.trim();
    final clientSecret = _clientSecretCtrl.text;
    final deviceName = _deviceNameCtrl.text.trim();
    final market = _marketCtrl.text.trim();
    final sendsClientId = configIsNewValue(_clientIdCtrl, currentId);
    final sendsDeviceName = configIsNewValue(_deviceNameCtrl, currentDevice);
    final sendsMarket = configIsNewValue(_marketCtrl, currentMarket);
    if (!sendsClientId &&
        clientSecret.isEmpty &&
        !sendsDeviceName &&
        !sendsMarket) {
      setState(() {
        _credentialsStatus = 'No hay cambios para guardar.';
        _credentialsStatusOk = true;
      });
      return;
    }
    setState(() {
      _savingCredentials = true;
      _credentialsStatus = '';
      _reconnectRequired = false;
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
        _savingCredentials = false;
        _reconnectRequired = response['reconnect_required'] == true;
      });
      showConfigSavedMessage(
        context,
        response,
        fallback: 'Configuración de Spotify guardada.',
      );
      await loadModuleConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingCredentials = false;
        _credentialsStatus = configErrorMessage(e);
        _credentialsStatusOk = false;
      });
    }
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Spotify'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _connectionCard(),
            const SizedBox(height: 14),
            _soloistCard(),
            const SizedBox(height: 14),
            SettingsCard(
              icon: CupertinoIcons.lock,
              title: 'Credenciales de la app',
              child: buildModuleConfig(
                (section) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-spotify-client-id'),
                      label: 'Client ID',
                      controller: _clientIdCtrl,
                      helper: configSourceHintOf(section, 'client_id'),
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-spotify-client-secret'),
                      label: 'Client Secret',
                      controller: _clientSecretCtrl,
                      helper: configSecretHintOf(section, 'client_secret'),
                      obscure: true,
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-spotify-device-name'),
                      label: 'Dispositivo',
                      controller: _deviceNameCtrl,
                      helper: configSourceHintOf(section, 'device_name'),
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-spotify-market'),
                      label: 'Mercado',
                      controller: _marketCtrl,
                      helper: configSourceHintOf(section, 'market'),
                    ),
                    if (_reconnectRequired) _reconnectWarning(),
                    ModuleConfigSaveRow(
                      saveKey: const ValueKey('config-spotify-save'),
                      saving: _savingCredentials,
                      onSave: _saveCredentials,
                    ),
                    const SizedBox(height: 4),
                    ModuleConfigStatus(
                      status: _credentialsStatus,
                      ok: _credentialsStatusOk,
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

  Widget _connectionCard() {
    final s = _spotifySettings ?? const <String, dynamic>{};
    final connected =
        s['authenticated'] == true && s['client_id_configured'] == true;
    return SettingsCard(
      icon: CupertinoIcons.music_note,
      title: 'Conexión',
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
            _meta('Cuenta: ${s['account_name']}'),
          if (connected && s['device_name'] != null)
            _meta('Dispositivo: ${s['device_name']}'),
          if (_callbackWarning.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _callbackWarning,
              key: const ValueKey('spotify-callback-warning'),
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.amber,
              ),
            ),
          ],
          if (_connectionStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _connectionStatus,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: _connectionStatusOk ? AppColors.textDim : AppColors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _soloistCard() {
    final s = _soloistStatus ?? const <String, dynamic>{};
    final ready = s['ready'] == true;
    final binary = s['binary'] is Map
        ? (s['binary'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final apiKey = s['api_key'] is Map
        ? (s['api_key'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final service = s['service'] is Map
        ? (s['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final adapter = s['adapter'] is Map
        ? (s['adapter'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final nextStep = s['next_step'] is Map
        ? (s['next_step'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final expiresIn = binary['expires_in_days'];
    final showExpiry =
        expiresIn is num && expiresIn < 15 && binary['present'] == true;
    return SettingsCard(
      icon: CupertinoIcons.speaker_2,
      title: 'Reproductor local',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 28,
                decoration: BoxDecoration(
                  color: ready
                      ? AppColors.green.withValues(alpha: 0.09)
                      : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ready
                        ? AppColors.green.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  ready ? 'Listo' : 'En proceso',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ready ? AppColors.green : AppColors.textFaint,
                  ),
                ),
              ),
              const Spacer(),
              ToolButton(
                icon: CupertinoIcons.refresh,
                label: 'Verificar',
                filled: false,
                onTap: _loadSoloistStatus,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _meta(_soloistBinaryLine(binary)),
          _meta(
            'Clave API: ${apiKey['configured'] == true ? 'configurada' : 'pendiente'}',
          ),
          _meta(_soloistServiceLine(service)),
          _meta(
            'Sesión: ${adapter['logged_in'] == true ? 'conectada' : 'sin conectar'}'
            '${adapter['is_active'] == true ? ' (dispositivo activo)' : ''}',
          ),
          if (s['device_visible'] == true)
            _meta('Visible en Spotify: sí'),
          if (nextStep['code'] == 'pair') ...[
            const SizedBox(height: 8),
            const Text(
              'Abre la app de Spotify en la misma red, elige tu reproductor '
              'en el selector de dispositivos y reproduce algo. Después pulsa '
              'Verificar.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textDim,
              ),
            ),
          ],
          if (showExpiry) ...[
            const SizedBox(height: 8),
            Text(
              'El build caduca en ${expiresIn.round()} días: actualiza antes de que deje de funcionar.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.amber,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ModuleConfigField(
            fieldKey: const ValueKey('config-soloist-api-key'),
            label: 'Clave API de Soloist',
            controller: _soloistKeyCtrl,
            helper: 'Solo se guarda, nunca se muestra. Generala en el panel de Soloist.',
            obscure: true,
          ),
          ModuleConfigSaveRow(
            saveKey: const ValueKey('config-soloist-save-key'),
            saving: _savingSoloistKey,
            onSave: _saveSoloistKey,
          ),
          const SizedBox(height: 4),
          ModuleConfigStatus(
            status: _soloistKeyStatus,
            ok: _soloistKeyStatusOk,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ToolButton(
                key: const ValueKey('config-soloist-install'),
                icon: CupertinoIcons.arrow_down_to_line,
                label: 'Instalar',
                filled: false,
                onTap: () {
                  if (!_soloistWorking && _soloistJobId == null) {
                    _soloistInstall();
                  }
                },
              ),
              ToolButton(
                key: const ValueKey('config-soloist-update'),
                icon: CupertinoIcons.arrow_2_circlepath,
                label: 'Actualizar',
                filled: false,
                onTap: () {
                  if (!_soloistWorking && _soloistJobId == null) {
                    _soloistInstall(update: true);
                  }
                },
              ),
              ToolButton(
                key: const ValueKey('config-soloist-service-start'),
                icon: CupertinoIcons.play,
                label: _soloistWorking ? 'Aplicando…' : 'Iniciar',
                filled: false,
                onTap: () => _soloistService('start'),
              ),
              ToolButton(
                key: const ValueKey('config-soloist-service-restart'),
                icon: CupertinoIcons.restart,
                label: 'Reiniciar',
                filled: false,
                onTap: () => _soloistService('restart'),
              ),
            ],
          ),
          if (_soloistJobStatus.isNotEmpty || _soloistActionStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (_soloistJobStatus.isNotEmpty)
              Text(
                _soloistJobStatus,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textDim,
                ),
              ),
            if (_soloistActionStatus.isNotEmpty)
              ModuleConfigStatus(
                status: _soloistActionStatus,
                ok: _soloistActionOk,
              ),
          ],
        ],
      ),
    );
  }

  String _soloistBinaryLine(Map<String, dynamic> binary) {
    if (binary['present'] != true) return 'Binario: no instalado';
    final version = binary['version']?.toString();
    final age = binary['age_days'];
    final head = version != null && version.isNotEmpty
        ? 'Binario: $version'
        : 'Binario: instalado';
    if (age is num) return '$head (${age.round()} días)';
    return head;
  }

  String _soloistServiceLine(Map<String, dynamic> service) {
    if (service['installed'] != true) return 'Servicio: no instalado';
    final state = service['active'] == true
        ? 'activo'
        : service['enabled'] == true
        ? 'habilitado, inactivo'
        : 'detenido';
    return 'Servicio: $state';
  }

  Widget _reconnectWarning() {
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

  Widget _meta(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textDim),
      ),
    );
  }
}
