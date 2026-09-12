import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import 'module_config_widgets.dart';

/// Cameras module configuration: NVR/ISAPI connection settings. The password
/// is write-only; changes apply after restarting the core.
class CamerasModuleScreen extends StatefulWidget {
  const CamerasModuleScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CamerasModuleScreen> createState() => _CamerasModuleScreenState();
}

class _CamerasModuleScreenState extends State<CamerasModuleScreen>
    with ModuleConfigLoader<CamerasModuleScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _isapiPathCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _saving = false;
  String _status = '';
  bool _statusOk = true;

  @override
  ApiClient get moduleApi => widget.api;

  @override
  String get moduleConfigSection => 'cameras';

  @override
  void applyModuleSection(Map<String, dynamic> section) {
    _hostCtrl.text = configValueOf(section, 'nvr_host') ?? '';
    _portCtrl.text = configValueOf(section, 'nvr_port') ?? '';
    _isapiPathCtrl.text = configValueOf(section, 'nvr_isapi_path') ?? '';
    _userCtrl.text = configValueOf(section, 'nvr_user') ?? '';
    // Secrets are never seeded: blank means "keep the stored value".
    _passCtrl.clear();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _isapiPathCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final section = moduleConfigData ?? const <String, dynamic>{};
    final currentHost = configValueOf(section, 'nvr_host');
    final currentPort = configValueOf(section, 'nvr_port');
    final currentPath = configValueOf(section, 'nvr_isapi_path');
    final currentUser = configValueOf(section, 'nvr_user');
    final host = _hostCtrl.text.trim();
    final portText = _portCtrl.text.trim();
    final path = _isapiPathCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    int? port;
    if (portText.isNotEmpty) {
      port = int.tryParse(portText);
      if (port == null) {
        setState(() {
          _status = 'El puerto debe ser un número.';
          _statusOk = false;
        });
        return;
      }
    }
    final sendsHost = configIsNewValue(_hostCtrl, currentHost);
    final sendsPort = portText.isNotEmpty && portText != currentPort;
    final sendsPath = configIsNewValue(_isapiPathCtrl, currentPath);
    final sendsUser = configIsNewValue(_userCtrl, currentUser);
    if (!sendsHost && !sendsPort && !sendsPath && !sendsUser && pass.isEmpty) {
      setState(() {
        _status = 'No hay cambios para guardar.';
        _statusOk = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _status = '';
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
      setState(() => _saving = false);
      showConfigSavedMessage(
        context,
        response,
        fallback: 'Configuración de cámaras guardada.',
      );
      await loadModuleConfig();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = configErrorMessage(e);
        _statusOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Cámaras'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsCard(
              icon: CupertinoIcons.videocam,
              title: 'NVR',
              child: buildModuleConfig(
                (section) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-cameras-host'),
                      label: 'Host del NVR',
                      controller: _hostCtrl,
                      helper: configSourceHintOf(section, 'nvr_host'),
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-cameras-port'),
                      label: 'Puerto',
                      controller: _portCtrl,
                      helper: configSourceHintOf(section, 'nvr_port'),
                      keyboardType: TextInputType.number,
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-cameras-isapi-path'),
                      label: 'Ruta ISAPI',
                      controller: _isapiPathCtrl,
                      helper: configSourceHintOf(section, 'nvr_isapi_path'),
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-cameras-user'),
                      label: 'Usuario',
                      controller: _userCtrl,
                      helper: configSourceHintOf(section, 'nvr_user'),
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-cameras-pass'),
                      label: 'Contraseña',
                      controller: _passCtrl,
                      helper: configSecretHintOf(section, 'nvr_pass'),
                      obscure: true,
                    ),
                    ModuleConfigSaveRow(
                      saveKey: const ValueKey('config-cameras-save'),
                      saving: _saving,
                      onSave: _save,
                    ),
                    const SizedBox(height: 4),
                    ModuleConfigStatus(status: _status, ok: _statusOk),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
