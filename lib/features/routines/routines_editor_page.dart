import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../adaptive/adaptive_scope.dart';
import '../devices/devices_page.dart' show formatDeviceName, formatLocationName;
import 'routine_actions.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/app_colors.dart';

Color get _accent => AppColors.accent;
const _dimText = AppColors.textDim;
const _dimCap = AppColors.textDim;
const _border = AppColors.border;
const _danger = AppColors.red;
const _softFill = AppColors.surfaceRaised;
// ponytail: blur 10 en vez de 20 — las sombras con blur grande son lo más
// caro de rasterizar en móvil; con muchas cards en pantalla el scroll sufre.
const _cardShadow = BoxShadow(
  color: AppColors.shadow,
  blurRadius: 10,
  offset: Offset(0, 4),
);

const _moduleNames = {
  'spotify': 'Spotify',
  'news': 'Noticias',
  'cameras': 'Cámaras',
};

const _stepLabels = ['Acciones', 'Detalles', 'Revisar'];

class RoutinesEditorPage extends StatefulWidget {
  const RoutinesEditorPage({
    super.key,
    required this.api,
    this.routineId,
    this.wallLayout = false,
  });

  final ApiClient api;
  final String? routineId;

  /// Acomodo de una sola pantalla según el boceto táctil. Se pasa explícito
  /// porque las rutas pusheadas con Navigator.push quedan FUERA del
  /// AppAdaptiveScope (vive debajo del Navigator, en el body del AppShell),
  /// así que el editor no puede leerlo con maybeOf por sí mismo.
  final bool wallLayout;

  @override
  State<RoutinesEditorPage> createState() => _RoutinesEditorPageState();
}

class _RoutinesEditorPageState extends State<RoutinesEditorPage> {
  int _step = 0;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  final _draft = _RoutineDraft();
  List<Map<String, dynamic>> _locationsView = [];
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _allRoutines = [];
  Map<String, bool> _modulesEnabled = {};

  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _activadorController = TextEditingController();
  String _activatorFeedback = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _activadorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        widget.api.deviceInventory(),
        widget.api.modules(),
      ]);
      final inventoryData = results[0] as Map<String, dynamic>;
      final modulesList = results[1] as List<Map<String, dynamic>>;
      // Directorio real de áreas (/api/v1/areas): el catálogo legacy trae
      // ids canónicos (area_<hex>) sin nombre legible, así que las pills
      // quedaban todas como «Área». Se carga tolerante: sin áreas igual se
      // puede editar, solo que las pills muestran el fallback.
      List<Map<String, dynamic>> areas = const [];
      try {
        areas = await widget.api.areas();
      } catch (_) {
        areas = const [];
      }
      // Rutinas existentes para «Ejecutar otra rutina». Tolerante: sin ellas
      // la tarjeta muestra su estado vacío en vez de romper el editor.
      List<Map<String, dynamic>> routines = const [];
      try {
        routines = await widget.api.routines();
      } catch (_) {
        routines = const [];
      }
      Map<String, dynamic>? routine;
      if (widget.routineId != null) {
        routine = await widget.api.routine(widget.routineId!);
      }
      if (!mounted) return;
      setState(() {
        // Vista ubicación→dispositivos proyectada del inventory en vez del
        // catálogo legacy: mismo contrato (`name`/`devices`/`capabilities`
        // en intents), con capabilities reales del endpoint.
        _locationsView = inventoryCatalogView(
          areas: areas,
          devices:
              (inventoryData['devices'] as List?) ?? const [],
        );
        _areas = areas;
        _allRoutines = routines;
        _modulesEnabled = {
          for (final m in modulesList)
            m['name'].toString(): m['enabled'] == true,
        };
        if (routine != null) {
          _draft.id = routine['id']?.toString();
          _draft.nombre = routine['nombre']?.toString() ?? '';
          _draft.descripcion = routine['descripcion']?.toString() ?? '';
          _draft.activadores.addAll(
            (routine['activadores'] as List?)?.cast<String>() ?? const [],
          );
          _draft.acciones.addAll(
            (routine['acciones'] as List?)?.cast<Map<String, dynamic>>() ??
                const [],
          );
          _nombreController.text = _draft.nombre;
          _descripcionController.text = _draft.descripcion;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool _stepHasError(int step) {
    if (step == 0) return _draft.acciones.isEmpty;
    if (step == 1) {
      return _draft.nombre.trim().isEmpty || _draft.activadores.isEmpty;
    }
    return _validate().isNotEmpty;
  }

  List<String> _validate() {
    final errors = <String>[];
    if (_draft.nombre.trim().isEmpty) {
      errors.add('Escribe un nombre para la rutina.');
    }
    if (_draft.activadores.isEmpty) {
      errors.add('Agrega al menos una frase de activación.');
    }
    if (_draft.acciones.isEmpty) {
      errors.add('Agrega al menos una acción.');
    }
    return errors;
  }

  void _navigateTo(int step) {
    if (step == _step || step < 0 || step >= _stepLabels.length) return;
    setState(() => _step = step);
  }

  Future<void> _addAction(String type) async {
    final enabler = moduleEnablers[type];
    final moduleIsOff = enabler != null && !(_modulesEnabled[enabler] ?? false);
    final sheet = _ActionConfigSheet(
      api: widget.api,
      type: type,
      locationsView: _locationsView,
      areas: _areas,
      routines: [
        for (final r in _allRoutines)
          if (r['id']?.toString() != _draft.id &&
              (r['nombre']?.toString().trim().isNotEmpty ?? false))
            r,
      ],
      existing: _draft.acciones,
      moduleIsOff: moduleIsOff,
    );
    final isDesktop = MediaQuery.sizeOf(context).width >= 700;
    final action = isDesktop
        ? await showGeneralDialog<Map<String, dynamic>>(
            context: context,
            barrierDismissible: true,
            barrierLabel: 'Cerrar configuración',
            barrierColor: Colors.black54,
            transitionDuration: const Duration(milliseconds: 220),
            transitionBuilder: (context, anim, _, child) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutCubic,
                ),
                child: child,
              ),
            ),
            pageBuilder: (dialogContext, _, _) {
              final mq = MediaQuery.sizeOf(dialogContext);
              return Center(
                child: SizedBox(
                  width: mq.width >= 1228 ? 1180 : mq.width - 48,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Material(color: Colors.transparent, child: sheet),
                  ),
                ),
              );
            },
          )
        : await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) => sheet,
          );
    if (action != null && mounted) {
      setState(() => _draft.acciones.add(action));
    }
  }

  Future<void> _save() async {
    if (_validate().isNotEmpty) return;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'nombre': _draft.nombre.trim(),
      'descripcion': _draft.descripcion.trim(),
      'activadores': _draft.activadores,
      'acciones': _draft.acciones,
    };
    try {
      if (_draft.id != null) {
        await widget.api.updateRoutine(_draft.id!, payload);
      } else {
        await widget.api.createRoutine(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: MessageView(
            message: _error!,
            onRetry: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
          ),
        ),
      );
    }
    // Superficie táctil / panel de pared: acomodo de una sola pantalla según
    // el boceto (formulario a la izquierda, resumen a la derecha). El wizard
    // de 3 pasos se conserva para móvil/desktop.
    final isWallPanel =
        widget.wallLayout ||
        (AppAdaptiveScope.maybeOf(context)?.isWallPanel ?? false);
    if (isWallPanel) return _buildWallEditor();
    // En móvil el botón de back se elimina: el gesto/botón back del sistema
    // ya hace Navigator.pop (el editor se abrió con push). Ahorra espacio en
    // el header, que queda solo con el indicador de pasos.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 20,
                compact ? 12 : 20,
                compact ? 16 : 20,
                compact ? 8 : 12,
              ),
              child: Row(
                children: [
                  if (!compact) ...[
                    ToolButton(
                      icon: CupertinoIcons.back,
                      label: 'Rutines',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(child: _buildStepIndicator(compact: compact)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: switch (_step) {
                    0 => _buildStepActions(),
                    1 => _buildStepDetails(),
                    _ => _buildStepReview(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Editor táctil / panel de pared (acomodo del boceto) -------------------
  // Una sola pantalla: encabezado con Guardar + dos columnas (formulario a la
  // izquierda, resumen "Tu rutina" a la derecha). Reusa el mismo draft,
  // validación, paleta y sheets que el wizard; solo cambia el acomodo y los
  // tamaños táctiles (>= 56dp). Estilo claro actual (AppColors).

  /// Orden de tarjetas del boceto: 2 columnas tal cual la referencia.
  /// `camera` queda fuera del panel como antes; las 4 nuevas sí entran.
  static const _wallPaletteOrder = [
    'device',
    'location',
    'music',
    'news',
    'climate',
    'wait',
    'announce',
    'runroutine',
  ];

  Widget _buildWallEditor() {
    final errors = _validate();
    final canSave = !_saving && errors.isEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const WallBackButton(),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                      boxShadow: const [_cardShadow],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _draft.id == null
                                      ? 'Nueva rutina'
                                      : 'Editar rutina',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.02,
                                  ),
                                ),
                              ),
                              _primaryButton(
                                label: _saving
                                    ? 'Guardando…'
                                    : 'Guardar rutina',
                                onTap: canSave ? _save : null,
                                height: 56,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: _border),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final left = _wallFormColumn();
                            final right = _wallSummaryColumn();
                            if (constraints.maxWidth < 760) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      20,
                                      24,
                                      8,
                                    ),
                                    child: left,
                                  ),
                                  const Divider(height: 1, color: _border),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      20,
                                      24,
                                      24,
                                    ),
                                    child: right,
                                  ),
                                ],
                              );
                            }
                            // Sin IntrinsicHeight ni Row+stretch a propósito: con la
                            // altura no acotada del scroll ambos revientan
                            // ("forces an infinite height" / pantalla en
                            // blanco). La Table mide sus filas por contenido y
                            // la celda fill estira el divisor al alto real.
                            return Table(
                              columnWidths: const {
                                0: FlexColumnWidth(),
                                1: FixedColumnWidth(1),
                                2: FlexColumnWidth(),
                              },
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.top,
                              children: [
                                TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        20,
                                        24,
                                        24,
                                      ),
                                      child: left,
                                    ),
                                    const TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.fill,
                                      child: ColoredBox(color: _border),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        20,
                                        24,
                                        24,
                                      ),
                                      child: right,
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final e in errors)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(
                          e,
                          style: const TextStyle(fontSize: 13, color: _danger),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wallFormColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wallLabel('Nombre'),
        SizedBox(
          height: 64,
          child: TextField(
            controller: _nombreController,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            onChanged: (_) =>
                setState(() => _draft.nombre = _nombreController.text),
            decoration: _decoration(hint: 'Ej: Buenos días'),
          ),
        ),
        const SizedBox(height: 20),
        _wallLabel('Frase para activarla'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 64,
                child: TextField(
                  controller: _activadorController,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addActivator(_activadorController.text),
                  decoration: _decoration(hint: 'Escribe una frase'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              height: 64,
              child: Material(
                color: _accent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => _addActivator(_activadorController.text),
                  borderRadius: BorderRadius.circular(14),
                  child: const Icon(
                    CupertinoIcons.add,
                    size: 28,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _activatorTags(),
        if (_activatorFeedback.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _activatorFeedback,
            style: const TextStyle(fontSize: 13, color: AppColors.amber),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          '¿Qué quieres agregar?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 132,
          ),
          children: [for (final type in _wallPaletteOrder) _wallAddTile(type)],
        ),
      ],
    );
  }

  Widget _wallAddTile(String type) {
    final meta = routineCategories[type]!;
    final enabler = moduleEnablers[type];
    final isOff = enabler != null && !(_modulesEnabled[enabler] ?? false);
    return Opacity(
      opacity: isOff ? 0.5 : 1,
      child: Material(
        color: _softFill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _addAction(type),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(meta.icon, size: 26, color: _accent),
                const SizedBox(height: 10),
                Text(
                  meta.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wallSummaryColumn() {
    final triggers = _draft.activadores.isNotEmpty
        ? _draft.activadores
        : [if (_draft.nombre.trim().isNotEmpty) _draft.nombre.trim()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tu rutina',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Así se activará y esto hará, en orden.',
          style: TextStyle(fontSize: 14, color: _dimCap),
        ),
        const SizedBox(height: 20),
        const Text(
          'Para activarla, di',
          style: TextStyle(fontSize: 14, color: _dimText),
        ),
        const SizedBox(height: 6),
        if (triggers.isEmpty)
          const Text(
            '—',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final trigger in triggers)
                Text(
                  '“$trigger”',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 20),
        const Text(
          'Tu rutina hará',
          style: TextStyle(fontSize: 14, color: _dimText),
        ),
        const SizedBox(height: 10),
        if (_draft.acciones.isEmpty)
          const Text(
            'Todavía no agregaste acciones. Tocá una tarjeta de la izquierda.',
            style: TextStyle(fontSize: 14, color: _dimCap),
          )
        else
          for (var i = 0; i < _draft.acciones.length; i++)
            _wallSummaryRow(i, _draft.acciones[i]),
      ],
    );
  }

  Widget _wallSummaryRow(int index, Map<String, dynamic> action) {
    final category = actionCategory(action);
    final label = routineCategories[category]?.label ?? actionSummary(action);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _softFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: InkWell(
              onTap: () => setState(() => _draft.acciones.removeAt(index)),
              customBorder: const CircleBorder(),
              child: const Icon(CupertinoIcons.trash, size: 22, color: _dimCap),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wallLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, color: _dimText)),
    );
  }

  Widget _buildStepIndicator({bool compact = false}) {
    return Row(
      children: [
        for (var i = 0; i < _stepLabels.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
              child: Icon(
                CupertinoIcons.chevron_right,
                size: compact ? 14 : 18,
                color: _dimCap,
              ),
            ),
          Expanded(
            child: _StepPill(
              number: i + 1,
              label: _stepLabels[i],
              active: i == _step,
              hasError: _stepHasError(i) && i != _step,
              compact: compact,
              onTap: () => _navigateTo(i),
            ),
          ),
        ],
      ],
    );
  }

  String _countLabel() {
    final n = _draft.acciones.length;
    return '$n ${n == 1 ? 'acción' : 'acciones'}';
  }

  // --- Paso 1: Acciones ------------------------------------------------------

  Widget _buildStepActions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _sectionHead('Tu secuencia', _countLabel()),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
            boxShadow: const [_cardShadow],
          ),
          clipBehavior: Clip.antiAlias,
          child: _draft.acciones.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Tu secuencia está vacía. Toca una tarjeta de abajo para empezar.',
                    style: TextStyle(fontSize: 13, color: _dimCap),
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  // Sin el Material elevado por defecto: el item arrastrado
                  // se ve igual que en la lista (sin container flotante).
                  proxyDecorator: (child, index, animation) => child,
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  itemCount: _draft.acciones.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = _draft.acciones.removeAt(oldIndex);
                      _draft.acciones.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) => _ActionRow(
                    // ObjectKey (identidad del Map) en vez de ValueKey(index):
                    // al reordenar/borrar, los items no se reconstruyen todos,
                    // solo se mueve el que cambió. El index como key fuerza
                    // rebuild completo de la lista en cada interacción.
                    key: ObjectKey(_draft.acciones[index]),
                    index: index,
                    action: _draft.acciones[index],
                    onDelete: () {
                      setState(() => _draft.acciones.removeAt(index));
                    },
                  ),
                ),
        ),
        const SizedBox(height: 22),
        _sectionHead(
          '¿Qué quieres agregar?',
          'Toca una tarjeta para configurarla',
        ),
        const SizedBox(height: 6),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 215,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Altura por contenido, no por ancho: igual que en dispositivos,
            // el aspectRatio deja celdas chicas en móvil y la card desborda.
            mainAxisExtent: MediaQuery.textScalerOf(context).scale(172),
          ),
          children: [
            for (final type in paletteCategoryOrder) _paletteCard(type),
          ],
        ),
        const SizedBox(height: 20),
        _stepNav(
          back: null,
          onBack: null,
          forwardLabel: 'Siguiente',
          forwardEnabled: _draft.acciones.isNotEmpty,
          onForward: () => _navigateTo(1),
          hint: _draft.acciones.isEmpty
              ? 'Agrega al menos una acción para continuar.'
              : '',
        ),
      ],
    );
  }

  Widget _paletteCard(String type) {
    final meta = routineCategories[type]!;
    final enabler = moduleEnablers[type];
    final isOff = enabler != null && !(_modulesEnabled[enabler] ?? false);
    return Opacity(
      opacity: isOff ? 0.5 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _addAction(type),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [_cardShadow],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(meta.icon, size: 20, color: _accent),
                ),
                const Spacer(),
                Text(
                  meta.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: _dimText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHead(String title, String trailing) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Text(trailing, style: const TextStyle(fontSize: 13, color: _dimText)),
        ],
      ),
    );
  }

  // --- Paso 2: Detalles ------------------------------------------------------

  Widget _buildStepDetails() {
    final noName = _draft.nombre.trim().isEmpty;
    final noTrigger = _draft.activadores.isEmpty;
    final String hint;
    if (noName && noTrigger) {
      hint = 'Escribe un nombre y agrega una frase.';
    } else if (noName) {
      hint = 'Escribe un nombre.';
    } else if (noTrigger) {
      hint = 'Agrega al menos una frase.';
    } else {
      hint = '';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
            boxShadow: const [_cardShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configura los detalles de tu rutina',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final left = _columnLeft();
                  final right = _columnRight();
                  if (constraints.maxWidth < 720) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [left, const SizedBox(height: 24), right],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: left),
                      const SizedBox(width: 28),
                      Expanded(flex: 6, child: right),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _stepNav(
          back: 'Anterior',
          onBack: () => _navigateTo(0),
          forwardLabel: 'Siguiente',
          forwardEnabled: !noName && !noTrigger,
          onForward: () => _navigateTo(2),
          hint: hint,
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        optional ? '$text (opcional)' : text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _dimCap,
        ),
      ),
    );
  }

  InputDecoration _decoration({String hint = '', String counterText = ''}) {
    return InputDecoration(
      hintText: hint,
      counterText: counterText,
      filled: true,
      fillColor: AppColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accent, width: 1.4),
      ),
    );
  }

  Widget _columnLeft() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Nombre'),
        SizedBox(
          height: 64,
          child: TextField(
            controller: _nombreController,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            onChanged: (_) =>
                setState(() => _draft.nombre = _nombreController.text),
            decoration: _decoration(hint: 'Ej: Buenos días'),
          ),
        ),
        const SizedBox(height: 18),
        _fieldLabel('Descripción', optional: true),
        TextField(
          controller: _descripcionController,
          maxLength: 200,
          maxLines: 3,
          onChanged: (_) =>
              setState(() => _draft.descripcion = _descripcionController.text),
          decoration: _decoration(hint: 'Opcional'),
        ),
      ],
    );
  }

  Widget _columnRight() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Frases para activarla'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 64,
                child: TextField(
                  controller: _activadorController,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addActivator(_activadorController.text),
                  decoration: _decoration(hint: 'Escribe una frase'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _primaryButton(
              label: 'Agregar',
              onTap: () => _addActivator(_activadorController.text),
              height: 64,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _activatorTags(),
        if (_activatorFeedback.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _activatorFeedback,
            style: const TextStyle(fontSize: 12, color: AppColors.amber),
          ),
        ],
      ],
    );
  }

  /// Sugeridas de la referencia: un tap las agrega como frase (sin duplicar).
  static const _suggestedPhrases = ['Hola casa', 'Arriba'];

  Widget _activatorTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Frases que activan la rutina',
          style: TextStyle(fontSize: 12, color: _dimCap),
        ),
        if (_draft.activadores.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _draft.activadores.length; i++)
                _activatorTag(i, _draft.activadores[i]),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text(
              'Sugeridas:',
              style: TextStyle(fontSize: 12, color: _dimCap),
            ),
            for (final suggestion in _suggestedPhrases)
              _suggestionPill(suggestion),
          ],
        ),
      ],
    );
  }

  Widget _activatorTag(int index, String text) {
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '«$text»',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.accentStrong,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            height: 32,
            child: InkWell(
              onTap: () => setState(() => _draft.activadores.removeAt(index)),
              customBorder: const CircleBorder(),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  size: 14,
                  color: _dimCap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionPill(String text) {
    final added = _draft.activadores.any(
      (t) => t.toLowerCase() == text.toLowerCase(),
    );
    return InkWell(
      onTap: added ? null : () => _addActivator(text),
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: added ? 0.45 : 1,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _border),
          ),
          alignment: Alignment.center,
          child: Text(
            '«$text»',
            style: const TextStyle(fontSize: 13, color: _dimText),
          ),
        ),
      ),
    );
  }

  void _addActivator(String raw) {
    final value = raw.trim();
    setState(() {
      if (value.isEmpty) {
        _activatorFeedback = '';
        return;
      }
      if (_draft.activadores.any(
        (t) => t.toLowerCase() == value.toLowerCase(),
      )) {
        _activatorFeedback = '«$value» ya está agregada.';
        return;
      }
      _activatorFeedback = '';
      _activadorController.clear();
      _draft.activadores.add(value);
    });
  }

  // --- Paso 3: Revisar -------------------------------------------------------

  Widget _buildStepReview() {
    final name = _draft.nombre.trim().isEmpty
        ? 'Tu rutina'
        : _draft.nombre.trim();
    final errors = _validate();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
            boxShadow: const [_cardShadow],
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
                    child: Icon(
                      CupertinoIcons.sparkles,
                      size: 27,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Así la activarás y lo que hará en orden.',
                style: TextStyle(fontSize: 13, color: _dimCap),
              ),
              const SizedBox(height: 20),
              _reviewBlock(
                title: 'Para activarla, di',
                child: _draft.activadores.isEmpty
                    ? const Text(
                        'Aún no has agregado frases de activación.',
                        style: TextStyle(fontSize: 13, color: _dimCap),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in _draft.activadores) _reviewTrigger(t),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              _reviewBlock(
                title: 'Tu rutina hará',
                child: _draft.acciones.isEmpty
                    ? const Text(
                        'Aún no has agregado acciones.',
                        style: TextStyle(fontSize: 13, color: _dimCap),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < _draft.acciones.length; i++)
                            _reviewAction(i, _draft.acciones[i]),
                        ],
                      ),
              ),
              if (_draft.acciones.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Se ejecutarán las ${_draft.acciones.length} acciones en este orden.',
                  style: const TextStyle(fontSize: 12, color: _dimCap),
                ),
              ],
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      e,
                      style: const TextStyle(fontSize: 12, color: _danger),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _stepNav(
          back: 'Anterior',
          onBack: () => _navigateTo(1),
          forwardLabel: _saving ? 'Guardando…' : 'Guardar rutina',
          forwardEnabled: !_saving && errors.isEmpty,
          onForward: _save,
          hint: '',
        ),
      ],
    );
  }

  Widget _reviewTrigger(String text) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _softFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.mic, size: 16, color: _dimCap),
          const SizedBox(width: 6),
          Text(
            '«$text»',
            style: const TextStyle(fontSize: 13, color: _dimText),
          ),
        ],
      ),
    );
  }

  Widget _reviewAction(int index, Map<String, dynamic> action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(actionIcon(action), size: 21, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionSummary(action),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  actionSub(action),
                  style: const TextStyle(fontSize: 12, color: _dimText),
                ),
              ],
            ),
          ),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewBlock({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _dimCap,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  // --- Piezas compartidas ----------------------------------------------------

  Row _stepNav({
    required String? back,
    required VoidCallback? onBack,
    required String forwardLabel,
    required bool forwardEnabled,
    required VoidCallback onForward,
    required String hint,
  }) {
    return Row(
      children: [
        if (back != null) ...[
          _outlineButton(label: back, onTap: onBack!, height: 56),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            hint,
            style: const TextStyle(fontSize: 12, color: _dimCap),
          ),
        ),
        _primaryButton(
          label: forwardLabel,
          onTap: forwardEnabled ? onForward : null,
          height: 56,
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
    double height = 56,
  }) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SizedBox(
        height: height,
        child: Material(
          color: _accent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    required VoidCallback onTap,
    double height = 56,
  }) {
    return SizedBox(
      height: height,
      child: Material(
        color: _softFill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutineDraft {
  String? id;
  String nombre = '';
  String descripcion = '';
  final List<String> activadores = [];
  final List<Map<String, dynamic>> acciones = [];
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.index,
    required this.action,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> action;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(actionIcon(action), size: 19, color: _accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            actionSummary(action),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            actionSub(action),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _dimText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: InkWell(
              onTap: onDelete,
              customBorder: const CircleBorder(),
              child: const Icon(CupertinoIcons.trash, size: 20, color: _dimCap),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.number,
    required this.label,
    required this.active,
    required this.hasError,
    required this.onTap,
    this.compact = false,
  });

  final int number;
  final String label;
  final bool active;
  final bool hasError;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(
            height: compact ? 44 : 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _accent : AppColors.accentTint,
              borderRadius: BorderRadius.circular(999),
              border: active ? null : Border.all(color: _border),
            ),
            child: Text(
              '$number $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : _dimText,
              ),
            ),
          ),
          if (hasError)
            Positioned(
              top: compact ? 7 : 9,
              right: compact ? 9 : 12,
              child: const SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionConfigSheet extends StatefulWidget {
  const _ActionConfigSheet({
    required this.api,
    required this.type,
    required this.locationsView,
    required this.areas,
    required this.routines,
    required this.existing,
    required this.moduleIsOff,
  });

  final ApiClient api;
  final String type;
  final List<Map<String, dynamic>> locationsView;
  final List<Map<String, dynamic>> areas;

  /// Rutinas encadenables (ya sin la que se está editando).
  final List<Map<String, dynamic>> routines;
  final List<Map<String, dynamic>> existing;
  final bool moduleIsOff;

  @override
  State<_ActionConfigSheet> createState() => _ActionConfigSheetState();
}

class _ActionConfigSheetState extends State<_ActionConfigSheet> {
  String? _location;
  String? _device;
  String? _intent;
  double _value = 50;

  bool _house = true;
  String _op = 'play';
  String _cameraOp = 'snapshot';
  double _volume = 50;

  // Ajustar clima.
  String? _climateLocation;
  bool _climateAll = true;
  String _climateMode = 'cool';
  double _climateTemp = 22;

  // Esperar.
  int _waitValue = 5;
  String _waitUnit = 'min';

  // Anuncio de voz.
  String _announceTarget = 'house';
  final _announceController = TextEditingController();

  // Ejecutar otra rutina.
  String? _runRoutineId;

  Map<String, dynamic>? _spot;
  final _searchController = TextEditingController();
  Map<String, List<Map<String, dynamic>>>? _results;
  bool _searching = false;
  String? _searchError;
  Timer? _debounce;

  String _filter = 'all';
  List<Map<String, dynamic>>? _myPlaylists;
  bool _playlistsLoading = false;
  String? _playlistsError;

  final _cameraController = TextEditingController();
  String _feedback = '';
  List<Map<String, String>>? _conflicts;
  Map<String, dynamic>? _pending;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _cameraController.dispose();
    _announceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = routineCategories[widget.type]!;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: _conflicts != null
                ? _conflictBody(meta)
                : (widget.moduleIsOff
                      ? _moduleOffBody(meta)
                      : _configBody(meta)),
          ),
        ),
      ),
    );
  }

  Widget _moduleOffBody(RoutineCategory meta) {
    final moduleName = _moduleNames[moduleEnablers[widget.type]] ?? meta.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetHeader(meta),
        const SizedBox(height: 16),
        Text(
          'El módulo de $moduleName está apagado. Actívalo en Ajustes para usar esta tarjeta.',
          style: const TextStyle(fontSize: 13, height: 1.5, color: _dimText),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: _sheetButton(
            label: 'Entendido',
            filled: true,
            onTap: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }

  Widget _conflictBody(RoutineCategory meta) {
    final conflicts = _conflicts!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetHeader(meta),
        const SizedBox(height: 14),
        const Text(
          'Acciones contrarias',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Esta acción contradice otra de la secuencia. Puedes agregarla de todos modos.',
          style: TextStyle(fontSize: 13, height: 1.4, color: _dimText),
        ),
        const SizedBox(height: 12),
        for (final conflict in conflicts.take(3))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${conflict['index']}. ${conflict['label']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  conflict['reason'] ?? '',
                  style: const TextStyle(fontSize: 12, color: _danger),
                ),
              ],
            ),
          ),
        if (conflicts.length > 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Y ${conflicts.length - 3} '
              '${conflicts.length - 3 == 1 ? 'conflicto más' : 'conflictos más'}.',
              style: const TextStyle(fontSize: 12, color: _dimCap),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text.rich(
            TextSpan(
              text: 'Se agregará: ',
              style: const TextStyle(fontSize: 13, color: _dimText),
              children: [
                TextSpan(
                  text: actionSummary(_pending!),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _sheetButton(
                label: 'Volver',
                filled: false,
                onTap: () {
                  setState(() {
                    _conflicts = null;
                    _pending = null;
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _sheetButton(
                label: 'Agregar de todos modos',
                filled: true,
                onTap: () => Navigator.pop(context, _pending),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _configBody(RoutineCategory meta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetHeader(meta),
        const SizedBox(height: 14),
        switch (meta.name) {
          'device' => _deviceConfig(),
          'location' => _locationConfig(),
          'music' => _musicConfig(),
          'news' => const Text(
            'Al ejecutarse la rutina, GAMMA leerá las noticias del día.',
            style: TextStyle(fontSize: 13, height: 1.5, color: _dimText),
          ),
          'camera' => _cameraConfig(),
          'climate' => _climateConfig(),
          'wait' => _waitConfig(),
          'announce' => _announceConfig(),
          'runroutine' => _runRoutineConfig(),
          _ => const SizedBox.shrink(),
        },
        if (_feedback.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_feedback, style: const TextStyle(fontSize: 12, color: _danger)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _sheetButton(
                label: 'Cancelar',
                filled: false,
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _sheetButton(
                label: 'Agregar a la secuencia',
                filled: true,
                onTap: _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sheetHeader(RoutineCategory meta) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(meta.icon, size: 20, color: _accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            meta.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(CupertinoIcons.xmark, color: _dimText),
          ),
        ),
      ],
    );
  }

  /// Nombre legible del área: el directorio real (/api/v1/areas) manda;
  /// el catálogo legacy solo trae ids canónicos `area_hex` que sin esto
  /// quedaban todos como «Área».
  String _areaLabel(String id) {
    for (final area in widget.areas) {
      if (area['id']?.toString() == id) {
        final name = area['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    return formatLocationName(id);
  }

  /// Opciones de ubicación: unión del catálogo (tiene dispositivos) con el
  /// directorio real de áreas (tiene los nombres). Sin catálogo igual se
  /// ofrecen las áreas para «Una ubicación»; para «Controla un dispositivo»
  /// el paso 2 avisará si el área no tiene dispositivos.
  List<({String id, String label, bool hasDevices})> _locationOptions() {
    final options = <({String id, String label, bool hasDevices})>[];
    final seen = <String>{};
    for (final location in widget.locationsView) {
      final id = location['name']?.toString() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      options.add((id: id, label: _areaLabel(id), hasDevices: true));
    }
    for (final area in widget.areas) {
      final id = area['id']?.toString() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      final name = area['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      options.add((id: id, label: name, hasDevices: false));
    }
    return options;
  }

  Widget _deviceConfig() {
    final options = _locationOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Ubicación'),
        if (options.isEmpty)
          const Text(
            'No hay áreas todavía. Crealas en Áreas para usarlas aquí.',
            style: TextStyle(fontSize: 13, height: 1.5, color: _dimText),
          )
        else
          _pillWrap(
            children: [
              for (final option in options)
                _pill(
                  label: option.label,
                  selected: _location == option.id,
                  onTap: () => _selectLocation(option.id),
                ),
            ],
          ),
        if (_location != null && _devices().isNotEmpty) ...[
          const SizedBox(height: 16),
          _stepLabel('2. Dispositivo'),
          _pillWrap(
            children: [
              for (final device in _devices())
                _pill(
                  label: formatDeviceName(device['id'].toString()),
                  selected: _device == device['id'],
                  onTap: () => setState(() {
                    _device = device['id'].toString();
                    _intent = null;
                    _feedback = '';
                  }),
                ),
            ],
          ),
        ],
        if (_device != null) ...[
          const SizedBox(height: 16),
          _stepLabel('3. Acción'),
          _pillWrap(
            children: [
              for (final cap in _capabilities())
                _pill(
                  label: intentLabels[cap] ?? cap,
                  selected: _intent == cap,
                  onTap: () => setState(() {
                    _intent = cap;
                    _feedback = '';
                  }),
                ),
            ],
          ),
          if (_intent == 'SET_VALUE') ...[
            const SizedBox(height: 16),
            _stepLabel('Nivel'),
            _valueSlider(
              value: _value,
              onChanged: (v) => setState(() => _value = v.roundToDouble()),
            ),
          ],
        ],
        _selectionSummary(),
      ],
    );
  }

  Widget _selectionSummary() {
    if (_location == null) return const SizedBox.shrink();
    if (_devices().isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          '«${_areaLabel(_location!)}» todavía no tiene dispositivos.',
          style: const TextStyle(fontSize: 13, color: _dimText),
        ),
      );
    }
    if (_device == null || _intent == null) {
      return const SizedBox.shrink();
    }
    final text =
        '${formatDeviceName(_device!)} · '
        '${_areaLabel(_location!)} · '
        '${intentLabels[_intent] ?? _intent}'
        '${_intent == 'SET_VALUE' ? ' · ${_value.round()}%' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _locationConfig() {
    final options = _locationOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Ubicación'),
        if (options.isEmpty)
          const Text(
            'No hay áreas todavía. Crealas en Áreas para usarlas aquí.',
            style: TextStyle(fontSize: 13, height: 1.5, color: _dimText),
          )
        else
          _pillWrap(
            children: [
              _pill(
                label: 'Toda la casa',
                selected: _house,
                onTap: () => setState(() {
                  _house = true;
                  _location = null;
                  _feedback = '';
                }),
              ),
              for (final option in options)
                _pill(
                  label: option.label,
                  selected: !_house && _location == option.id,
                  onTap: () => setState(() {
                    _house = false;
                    _location = option.id;
                    _feedback = '';
                  }),
                ),
            ],
          ),
        const SizedBox(height: 16),
        _stepLabel('2. Acción'),
        _pillWrap(
          children: [
            for (final intent in const ['TURN_ON', 'TURN_OFF'])
              _pill(
                label: intent == 'TURN_ON' ? 'Enciende todo' : 'Apaga todo',
                selected: _intent == intent,
                onTap: () => setState(() {
                  _intent = intent;
                  _feedback = '';
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _musicConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Acción'),
        _pillWrap(
          children: [
            for (final op in const [
              'play',
              'pause',
              'next',
              'previous',
              'volume',
            ])
              _pill(
                label: switch (op) {
                  'play' => 'Reproduce',
                  'pause' => 'Pausa',
                  'next' => 'Siguiente',
                  'previous' => 'Anterior',
                  _ => 'Volumen',
                },
                icon: switch (op) {
                  'play' => CupertinoIcons.play_fill,
                  'pause' => CupertinoIcons.pause_fill,
                  'next' => CupertinoIcons.forward_end_fill,
                  'previous' => CupertinoIcons.backward_end_fill,
                  _ => CupertinoIcons.volume_up,
                },
                selected: _op == op,
                onTap: () => setState(() {
                  _op = op;
                  _feedback = '';
                }),
              ),
          ],
        ),
        if (_op == 'play') ...[
          const SizedBox(height: 16),
          _stepLabel('2. Detalles'),
          _searchArea(),
        ],
        if (_op == 'volume') ...[
          const SizedBox(height: 16),
          _stepLabel('2. Detalles'),
          _stepLabel('Volumen'),
          _valueSlider(
            value: _volume,
            onChanged: (v) => setState(() => _volume = v.roundToDouble()),
          ),
        ],
      ],
    );
  }

  Widget _cameraConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Acción'),
        _pillWrap(
          children: [
            for (final op in const ['snapshot', 'status', 'events'])
              _pill(
                label: switch (op) {
                  'snapshot' => 'Tomar foto',
                  'status' => 'Estado',
                  _ => 'Eventos',
                },
                selected: _cameraOp == op,
                onTap: () => setState(() {
                  _cameraOp = op;
                  _feedback = '';
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _stepLabel('2. Cámara'),
        SizedBox(
          height: 64,
          child: TextField(
            controller: _cameraController,
            maxLength: 80,
            onChanged: (_) {
              if (_feedback.isNotEmpty) setState(() => _feedback = '');
            },
            decoration: _decoration(hint: 'Ej: camara patio'),
          ),
        ),
      ],
    );
  }

  String _climateModeLabel(String mode) => switch (mode) {
    'heat' => 'Calor',
    'off' => 'Apagar',
    _ => 'Frío',
  };

  String _climateZoneLabel() {
    if (_climateAll) return 'Toda la casa';
    if (_climateLocation == null) return '—';
    return _areaLabel(_climateLocation!);
  }

  Widget _climateConfig() {
    final options = _locationOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Ubicación'),
        if (options.isEmpty)
          const Text(
            'No hay áreas todavía. Crealas en Áreas para usarlas aquí.',
            style: TextStyle(fontSize: 13, height: 1.5, color: _dimText),
          )
        else
          _pillWrap(
            children: [
              _pill(
                label: 'Toda la casa',
                selected: _climateAll,
                onTap: () => setState(() {
                  _climateAll = true;
                  _climateLocation = null;
                  _feedback = '';
                }),
              ),
              for (final option in options)
                _pill(
                  label: option.label,
                  selected: !_climateAll && _climateLocation == option.id,
                  onTap: () => setState(() {
                    _climateAll = false;
                    _climateLocation = option.id;
                    _feedback = '';
                  }),
                ),
            ],
          ),
        const SizedBox(height: 16),
        _stepLabel('2. Modo'),
        _pillWrap(
          children: [
            for (final mode in const ['cool', 'heat', 'off'])
              _pill(
                label: _climateModeLabel(mode),
                selected: _climateMode == mode,
                onTap: () => setState(() {
                  _climateMode = mode;
                  _feedback = '';
                }),
              ),
          ],
        ),
        if (_climateMode != 'off') ...[
          const SizedBox(height: 16),
          _stepLabel('3. Temperatura'),
          _stepper(
            center: '${_climateTemp.round()}°C',
            onMinus: () => setState(() {
              if (_climateTemp > 16) _climateTemp -= 1;
            }),
            onPlus: () => setState(() {
              if (_climateTemp < 30) _climateTemp += 1;
            }),
          ),
        ],
        _configSummary(
          _climateMode == 'off'
              ? '${_climateZoneLabel()} · Apagar'
              : '${_climateZoneLabel()} · ${_climateModeLabel(_climateMode)} · ${_climateTemp.round()}°C',
        ),
      ],
    );
  }

  String _waitUnitLabel(String unit) => unit == 's' ? 'Segundos' : 'Minutos';

  int get _waitMax => _waitUnit == 's' ? 300 : 60;

  Widget _waitConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Duración'),
        _stepper(
          center: _waitUnit == 's' ? '$_waitValue s' : '$_waitValue min',
          onMinus: () => setState(() {
            if (_waitValue > 1) _waitValue -= 1;
          }),
          onPlus: () => setState(() {
            if (_waitValue < _waitMax) _waitValue += 1;
          }),
        ),
        const SizedBox(height: 16),
        _stepLabel('2. Unidad'),
        _pillWrap(
          children: [
            for (final unit in const ['s', 'min'])
              _pill(
                label: _waitUnitLabel(unit),
                selected: _waitUnit == unit,
                onTap: () => setState(() {
                  _waitUnit = unit;
                  if (_waitValue > _waitMax) _waitValue = _waitMax;
                  _feedback = '';
                }),
              ),
          ],
        ),
        _configSummary(
          'Esperar $_waitValue ${_waitUnit == 's' ? 'segundos' : 'minutos'}',
        ),
      ],
    );
  }

  Widget _announceConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Dónde anunciar'),
        _pillWrap(
          children: [
            _pill(
              label: 'Toda la casa',
              selected: _announceTarget == 'house',
              onTap: () => setState(() {
                _announceTarget = 'house';
                _feedback = '';
              }),
            ),
            _pill(
              label: 'Mi teléfono',
              selected: _announceTarget == 'phone',
              onTap: () => setState(() {
                _announceTarget = 'phone';
                _feedback = '';
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _stepLabel('2. Mensaje'),
        TextField(
          controller: _announceController,
          maxLength: 200,
          maxLines: 2,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_feedback.isNotEmpty) setState(() => _feedback = '');
          },
          decoration: _decoration(hint: 'La comida está lista'),
        ),
        _configSummary(
          _announceController.text.trim().isEmpty
              ? 'Escribe el mensaje que dirá GAMMA.'
              : 'Anuncia: «${_announceController.text.trim()}»',
        ),
      ],
    );
  }

  Widget _runRoutineConfig() {
    if (widget.routines.isEmpty) {
      return const Text(
        'Todavía no tienes otra rutina para encadenar. Guarda esta y crea una más.',
        style: TextStyle(fontSize: 13, height: 1.5, color: _dimText),
      );
    }
    String selectedName = '';
    for (final r in widget.routines) {
      if (r['id']?.toString() == _runRoutineId) {
        selectedName = r['nombre']?.toString() ?? '';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepLabel('1. Rutina'),
        _pillWrap(
          children: [
            for (final r in widget.routines)
              _pill(
                label: r['nombre']?.toString() ?? '',
                selected: _runRoutineId == r['id']?.toString(),
                onTap: () => setState(() {
                  _runRoutineId = r['id']?.toString();
                  _feedback = '';
                }),
              ),
          ],
        ),
        _configSummary(
          selectedName.isEmpty
              ? 'Elige qué rutina se ejecutará.'
              : 'Ejecuta la rutina «$selectedName»',
        ),
      ],
    );
  }

  /// Cajita de resumen gris como la referencia («Recámara · Frío · 22°C»).
  Widget _configSummary(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _softFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Stepper − valor + en contenedor redondeado, como la referencia.
  Widget _stepper({
    required String center,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    Widget circle(IconData icon, VoidCallback onTap) {
      return SizedBox(
        width: 56,
        height: 56,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(side: BorderSide(color: _border)),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Icon(icon, size: 22, color: _dimText),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _softFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          circle(CupertinoIcons.minus, onMinus),
          Expanded(
            child: Text(
              center,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          circle(CupertinoIcons.add, onPlus),
        ],
      ),
    );
  }

  void _selectLocation(String name) {
    setState(() {
      _location = name;
      _device = null;
      _intent = null;
      _feedback = '';
    });
  }

  List<Map<String, dynamic>> _devices() {
    for (final location in widget.locationsView) {
      if (location['name'] == _location) {
        return (location['devices'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
      }
    }
    return const [];
  }

  List<String> _capabilities() {
    return deviceCapabilities(_location!, _device!, widget.locationsView);
  }

  // --- Búsqueda de Spotify ---------------------------------------------------

  Widget _searchArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _searchBox(),
        const SizedBox(height: 10),
        _filterPills(),
        const SizedBox(height: 12),
        ..._searchBody(),
      ],
    );
  }

  Widget _searchBox() {
    return SizedBox(
      height: 64,
      child: TextField(
        controller: _searchController,
        maxLength: 120,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Canción, artista o playlist',
          counterText: '',
          filled: true,
          fillColor: AppColors.surfaceRaised,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          prefixIcon: const Icon(
            CupertinoIcons.search,
            size: 22,
            color: _dimCap,
          ),
          // ListenableBuilder: solo este icono se reconstruye al escribir,
          // no todo el modal (evita el lag de rebuild por tecla).
          suffixIcon: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) => _searchController.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(
                      CupertinoIcons.xmark,
                      size: 18,
                      color: _dimText,
                    ),
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _searchController.clear();
                      _onQueryChanged('');
                    },
                  ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _accent, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _filterPills() {
    const filters = [
      ('all', 'Todo'),
      ('track', 'Canciones'),
      ('artist', 'Artistas'),
      ('playlist', 'Playlists'),
      ('mine', 'Mis playlists'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in filters) _filterPill(value, label),
      ],
    );
  }

  Widget _filterPill(String value, String label) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => _selectFilter(value),
      borderRadius: BorderRadius.circular(999),
      child: IntrinsicWidth(
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected ? _accent : _softFill,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: _border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _dimText,
            ),
          ),
        ),
      ),
    );
  }

  void _selectFilter(String value) {
    setState(() => _filter = value);
    if (value == 'mine' &&
        _myPlaylists == null &&
        _playlistsError == null &&
        !_playlistsLoading) {
      setState(() => _playlistsLoading = true);
      _loadMyPlaylists();
    }
  }

  Future<void> _loadMyPlaylists() async {
    try {
      final data = await widget.api.spotifyPlaylists();
      if (!mounted) return;
      setState(() {
        _myPlaylists =
            (data['playlists'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        _playlistsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      var message = e.toString();
      if (e.body is Map && (e.body as Map)['detail'] != null) {
        message = (e.body as Map)['detail'].toString();
      }
      setState(() {
        _playlistsError = message;
        _playlistsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playlistsError = e.toString();
        _playlistsLoading = false;
      });
    }
  }

  List<Widget> _searchBody() {
    if (_filter == 'mine') return _mineBody();
    if (_searchError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _searchError!,
            style: const TextStyle(fontSize: 12, color: _danger),
          ),
        ),
      ];
    }
    if (_searching) {
      // Skeleton que imita las filas de resultados: el contenido real
      // reemplaza estos placeholders cuando llega, sin aparecer de golpe.
      return const [
        _SkeletonStrip(height: 160, cardWidth: 110),
        SizedBox(height: 22),
        _SkeletonStrip(height: 225, cardWidth: 130, circle: true),
      ];
    }
    if (_results == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Escribe al menos 2 letras para buscar qué reproducir.',
            style: TextStyle(fontSize: 12, color: _dimCap),
          ),
        ),
      ];
    }
    if (_flat().isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Sin resultados para «${_searchController.text.trim()}». '
            'Revisa la ortografía o prueba con otro nombre.',
            style: const TextStyle(fontSize: 12, color: _dimCap),
          ),
        ),
      ];
    }
    return _resultSections();
  }

  List<Widget> _mineBody() {
    if (_playlistsError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _playlistsError!,
            style: const TextStyle(fontSize: 12, color: _danger),
          ),
        ),
      ];
    }
    if (_playlistsLoading || _myPlaylists == null) {
      return const [_SkeletonStrip(height: 225, cardWidth: 140)];
    }
    if (_myPlaylists!.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No se encontraron playlists en tu cuenta conectada.',
            style: TextStyle(fontSize: 12, color: _dimCap),
          ),
        ),
      ];
    }
    return [
      _sectionTitle('Mis playlists', _myPlaylists!.length),
      _sectionGrid('playlist', _myPlaylists!),
    ];
  }

  List<Map<String, dynamic>> _flat() {
    if (_results == null) return const [];
    return [
      ...?_results!['tracks'],
      ...?_results!['artists'],
      ...?_results!['playlists'],
    ];
  }

  List<Widget> _resultSections() {
    const names = {
      'tracks': ('Canciones', 'track'),
      'artists': ('Artistas', 'artist'),
      'playlists': ('Playlists', 'playlist'),
    };
    final sections = <Widget>[];
    for (final entry in _results!.entries) {
      final key = entry.key;
      final meta = names[key];
      if (meta == null) continue;
      final (title, type) = meta;
      if (_filter != 'all' && _filter != type) continue;
      final items = entry.value;
      if (items.isEmpty) continue;
      sections.add(_sectionTitle(title, items.length));
      sections.add(_sectionGrid(type, items));
      sections.add(const SizedBox(height: 18));
    }
    return sections;
  }

  Widget _sectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionGrid(String type, List<Map<String, dynamic>> items) {
    return switch (type) {
      'track' => _trackStrip(items),
      'artist' => _artistStrip(items),
      _ => _playlistStrip(items),
    };
  }

  /// Filas horizontales compactas: se ven ~4 y se scrollea a los lados.
  /// ListView.builder es lazy por construcción: construye solo los items
  /// visibles y descarta los que salen de vista (y sus imágenes se liberan
  /// del cache por LRU). No se carga todo de golpe.
  Widget _trackStrip(List<Map<String, dynamic>> items) {
    return _strip(items, height: 160, cardWidth: 110, card: _trackCard);
  }

  Widget _artistStrip(List<Map<String, dynamic>> items) {
    return _strip(items, height: 225, cardWidth: 130, card: _artistCard);
  }

  Widget _playlistStrip(List<Map<String, dynamic>> items) {
    return _strip(items, height: 225, cardWidth: 140, card: _playlistCard);
  }

  Widget _strip(
    List<Map<String, dynamic>> items, {
    required double height,
    required double cardWidth,
    required Widget Function(Map<String, dynamic>) card,
  }) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4),
        itemCount: items.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(width: cardWidth, child: card(items[i])),
        ),
      ),
    );
  }

  Widget _trackCard(Map<String, dynamic> item) {
    final selected = _spot?['uri'] == item['uri'];
    return GestureDetector(
      onTap: () => setState(() => _spot = item),
      child: _trackCardBody(item, selected),
    );
  }

  Widget _artistCard(Map<String, dynamic> item) {
    final selected = _spot?['uri'] == item['uri'];
    return GestureDetector(
      onTap: () => setState(() => _spot = item),
      child: _artistCardBody(item, selected),
    );
  }

  Widget _playlistCard(Map<String, dynamic> item) {
    final selected = _spot?['uri'] == item['uri'];
    return GestureDetector(
      onTap: () => setState(() => _spot = item),
      child: _playlistCardBody(item, selected),
    );
  }

  Widget _trackCardBody(Map<String, dynamic> item, bool selected) {
    final name = item['name']?.toString() ?? '';
    final subtitle = item['subtitle']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _resultArt(
          item,
          size: 110,
          radius: BorderRadius.circular(12),
          selected: selected,
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _dimText),
          ),
        ],
      ],
    );
  }

  Widget _artistCardBody(Map<String, dynamic> item, bool selected) {
    final name = item['name']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
      child: Column(
        children: [
          // AspectRatio(1) fuerza el cuadrado aunque la celda del grid sea
          // más angosta que el arte; con ClipOval el círculo es perfecto
          // siempre (antes un tamaño fijo de 96px en celdas de ~72px
          // deformaba el recorte en óvalo).
          AspectRatio(
            aspectRatio: 1,
            child: _resultArt(
              item,
              radius: BorderRadius.circular(999),
              selected: selected,
              circle: true,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Artista',
            style: TextStyle(fontSize: 13, color: _dimText),
          ),
        ],
      ),
    );
  }

  Widget _playlistCardBody(Map<String, dynamic> item, bool selected) {
    final name = item['name']?.toString() ?? '';
    final subtitle = item['subtitle']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: _resultArt(
              item,
              radius: BorderRadius.circular(14),
              selected: selected,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: _dimText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultArt(
    Map<String, dynamic> item, {
    required BorderRadius radius,
    required bool selected,
    double? size,
    bool circle = false,
  }) {
    final url = item['image_url']?.toString();
    final icon = switch (item['type']) {
      'artist' => CupertinoIcons.person,
      'playlist' => CupertinoIcons.music_note_list,
      _ => CupertinoIcons.music_note,
    };
    final fallback = Container(
      color: AppColors.surfaceSoft,
      child: Icon(icon, size: 22, color: AppColors.textFaint),
    );
    Widget art;
    if (url == null || url.isEmpty) {
      art = fallback;
    } else {
      art = Image.network(
        url,
        fit: BoxFit.cover,
        // Decodifica al tamaño mostrado (x3 para densidad), no a los 640px
        // que manda Spotify: menos memoria y menos lag al hacer scroll.
        cacheWidth: ((size ?? 64) * 3).round(),
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      );
    }
    final check = selected
        ? Positioned(
            right: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x4020142D), blurRadius: 6)],
              ),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Icon(
                  CupertinoIcons.checkmark,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    if (circle) {
      // Círculo perfecto para artistas: ClipOval no depende del radio.
      return AspectRatio(
        aspectRatio: 1,
        child: ClipOval(
          child: Stack(fit: StackFit.expand, children: [art, check]),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(fit: StackFit.expand, children: [art, check]),
      ),
    );
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      if (_results != null || _searching || _searchError != null) {
        setState(() {
          _results = null;
          _searching = false;
          _searchError = null;
        });
      }
      return;
    }
    // Sin setState por tecla: solo el timer de 300ms dispara el rebuild.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searching = true);
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q) async {
    try {
      final data = await widget.api.spotifySearch(q);
      if (!mounted) return;
      setState(() {
        _results = {
          'tracks':
              (data['tracks'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
          'artists':
              (data['artists'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
          'playlists':
              (data['playlists'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
        };
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      var message = e.toString();
      if (e.body is Map && (e.body as Map)['detail'] != null) {
        message = (e.body as Map)['detail'].toString();
      }
      setState(() {
        _searchError = message;
        _results = null;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  // --- Sliders y pill compartidos --------------------------------------------

  Widget _valueSlider({double? value, ValueChanged<double>? onChanged}) {
    final current = value ?? _value;
    final change =
        onChanged ?? (v) => setState(() => _value = v.roundToDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Slider(
                value: current,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${current.round()}%',
                activeColor: _accent,
                onChanged: change,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '${current.round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _dimCap,
        ),
      ),
    );
  }

  Widget _pillWrap({required List<Widget> children}) {
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: IntrinsicWidth(
        child: Container(
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 18 : 20),
          decoration: BoxDecoration(
            color: selected ? _accent : _softFill,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: _border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: selected ? Colors.white : _dimText),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : _dimText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      child: Material(
        color: filled ? _accent : _softFill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled ? null : Border.all(color: _border),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : _dimText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({String hint = ''}) {
    return InputDecoration(
      hintText: hint,
      counterText: '',
      filled: true,
      fillColor: AppColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accent, width: 1.4),
      ),
    );
  }

  void _submit() {
    final action = _readAction();
    if (action == null) return;
    final conflicts = findConflicts(action, widget.existing, widget.locationsView);
    if (conflicts.isNotEmpty) {
      setState(() {
        _pending = action;
        _conflicts = conflicts;
      });
      return;
    }
    Navigator.pop(context, action);
  }

  Map<String, dynamic>? _readAction() {
    switch (widget.type) {
      case 'device':
        if (_location == null || _device == null || _intent == null) {
          _showFeedback('Elige una ubicación, un dispositivo y una acción.');
          return null;
        }
        return {
          'scope': 'SINGLE',
          'intent': _intent,
          'location': _location,
          'device': _device,
          if (_intent == 'SET_VALUE') ...{
            'value': _value.round(),
            'value_semantic': 'porcentaje',
          },
        };
      case 'location':
        final intent = _intent ?? 'TURN_ON';
        return {
          'intent': intent,
          'scope': _house ? 'HOUSE_ALL' : 'LOCATION_ALL',
          if (!_house) 'location': _location,
        };
      case 'music':
        final action = <String, dynamic>{
          'scope': 'MEDIA_CONTROL',
          'intent': 'MEDIA_CONTROL',
          'operation': _op,
        };
        if (_op == 'play') {
          if (_spot == null) {
            _showFeedback('Elige una canción, artista o playlist.');
            return null;
          }
          action['query'] = _spot!['name'];
          action['spotify_type'] = _spot!['type'];
          action['spotify_uri'] = _spot!['uri'];
        }
        if (_op == 'volume') {
          action['argument'] = _volume.round().toString();
        }
        return action;
      case 'news':
        return {'scope': 'FETCH_NEWS', 'intent': 'FETCH_NEWS'};
      case 'camera':
        final query = _cameraController.text.trim();
        if (query.isEmpty) {
          _showFeedback('Escribe cuál cámara, por ejemplo «camara patio».');
          return null;
        }
        return {
          'scope': 'CAMERA_CONTROL',
          'intent': 'CAMERA_CONTROL',
          'operation': _cameraOp,
          'query': query,
        };
      case 'climate':
        if (!_climateAll && _climateLocation == null) {
          _showFeedback('Elige una ubicación para el clima.');
          return null;
        }
        return {
          'scope': 'CLIMATE_CONTROL',
          'intent': 'CLIMATE_CONTROL',
          if (!_climateAll) 'location': _climateLocation,
          'mode': _climateMode,
          if (_climateMode != 'off') ...{
            'value': _climateTemp.round(),
            'value_semantic': 'grados',
          },
        };
      case 'wait':
        return {
          'scope': 'WAIT',
          'intent': 'WAIT',
          'value': _waitValue,
          'value_semantic': _waitUnit == 's' ? 'segundos' : 'minutos',
        };
      case 'announce':
        final message = _announceController.text.trim();
        if (message.isEmpty) {
          _showFeedback('Escribe el mensaje que dirá GAMMA.');
          return null;
        }
        return {
          'scope': 'ANNOUNCE',
          'intent': 'ANNOUNCE',
          if (_announceTarget == 'phone') 'location': 'phone',
          'query': message,
        };
      case 'runroutine':
        if (_runRoutineId == null) {
          _showFeedback('Elige qué rutina se ejecutará.');
          return null;
        }
        String targetName = '';
        for (final r in widget.routines) {
          if (r['id']?.toString() == _runRoutineId) {
            targetName = r['nombre']?.toString() ?? '';
          }
        }
        return {
          'scope': 'RUN_ROUTINE',
          'intent': 'RUN_ROUTINE',
          'routine_id': _runRoutineId,
          if (targetName.isNotEmpty) 'query': targetName,
        };
    }
    return null;
  }

  void _showFeedback(String message) {
    setState(() => _feedback = message);
  }
}

/// Skeleton de carga para los resultados de Spotify: imita la forma de las
/// filas horizontales (card + textos) con un pulso de opacidad. Sin
/// dependencias — FadeTransition sobre un AnimationController.
class _SkeletonStrip extends StatefulWidget {
  const _SkeletonStrip({
    required this.height,
    required this.cardWidth,
    this.circle = false,
  });

  final double height;
  final double cardWidth;
  final bool circle;

  @override
  State<_SkeletonStrip> createState() => _SkeletonStripState();
}

class _SkeletonStripState extends State<_SkeletonStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const placeholders = 4;
    return SizedBox(
      height: widget.height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: placeholders,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FadeTransition(
            opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
            child: SizedBox(
              width: widget.cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: widget.cardWidth,
                    height: widget.cardWidth,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      shape: widget.circle
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: widget.circle
                          ? null
                          : BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: widget.cardWidth * 0.85,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: widget.cardWidth * 0.55,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(6),
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
