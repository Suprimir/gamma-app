import 'package:flutter/material.dart';

import '../../data/api_client.dart';

/// Confirma una eliminación de área con la copia canónica (F2-C). Reutilizado
/// por mobile, desktop y wall para que el flujo sea idéntico.
Future<bool> showAreaDeleteConfirm(BuildContext context, String areaName) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Eliminar área'),
      content: Text('¿Eliminar "$areaName"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  ).then((value) => value ?? false);
}

/// Mapea errores de CRUD de áreas a mensajes honestos (F2-C).
String areaErrorMessage(Object error) {
  return switch (error) {
    ApiException(:final statusCode) when statusCode == 409 =>
      'No se puede eliminar esta área porque todavía está asignada a uno o más dispositivos o canales.',
    ApiException(:final statusCode) when statusCode == 404 =>
      'El área ya no existe. Se actualizó la lista.',
    ApiException(:final statusCode) when statusCode == 503 =>
      'No se pudo guardar el cambio. Inténtalo de nuevo.',
    ApiException(:final body) =>
      body is Map && body['detail'] is String
          ? body['detail'] as String
          : 'Error del servidor.',
    UnsupportedError() =>
      'La eliminación de áreas no está disponible en esta versión.',
    _ => error.toString(),
  };
}

/// Formulario canónico de editor de área: nombre + aliases.
///
/// Compartido por el diálogo móvil/desktop (envuelto en [AreaEditorDialog]),
/// el panel de detalle desktop y la página touch de wall. El botón de enviar
/// pertenece al formulario; [onSubmit] recibe nombre y aliases recortados y
/// validados. Sin alturas fijas alrededor de las etiquetas: escala de texto
/// grande nunca recorta el contenido.
class AreaEditorForm extends StatefulWidget {
  const AreaEditorForm({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.initialName = '',
    this.initialAliases = const [],
    this.busy = false,
    this.large = false,
    this.autofocus = false,
  });

  final String submitLabel;
  final Future<void> Function(String name, List<String> aliases) onSubmit;
  final String initialName;
  final List<String> initialAliases;

  /// Desactiva el envío mientras una mutación está en curso.
  final bool busy;

  /// Controles más grandes para superficies touch-first (wall).
  final bool large;

  /// Foco inicial en el campo de nombre (diálogo móvil).
  final bool autofocus;

  @override
  State<AreaEditorForm> createState() => _AreaEditorFormState();
}

class _AreaEditorFormState extends State<AreaEditorForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final List<TextEditingController> _aliasControllers = [
    for (final alias in widget.initialAliases)
      TextEditingController(text: alias),
  ];
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _aliasControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addAlias() {
    setState(() => _aliasControllers.add(TextEditingController()));
  }

  void _removeAlias(int index) {
    setState(() {
      _aliasControllers.removeAt(index).dispose();
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'El nombre no puede estar vacío.');
      return;
    }
    if (widget.busy) return;
    final aliases = _aliasControllers
        .map((controller) => controller.text.trim())
        .where((alias) => alias.isNotEmpty)
        .toList();
    await widget.onSubmit(name, aliases);
  }

  @override
  Widget build(BuildContext context) {
    final fieldStyle = widget.large ? const TextStyle(fontSize: 17) : null;
    final contentPadding = widget.large
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 16)
        : null;
    final aliasDecoration = widget.large
        ? InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: contentPadding,
          )
        : const InputDecoration(border: OutlineInputBorder(), isDense: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.autofocus,
          style: fieldStyle,
          decoration: InputDecoration(
            labelText: 'Nombre',
            errorText: _nameError,
            border: const OutlineInputBorder(),
            contentPadding: contentPadding,
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        const Text('Aliases', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (var index = 0; index < _aliasControllers.length; index++) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aliasControllers[index],
                  style: fieldStyle,
                  decoration: aliasDecoration,
                ),
              ),
              IconButton(
                tooltip: 'Quitar alias',
                onPressed: () => _removeAlias(index),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addAlias,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar alias'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.busy ? null : _submit,
            style: widget.large
                ? FilledButton.styleFrom(minimumSize: const Size.fromHeight(56))
                : null,
            child: Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }
}

/// Diálogo de editor de área (F2-C): chrome de diálogo + [AreaEditorForm].
/// Devuelve `({String name, List<String> aliases})` o `null` al cancelar.
class AreaEditorDialog extends StatefulWidget {
  const AreaEditorDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    this.initialName = '',
    this.initialAliases = const [],
  });

  final String title;
  final String submitLabel;
  final String initialName;
  final List<String> initialAliases;

  @override
  State<AreaEditorDialog> createState() => _AreaEditorDialogState();
}

class _AreaEditorDialogState extends State<AreaEditorDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: AreaEditorForm(
          initialName: widget.initialName,
          initialAliases: widget.initialAliases,
          submitLabel: widget.submitLabel,
          autofocus: true,
          onSubmit: (name, aliases) async {
            Navigator.of(context).pop((name: name, aliases: aliases));
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
