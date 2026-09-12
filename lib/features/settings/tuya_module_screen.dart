import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import 'module_config_widgets.dart';

/// Tuya Cloud configuration: credentials used by the device provider to
/// discover and control Tuya devices. The API secret is write-only; changes
/// apply to the running core.
class TuyaModuleScreen extends StatefulWidget {
  const TuyaModuleScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<TuyaModuleScreen> createState() => _TuyaModuleScreenState();
}

class _TuyaModuleScreenState extends State<TuyaModuleScreen>
    with ModuleConfigLoader<TuyaModuleScreen> {
  static const _regionValues = ['', 'eu', 'us', 'in', 'cn'];
  static const _regionLabels = {
    '': 'Sin definir',
    'eu': 'eu',
    'us': 'us',
    'in': 'in',
    'cn': 'cn',
  };

  final _accessIdCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();
  final _deviceIdCtrl = TextEditingController();
  bool _cloudEnabled = false;
  String _region = '';
  bool _saving = false;
  String _status = '';
  bool _statusOk = true;

  @override
  ApiClient get moduleApi => widget.api;

  @override
  String get moduleConfigSection => 'tuya';

  @override
  void applyModuleSection(Map<String, dynamic> section) {
    _cloudEnabled = configValueOf(section, 'cloud_enabled') == 'true';
    final region = configValueOf(section, 'region') ?? '';
    // Unknown regions degrade to "Sin definir" so the dropdown always has a
    // matching item.
    _region = _regionValues.contains(region) ? region : '';
    _accessIdCtrl.text = configValueOf(section, 'access_id') ?? '';
    _deviceIdCtrl.text = configValueOf(section, 'device_id') ?? '';
    // Secrets are never seeded: blank means "keep the stored value".
    _apiSecretCtrl.clear();
  }

  @override
  void dispose() {
    _accessIdCtrl.dispose();
    _apiSecretCtrl.dispose();
    _deviceIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final section = moduleConfigData ?? const <String, dynamic>{};
    final currentCloud = configValueOf(section, 'cloud_enabled') == 'true';
    final currentRegion = configValueOf(section, 'region') ?? '';
    final currentAccessId = configValueOf(section, 'access_id');
    final currentDeviceId = configValueOf(section, 'device_id');
    final sendsCloud = _cloudEnabled != currentCloud;
    final sendsRegion = _region != currentRegion;
    final sendsAccessId = configIsNewValue(_accessIdCtrl, currentAccessId);
    final sendsDeviceId = configIsNewValue(_deviceIdCtrl, currentDeviceId);
    final secret = _apiSecretCtrl.text;
    if (!sendsCloud &&
        !sendsRegion &&
        !sendsAccessId &&
        !sendsDeviceId &&
        secret.isEmpty) {
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
      final response = await widget.api.updateTuyaConfig(
        cloudEnabled: sendsCloud ? _cloudEnabled : null,
        region: sendsRegion ? _region : null,
        accessId: sendsAccessId ? _accessIdCtrl.text.trim() : null,
        apiSecret: secret.isEmpty ? null : secret,
        deviceId: sendsDeviceId ? _deviceIdCtrl.text.trim() : null,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showConfigSavedMessage(
        context,
        response,
        fallback: 'Credenciales de Tuya guardadas.',
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
        title: const Text('Tuya'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsCard(
              icon: CupertinoIcons.wifi,
              title: 'Nube Tuya',
              child: buildModuleConfig(
                (section) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile.adaptive(
                        key: const ValueKey('config-tuya-cloud-enabled'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Activar nube Tuya',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: _cloudEnabled,
                        onChanged: (value) =>
                            setState(() => _cloudEnabled = value),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _regionDropdown(),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-tuya-access-id'),
                      label: 'Access ID',
                      controller: _accessIdCtrl,
                      helper: configSourceHintOf(section, 'access_id'),
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-tuya-api-secret'),
                      label: 'API secret',
                      controller: _apiSecretCtrl,
                      helper: configSecretHintOf(section, 'api_secret'),
                      obscure: true,
                    ),
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-tuya-device-id'),
                      label: 'Device ID',
                      controller: _deviceIdCtrl,
                      helper: _deviceHelper(section),
                    ),
                    ModuleConfigSaveRow(
                      saveKey: const ValueKey('config-tuya-save'),
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

  Widget _regionDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: const ValueKey('config-tuya-region'),
        initialValue: _region,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Región',
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
            borderSide: BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
        items: [
          for (final region in _regionValues)
            DropdownMenuItem(
              value: region,
              child: Text(_regionLabels[region] ?? region),
            ),
        ],
        onChanged: (region) => setState(() => _region = region ?? ''),
      ),
    );
  }

  String _deviceHelper(Map<String, dynamic> section) {
    final source = configSourceHintOf(section, 'device_id');
    return source == null ? 'Opcional' : 'Opcional · $source';
  }
}
