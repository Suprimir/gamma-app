import 'package:flutter/material.dart';

import '../../adaptive/adaptive_feature_controller.dart';
import '../../data/device_inventory.dart';
import '../../ui/app_colors.dart';
import '../../ui/device_status.dart';

/// Desktop master pane per Slice A spec: header 18w700+badge, location filter,
/// Add button indigo full-width, search pill, and [_DeviceRow] list.
///
/// The location filter opens a desktop-styled Ubicación dialog with one row
/// per area plus in-row edit/delete actions and an Agregar área entry — same
/// shared-controller mutations as the wall/touch surface, with compact
/// desktop controls.
class DesktopMasterPane extends StatefulWidget {
  const DesktopMasterPane({
    super.key,
    required this.devices,
    required this.areas,
    required this.selectedDeviceId,
    required this.onSelect,
    this.onAddDevice,
    this.controller,
    this.onAddArea,
    this.onEditArea,
    this.onDeleteArea,
    this.onDiscover,
    this.discovering = false,
    this.initialLocationId,
  });

  final List<PhysicalDevice> devices;
  final List<HomeArea> areas;
  final String? selectedDeviceId;
  final ValueChanged<PhysicalDevice> onSelect;
  final VoidCallback? onAddDevice;

  /// Shared feature controller (production). When set, area/discover actions
  /// default to it; tests can keep using the pure-props constructor.
  final AdaptiveFeatureController? controller;
  final VoidCallback? onAddArea;
  final ValueChanged<HomeArea>? onEditArea;
  final ValueChanged<HomeArea>? onDeleteArea;
  final VoidCallback? onDiscover;
  final bool discovering;

  /// Pre-selected area filter (e.g. Inicio → Ver dispositivos de un área).
  final String? initialLocationId;

  @override
  State<DesktopMasterPane> createState() => _DesktopMasterPaneState();
}

class _DesktopMasterPaneState extends State<DesktopMasterPane> {
  String _query = '';
  String? _selectedLocationId; // null = Todas

  @override
  void initState() {
    super.initState();
    _selectedLocationId = widget.initialLocationId;
  }

  bool get _showsDiscovery =>
      widget.controller != null || widget.onDiscover != null;

  String _labelFor(String? id) {
    if (id == null) return 'Todas las ubicaciones';
    for (final area in widget.areas) {
      if (area.id == id) return area.name;
    }
    return 'Todas las ubicaciones';
  }

  /// The closed filter control opens a desktop-styled Ubicación dialog
  /// (one row per area with edit/delete actions + Agregar área) instead of
  /// a popup menu. '' selects 'Todas'; dialog dismissal returns null and
  /// changes nothing.
  Future<void> _pickLocation() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _LocationPickerDialog(
        areas: widget.areas,
        selectedId: _selectedLocationId,
        onSelect: (id) => Navigator.of(dialogContext).pop(id),
        onEditArea: (area) {
          Navigator.of(dialogContext).pop();
          widget.onEditArea?.call(area);
        },
        onDeleteArea: (area) {
          Navigator.of(dialogContext).pop();
          // Optimistic: the deleted area can't stay selected.
          if (_selectedLocationId == area.id) {
            setState(() => _selectedLocationId = null);
          }
          widget.onDeleteArea?.call(area);
        },
        onAddArea: () {
          Navigator.of(dialogContext).pop();
          widget.onAddArea?.call();
        },
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _selectedLocationId = result.isEmpty ? null : result);
  }

  void _discover() => widget.onDiscover?.call();

  Future<void> _showFallbackAddDialog() async {
    final result = await showDialog<_MasterAddResult>(
      context: context,
      builder: (_) => _MasterAddDialog(
        selectedAreaId: _selectedLocationId,
        areas: widget.areas,
      ),
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dispositivo "${result.name}" agregado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final areaById = {for (final a in widget.areas) a.id: a};
    final query = _query.trim().toLowerCase();
    final filtered = widget.devices.where((d) {
      final matchesQuery =
          query.isEmpty ||
          (d.userName ?? d.name).toLowerCase().contains(query) ||
          (d.providerName ?? '').toLowerCase().contains(query) ||
          (areaById[d.physicalAreaId]?.name ?? '').toLowerCase().contains(
            query,
          );
      final matchesLocation =
          _selectedLocationId == null ||
          d.physicalAreaId == _selectedLocationId;
      return matchesQuery && matchesLocation;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Header: Dispositivos + badge
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Dispositivos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gammaIndigoLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${filtered.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gammaIndigo,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Location filter: tapping the closed control opens a desktop-styled
        // "Ubicación" dialog with one row per area — edit/delete inline and an
        // Agregar área entry — instead of a popup menu.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('desktop-location-filter'),
              onTap: _pickLocation,
              borderRadius: BorderRadius.circular(10),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _labelFor(_selectedLocationId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_selectedLocationId != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selectedLocationId = null),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.clear,
                            size: 16,
                            color: AppColors.textDim,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.expand_more,
                        size: 20,
                        color: AppColors.textDim,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Add button indigo full width
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onAddDevice ?? _showFallbackAddDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gammaIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '+Agregar dispositivo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        // Wall parity: discovery as a full-width secondary action.
        if (_showsDiscovery)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.discovering ? null : _discover,
                icon: widget.discovering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar_outlined, size: 17),
                label: Text(
                  widget.discovering ? 'Buscando…' : 'Buscar dispositivos',
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.gammaIndigo,
                ),
              ),
            ),
          ),
        // Search pill
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: const Key('desktop-device-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Buscar dispositivos',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          ),
        ),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Sin resultados',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
        for (final device in filtered) ...[
          _DeviceRow(
            key: ValueKey('desktop-device-${device.id}'),
            title: device.userName ?? device.name,
            subtitle: areaById[device.physicalAreaId]?.name ?? 'Sin área',
            device: device,
            health: device.health,
            selected: device.id == widget.selectedDeviceId,
            onSelect: () => widget.onSelect(device),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Desktop location picker: a compact dialog with a row for "Todas las
/// ubicaciones", one row per area (with inline edit/delete actions) and an
/// "Agregar área" entry. Selection and management callbacks are owned by the
/// caller, which pops the dialog and forwards mutations to the shared
/// controller.
class _LocationPickerDialog extends StatelessWidget {
  const _LocationPickerDialog({
    required this.areas,
    required this.selectedId,
    required this.onSelect,
    this.onEditArea,
    this.onDeleteArea,
    this.onAddArea,
  });

  final List<HomeArea> areas;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<HomeArea>? onEditArea;
  final ValueChanged<HomeArea>? onDeleteArea;
  final VoidCallback? onAddArea;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ubicación',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2),
          Text(
            'Filtra los dispositivos por habitación',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LocationOption(
                label: 'Todas las ubicaciones',
                icon: Icons.select_all_outlined,
                selected: selectedId == null,
                onTap: () => onSelect(''),
              ),
              for (final area in areas)
                _LocationOption(
                  label: area.name,
                  icon: Icons.place_outlined,
                  selected: selectedId == area.id,
                  onTap: () => onSelect(area.id),
                  actions: [
                    if (onEditArea != null)
                      IconButton(
                        tooltip: 'Editar área',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => onEditArea!(area),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.textDim,
                        ),
                      ),
                    if (onDeleteArea != null)
                      IconButton(
                        tooltip: 'Eliminar área',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => onDeleteArea!(area),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.errorRed,
                        ),
                      ),
                  ],
                ),
              if (onAddArea != null)
                _LocationOption(
                  label: 'Agregar área',
                  icon: Icons.add_home_outlined,
                  selected: false,
                  onTap: onAddArea!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact desktop option row: gamma-indigo highlight when selected and
/// optional trailing [actions] (edit/delete) that don't trigger the row tap.
class _LocationOption extends StatelessWidget {
  const _LocationOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.actions,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.gammaIndigoLight : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppColors.gammaIndigo.withValues(alpha: 0.06),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? AppColors.gammaIndigo : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.gammaIndigo : AppColors.textDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.gammaIndigo : AppColors.text,
                    ),
                  ),
                ),
                ...?actions,
                if (selected)
                  const Icon(
                    Icons.check,
                    size: 18,
                    color: AppColors.gammaIndigo,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MasterAddResult {
  const _MasterAddResult({required this.name, required this.type, this.areaId});
  final String name;
  final String type;
  final String? areaId;
}

class _MasterAddDialog extends StatefulWidget {
  const _MasterAddDialog({required this.selectedAreaId, required this.areas});
  final String? selectedAreaId;
  final List<HomeArea> areas;
  @override
  State<_MasterAddDialog> createState() => _MasterAddDialogState();
}

class _MasterAddDialogState extends State<_MasterAddDialog> {
  late final TextEditingController _nameController = TextEditingController();
  String _type = 'Luz';
  String? _error;
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío.');
      return;
    }
    Navigator.of(context).pop(
      _MasterAddResult(name: name, type: _type, areaId: widget.selectedAreaId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar dispositivo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nombre',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Luz', child: Text('Luz')),
                DropdownMenuItem(value: 'Enchufe', child: Text('Enchufe')),
                DropdownMenuItem(value: 'Sensor', child: Text('Sensor')),
                DropdownMenuItem(
                  value: 'Interruptor',
                  child: Text('Interruptor'),
                ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'Luz'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Agregar')),
      ],
    );
  }
}

class _DeviceRow extends StatefulWidget {
  const _DeviceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.device,
    required this.health,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final PhysicalDevice device;
  final DeviceHealthState health;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<_DeviceRow> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return FocusableActionDetector(
      focusNode: _focusNode,
      enabled: true,
      onFocusChange: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: Semantics(
        selected: selected,
        button: true,
        label: widget.title,
        child: Material(
          color: selected ? AppColors.gammaIndigoLight : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onSelect,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected
                      ? AppColors.gammaIndigo
                      : _focused
                      ? AppColors.gammaIndigo
                      : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Kind icon badge: specific glyph per DeviceKind (sensors
                  // resolve to what they measure) on a soft accent tint.
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kindBadgeColor(
                        widget.device.kind,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      deviceListIcon(widget.device),
                      size: 18,
                      color: kindBadgeColor(widget.device.kind),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: healthToColor(widget.health),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${healthToLabel(widget.health)} · ${widget.subtitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textDim,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
