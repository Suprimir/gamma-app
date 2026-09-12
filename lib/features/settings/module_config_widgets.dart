import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/shared_widgets.dart';

/// Card chrome shared by the main Settings page and the module configuration
/// screens.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
}

/// Human-safe message for a failed settings read/save: the backend `detail`
/// when present, otherwise the server status or the raw error.
String configErrorMessage(Object error) {
  if (error is ApiException) {
    final body = error.body;
    final detail = body is Map ? body['detail'] : null;
    if (detail != null) return detail.toString();
    return 'Error del servidor (${error.statusCode}).';
  }
  return error.toString();
}

/// Loading row for a module config screen reading the aggregated view.
class ModuleConfigLoading extends StatelessWidget {
  const ModuleConfigLoading({super.key});

  @override
  Widget build(BuildContext context) {
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
}

/// Inline failure with a retry affordance for a module config screen.
class ModuleConfigError extends StatelessWidget {
  const ModuleConfigError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(fontSize: 13, color: AppColors.red),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}

/// One labelled config input. [obscure] is used for secrets, which are never
/// pre-filled (blank means "keep the stored value").
class ModuleConfigField extends StatelessWidget {
  const ModuleConfigField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.helper,
    this.obscure = false,
    this.keyboardType,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: fieldKey,
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
}

/// Right-aligned Guardar button shared by the module config screens.
class ModuleConfigSaveRow extends StatelessWidget {
  const ModuleConfigSaveRow({
    super.key,
    required this.saveKey,
    required this.saving,
    required this.onSave,
  });

  final Key saveKey;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ToolButton(
          key: saveKey,
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
}

/// Inline save status (green when ok, red otherwise). Hidden when empty.
class ModuleConfigStatus extends StatelessWidget {
  const ModuleConfigStatus({super.key, required this.status, required this.ok});

  final String status;
  final bool ok;

  @override
  Widget build(BuildContext context) {
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
}

/// Shows the backend `message` (or [fallback]) in a SnackBar.
void showConfigSavedMessage(
  BuildContext context,
  Map<String, dynamic> response, {
  required String fallback,
}) {
  final message = response['message']?.toString();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message == null || message.isEmpty ? fallback : message),
    ),
  );
}

/// Redacted-view section map (`spotify`, `news`, `llm`, `cameras`).
Map<String, dynamic>? configSectionOf(
  Map<String, dynamic>? overview,
  String name,
) {
  final raw = overview?[name];
  return raw is Map ? raw.cast<String, dynamic>() : null;
}

/// Field entry map (`value`/`source`, or `configured`/`last4`) for [key].
Map<String, dynamic>? configEntryOf(Map<String, dynamic>? section, String key) {
  final raw = section?[key];
  return raw is Map ? raw.cast<String, dynamic>() : null;
}

String? configValueOf(Map<String, dynamic>? section, String key) =>
    configEntryOf(section, key)?['value']?.toString();

/// Redacted-view source hint; `env` values stay editable (saving moves them
/// into the store).
String? configSourceHintOf(Map<String, dynamic>? section, String key) {
  final source = configEntryOf(section, key)?['source']?.toString();
  return switch (source) {
    'env' => 'definido en .env',
    'store' => 'Guardado en la app',
    _ => null,
  };
}

/// Secret helper. Secret values never reach the client: only
/// configured/source/last4 are rendered.
String? configSecretHintOf(Map<String, dynamic>? section, String key) {
  final entry = configEntryOf(section, key);
  if (entry == null) return null;
  if (entry['configured'] != true) return 'Sin configurar';
  final last4 = entry['last4'];
  return last4 == null || last4.toString().isEmpty
      ? 'Configurado'
      : 'Configurado · últimos 4: $last4';
}

/// True when [controller] holds a new, non-empty value. Blank never counts as
/// a change (no clear/delete flows in this slice).
bool configIsNewValue(TextEditingController controller, String? current) {
  final text = controller.text.trim();
  return text.isNotEmpty && text != current;
}

/// Loads the aggregated redacted settings view once and exposes one section
/// to a module configuration screen. The screen keeps its own controllers and
/// save state; this mixin owns the loading/error/retry contract.
mixin ModuleConfigLoader<T extends StatefulWidget> on State<T> {
  ApiClient get moduleApi;

  /// Section key inside `GET /api/v1/settings` (e.g. `spotify`).
  String get moduleConfigSection;

  Map<String, dynamic>? moduleConfigData;
  bool moduleConfigLoading = true;
  String? moduleConfigError;

  @override
  void initState() {
    super.initState();
    loadModuleConfig();
  }

  /// Hydrates the screen controllers from the freshly loaded section (empty
  /// map when the backend omits the section).
  void applyModuleSection(Map<String, dynamic> section);

  Future<void> loadModuleConfig() async {
    try {
      final overview = await moduleApi.configOverview();
      if (!mounted) return;
      final section = configSectionOf(overview, moduleConfigSection);
      // Hydration degrades to empty when the backend omits the section; the
      // builder still surfaces "not available" instead of fake values.
      applyModuleSection(section ?? const <String, dynamic>{});
      setState(() {
        moduleConfigData = section;
        moduleConfigError = null;
        moduleConfigLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        moduleConfigError = configErrorMessage(e);
        moduleConfigLoading = false;
      });
    }
  }

  void retryModuleConfig() {
    setState(() {
      moduleConfigLoading = true;
      moduleConfigError = null;
    });
    loadModuleConfig();
  }

  /// Shared body: loading → error/retry → builder(section).
  Widget buildModuleConfig(
    Widget Function(Map<String, dynamic> section) builder,
  ) {
    if (moduleConfigLoading) return const ModuleConfigLoading();
    if (moduleConfigError != null) {
      // Fixed household copy; the raw detail stays in [moduleConfigError] for
      // debugging/logging without leaking server internals into the card.
      return ModuleConfigError(
        message: 'No se pudo leer la configuración del núcleo.',
        onRetry: retryModuleConfig,
      );
    }
    final section = moduleConfigData;
    if (section == null) {
      return ModuleConfigError(
        message: 'Esta sección no está disponible.',
        onRetry: retryModuleConfig,
      );
    }
    return builder(section);
  }
}
