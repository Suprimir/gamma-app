import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import 'module_config_widgets.dart';

/// Artificial-intelligence module configuration: the Gemini API key. The new
/// key applies after restarting the core (backend `applies`/`message`).
class LlmModuleScreen extends StatefulWidget {
  const LlmModuleScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<LlmModuleScreen> createState() => _LlmModuleScreenState();
}

class _LlmModuleScreenState extends State<LlmModuleScreen>
    with ModuleConfigLoader<LlmModuleScreen> {
  final _apiKeyCtrl = TextEditingController();
  bool _saving = false;
  String _status = '';
  bool _statusOk = true;

  @override
  ApiClient get moduleApi => widget.api;

  @override
  String get moduleConfigSection => 'llm';

  @override
  void applyModuleSection(Map<String, dynamic> section) {
    // Secrets are never seeded: blank means "keep the stored value".
    _apiKeyCtrl.clear();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final apiKey = _apiKeyCtrl.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _status = 'Ingresá una API key para guardar.';
        _statusOk = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _status = '';
    });
    try {
      final response = await widget.api.updateLlmConfig(apiKey);
      if (!mounted) return;
      setState(() => _saving = false);
      showConfigSavedMessage(
        context,
        response,
        fallback: 'Se aplicará al reiniciar el núcleo',
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
        title: const Text('Inteligencia artificial'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsCard(
              icon: CupertinoIcons.lightbulb,
              title: 'Clave de Gemini',
              child: buildModuleConfig(
                (section) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ModuleConfigField(
                      fieldKey: const ValueKey('config-llm-api-key'),
                      label: 'Gemini API key',
                      controller: _apiKeyCtrl,
                      helper: configSecretHintOf(section, 'gemini_api_key'),
                      obscure: true,
                    ),
                    ModuleConfigSaveRow(
                      saveKey: const ValueKey('config-llm-save'),
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
