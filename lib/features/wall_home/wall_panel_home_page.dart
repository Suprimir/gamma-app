import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../../ui/assistant_orb.dart';
import '../../ui/audio_waves.dart';
import '../../adaptive/adaptive_scope.dart';
import '../dashboard/dashboard_page.dart';
import '../dashboard/desktop_dashboard_page.dart';
import '../../data/device_inventory.dart';
import '../../data/http_device_inventory_repository.dart';
import '../../data/weather_repository.dart';
import '../../ui/open_in_new_tab.dart';
import '../../ui/shared_widgets.dart';
import '../../ui/spotify_logo.dart';
import '../voice/vad_model.dart';
import '../spotify/spotify_controller_owner.dart';
import '../spotify/spotify_player_controller.dart';
import 'wall_activity_bus.dart';
import 'wall_voice_controller.dart';
import '../devices/wall_devices_page.dart';
import '../dashboard/home_theme_background.dart';
import '../cameras/cameras_page.dart';
import '../cameras/cameras_player_page.dart';
import 'wall_home_projection.dart';
import 'wall_quick_actions_usage.dart';
import 'wall_area_editor.dart';
import '../areas/area_editor.dart';

/// Surface-aware Home destination.
///
/// Only the effective wall panel experience renders the dedicated Wall Home;
/// mobile and desktop keep the existing voice [DashboardPage]. Compact wall
/// panels never reach here (AppShell already falls back to mobile).
class AdaptiveHomePage extends StatelessWidget {
  const AdaptiveHomePage({
    super.key,
    required this.api,
    this.spotifyPollInterval = Duration.zero,
    this.onSelectDestination,
  });

  final ApiClient api;

  /// Fallback playback polling cadence for the home surface. Production
  /// wires 30s; SSE events converge state in between. Tests stay at zero so
  /// no timer or subscription outlives them.
  final Duration spotifyPollInterval;

  /// Shell tab switch (same contract as the dock): deep links from the home
  /// move to the destination tab instead of pushing a dock-less route.
  final ValueChanged<int>? onSelectDestination;

  @override
  Widget build(BuildContext context) {
    final scope = AppAdaptiveScope.of(context);
    if (scope.isWallPanel) {
      // Idle sleep is a wall-only behavior (60s of true inactivity: the
      // countdown resets on any touch anywhere and pauses during
      // hands-free work like voice dictation).
      return WallPanelHomePage(
        api: api,
        idleTimeout: const Duration(seconds: 60),
        spotifyPollInterval: spotifyPollInterval,
        onSelectDestination: onSelectDestination,
      );
    }
    if (scope.isDesktopSurface) {
      return DesktopDashboardPage(
        api: api,
        spotifyPollInterval: spotifyPollInterval,
      );
    }
    return DashboardPage(api: api);
  }
}

/// Dedicated room-first Home for the wall panel surface.
///
/// Loads canonical inventory through [DeviceInventoryRepository] and renders
/// a pure [WallHomeSnapshot] projection. Navigation-only: no physical
/// controls, no power state, no provider vocabulary.
class WallPanelHomePage extends StatefulWidget {
  WallPanelHomePage({
    super.key,
    required this.api,
    DeviceInventoryRepository? repository,
    this.idleTimeout,
    this.spotifyPollInterval = Duration.zero,
    this.onSelectDestination,
  }) : repository = repository ?? HttpDeviceInventoryRepository(api);

  final ApiClient api;
  final DeviceInventoryRepository repository;

  /// Inactivity delay before the sleep overlay takes over. Null disables
  /// sleep (widget tests and non-wall previews). Production wall passes 60s.
  final Duration? idleTimeout;

  /// Playback polling cadence for the music card; zero disables polling
  /// (default so direct-construction tests stay timer-free).
  final Duration spotifyPollInterval;

  /// Shell tab switch supplied by the app shell. When present, home deep
  /// links (e.g. the attention card) move to that tab so the dock follows;
  /// standalone/test builds without it keep the pushed-route fallback.
  final ValueChanged<int>? onSelectDestination;

  @override
  State<WallPanelHomePage> createState() => _WallPanelHomePageState();
}

class _QuickActionDef {
  const _QuickActionDef({
    required this.key,
    required this.icon,
    required this.label,
    required this.command,
  });

  final String key;
  final IconData icon;
  final String label;
  final String command;
}

const _wallQuickActions = [
  _QuickActionDef(
    key: 'apagar',
    icon: Icons.power_settings_new_outlined,
    label: 'Apagar todo',
    command: 'Apagá todas las luces',
  ),
  _QuickActionDef(
    key: 'noche',
    icon: Icons.nightlight_outlined,
    label: 'Modo noche',
    command: 'Activá modo noche',
  ),
  _QuickActionDef(
    key: 'segura',
    icon: Icons.shield_outlined,
    label: 'Asegurar casa',
    command: 'Asegurá la casa',
  ),
  _QuickActionDef(
    key: 'fuera',
    icon: Icons.home_outlined,
    label: 'Modo fuera',
    command: 'Activá modo fuera',
  ),
];

class _WallPanelHomePageState extends State<WallPanelHomePage>
    with SingleTickerProviderStateMixin {
  DeviceInventorySnapshot? _snapshot;
  WallHomeSnapshot? _wall;
  Object? _error;
  bool _loading = true;

  /// Non-destructive refresh failure shown while a previous snapshot stays.
  Object? _refreshError;

  /// Set on the first active load; offstage pages stay inert until activated.
  bool _loadStarted = false;

  /// Quick-action order by cross-surface usage (most used first).
  List<String> _quickOrder = [for (final a in _wallQuickActions) a.key];
  bool _quickBusy = false;
  String? _quickBusyKey;

  /// Last completed voice turn seen; a change triggers a canonical refresh.
  int _seenCompletedTurns = 0;

  /// Sleep-mode state: set while the inline voice loop is active so talking
  /// never triggers sleep, and while the sleep overlay covers the screen.
  Timer? _idleTimer;
  bool _sleeping = false;

  /// Fullscreen sleep entry: an [OverlayEntry] (not an in-tree
  /// Positioned.fill) so sleep covers the whole window INCLUDING the shell
  /// side rail. The page area alone can never paint over the rail.
  /// The SAME entry backs the interactive drag-to-sleep sheet: while
  /// [_sheetOwned] the home gesture strip drives its reveal and completing
  /// the gesture never flashes.
  OverlayEntry? _sleepEntry;
  bool _sleepEntryInserted = false;

  /// Interactive drag-to-sleep: px of the sleep sheet pulled up from the
  /// bottom edge while the home gesture strip owns the drag.
  double _sheetLift = 0.0;
  bool _sheetOwned = false;
  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  /// Inline voice loop (same contract as mobile/desktop): the assistant card
  /// talks right here, with no navigation to another screen.
  late final WallVoiceController _voice;
  StreamSubscription<List<double>>? _speechSub;

  /// Passive core-bus subscription started after the first successful load.
  /// Repositories without [DeviceEventStreamRepository] never subscribe;
  /// cancelled on dispose.
  StreamSubscription<Map<String, dynamic>>? _deviceEventsSub;
  bool _deviceEventsSubscribed = false;

  /// Mic open or turn in flight: sleep stays off and touches don't re-arm.
  bool get _voiceActive => _voice.listening || _voice.busy;

  @override
  void initState() {
    super.initState();
    _voice = WallVoiceController(widget.api)..warmUp();
    _speechSub = VadModel.vad.onSpeechEnd.listen(_voice.onSpeechEnd);
    _voice.addListener(_onVoiceChanged);
    // Global activity (touches in any route/dialog/sheet) and hands-free
    // holds (voice dictation) drive the same countdown as local touches.
    WallActivityBus.pokes.addListener(_onBusPoke);
    WallActivityBus.holds.addListener(_onBusHolds);
  }

  /// Last TickerMode visibility seen; re-activation refreshes the snapshot.
  bool _wasActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (!_loadStarted && active) {
      _loadStarted = true;
      _load();
    } else if (_loadStarted && active && !_wasActive) {
      // The tab became visible again: refresh so configuration changes made
      // in the Dispositivos tab (areas/roles/bindings) land in the pending
      // attention count. With a snapshot present `_load` never shows the
      // full-screen spinner.
      _load();
    }
    _wasActive = active;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _refreshError = null;
    });
    // Fire-and-forget: warms the weather cache so the idle screen paints
    // the temperature on its first frame instead of flashing icon-only.
    WeatherRepository.prefetch();
    try {
      final snapshot = await widget.repository.load();
      if (!mounted) return;
      _maybeSubscribeDeviceEvents();
      setState(() {
        _snapshot = snapshot;
        _wall = projectWallHome(snapshot);
        // First paint never waits for plugin I/O; persisted order arrives
        // async and re-sorts when ready.
        _quickOrder = WallQuickActionsUsage.memoryOrder(_quickOrder);
      });
      // Armed here (not only in finally): the persisted-order await below
      // may never resolve where the prefs plugin is unavailable.
      _armIdle();
      final order = await WallQuickActionsUsage.orderedKeys(_quickOrder);
      if (!mounted) return;
      setState(() => _quickOrder = order);
    } catch (error) {
      if (!mounted) return;
      if (_wall == null) {
        setState(() => _error = error);
      } else {
        // Refresh failed after a good snapshot: keep the snapshot and surface
        // a non-destructive error. Never fall back to mocks.
        setState(() => _refreshError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_wall != null) _armIdle();
      }
    }
  }

  /// One-shot lazy subscription to the repository's passive SSE surface,
  /// started after the first successful load. Repositories without
  /// [DeviceEventStreamRepository] (plain fakes) never subscribe, so tests
  /// stay timer-free and no behavior changes for them.
  void _maybeSubscribeDeviceEvents() {
    if (_deviceEventsSubscribed) return;
    final events = asDeviceEventStreamRepository(
      widget.repository,
    )?.deviceEvents();
    if (events == null) return;
    _deviceEventsSubscribed = true;
    _deviceEventsSub = events.listen(_onDeviceEvent, onError: (_) {});
  }

  /// Dispatches one stream frame.
  ///
  /// [ApiClient.events] yields `{'event': <name>, 'data': <decoded frame>}`,
  /// and the core bus wraps every payload in an envelope
  /// (`{id, event, data, timestamp}`), so the real name/payload may live one
  /// level deeper. Only `devices_state_updated` reacts: the canonical snapshot
  /// is silently reloaded, nothing else.
  void _onDeviceEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final outer = event['data'];
    if (outer is! Map) return;
    var name = event['event'];
    final innerData = outer['data'];
    final innerName = outer['event'];
    if (innerData is Map && innerName is String) {
      name = innerName;
    }
    if (name != 'devices_state_updated') return;
    unawaited(_load());
  }

  Future<void> _runQuickAction(_QuickActionDef action) async {
    if (_quickBusy) return;
    setState(() {
      _quickBusy = true;
      _quickBusyKey = action.key;
    });
    try {
      // Persistence is best-effort; the memory count already applied.
      unawaited(WallQuickActionsUsage.recordUse(action.key));
      final result = await widget.api.turn(action.command);
      if (!mounted) return;
      final speech = result['speech']?.toString() ?? 'Listo.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(speech)));
      // The turn may have changed physical state: reload canonical inventory
      // so device/area cards reflect the action instead of a stale snapshot.
      await _load();
      final order = await WallQuickActionsUsage.orderedKeys(_quickOrder);
      if (mounted) setState(() => _quickOrder = order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo ejecutar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _quickBusy = false;
          _quickBusyKey = null;
        });
      }
    }
  }

  @override
  void dispose() {
    WallActivityBus.pokes.removeListener(_onBusPoke);
    WallActivityBus.holds.removeListener(_onBusHolds);
    _voice.removeListener(_onVoiceChanged);
    _speechSub?.cancel();
    unawaited(_deviceEventsSub?.cancel());
    _deviceEventsSub = null;
    _voice.dispose();
    _idleTimer?.cancel();
    _pillTimer?.cancel();
    _sheet.dispose();
    _removeSleepOverlay();
    super.dispose();
  }

  /// While the voice loop is active sleep stays off; when it goes idle
  /// again the countdown restarts from zero. A completed assistant turn also
  /// reloads canonical inventory so spoken actions are reflected.
  void _onVoiceChanged() {
    if (_voice.completedTurns != _seenCompletedTurns) {
      _seenCompletedTurns = _voice.completedTurns;
      unawaited(_load());
    }
    if (_voiceActive) {
      _idleTimer?.cancel();
    } else if (!_sleeping && mounted) {
      _armIdle();
    }
  }

  /// Touch anywhere in the app (any route, dialog or sheet) restarts the
  /// countdown through the global bus.
  void _onBusPoke() => _poke();

  /// A hands-free hold (e.g. voice dictation) pauses the countdown; release
  /// restarts it from zero when nothing else is active.
  void _onBusHolds() {
    if (WallActivityBus.held) {
      _idleTimer?.cancel();
    } else if (!_sleeping && mounted) {
      _armIdle();
    }
  }

  /// (Re)arms the inactivity countdown. No-op when sleep is disabled
  /// ([idleTimeout] null), while sleeping, while the voice loop is active,
  /// or while a hands-free hold (voice dictation) is in flight.
  void _armIdle() {
    _idleTimer?.cancel();
    final timeout = widget.idleTimeout;
    if (timeout == null ||
        _sleeping ||
        _voiceActive ||
        WallActivityBus.held ||
        !mounted) {
      return;
    }
    _idleTimer = Timer(timeout, () {
      if (mounted && !_voiceActive && !WallActivityBus.held) {
        setState(() => _sleeping = true);
        _syncSleepOverlay();
      }
    });
  }

  /// Inserts (or removes) the fullscreen sleep overlay to match [_sleeping].
  /// Insert runs post-frame: the entry must join a laid-out [Overlay].
  void _syncSleepOverlay() {
    if (!mounted) return;
    if (_sleeping && _wall != null && _sleepEntry == null) {
      final entry = _buildSleepEntry(animateEntrance: true);
      _sleepEntry = entry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sleeping || _sleepEntry != entry) return;
        Overlay.of(context).insert(entry);
        _sleepEntryInserted = true;
      });
    } else if (!_sleeping) {
      _removeSleepOverlay();
    }
  }

  OverlayEntry _buildSleepEntry({required bool animateEntrance}) {
    return OverlayEntry(
      builder: (_) => _WallSleepOverlay(
        key: const ValueKey('wall-sleep-overlay'),
        onWake: _wake,
        api: widget.api,
        pollInterval: widget.spotifyPollInterval,
        liftPx: _sheetOwned ? _sheetLift : double.infinity,
        gesturesEnabled: !_sheetOwned,
        animateEntrance: animateEntrance,
      ),
    );
  }

  void _removeSleepOverlay() {
    if (_sleepEntryInserted) {
      _sleepEntry?.remove();
      _sleepEntryInserted = false;
    }
    _sleepEntry = null;
    _sheetOwned = false;
    _sheetLift = 0;
  }

  /// Tablet-style sleep entry: drags starting on the bottom gesture strip
  /// pull the sleep sheet up following the finger (the scroll view never
  /// competes down there). Release past ~35% (or with a fast fling) lands
  /// in sleep; otherwise the sheet slides back down.
  void _onSheetDragStart(DragStartDetails details) {
    if (_sleeping ||
        _voiceActive ||
        _sheet.isAnimating ||
        _sleepEntry != null ||
        !mounted) {
      return;
    }
    _sheetOwned = true;
    _sheetLift = 0;
    final entry = _buildSleepEntry(animateEntrance: false);
    _sleepEntry = entry;
    Overlay.of(context).insert(entry);
    _sleepEntryInserted = true;
    if (mounted) setState(() {});
  }

  void _onSheetDragUpdate(DragUpdateDetails details) {
    if (!_sheetOwned || _sleepEntry == null) return;
    final height = MediaQuery.sizeOf(context).height;
    setState(() {
      _sheetLift = (_sheetLift - details.delta.dy).clamp(0.0, height);
    });
    _sleepEntry?.markNeedsBuild();
  }

  void _onSheetDragEnd(DragEndDetails details) {
    if (!_sheetOwned || _sleepEntry == null) return;
    final height = MediaQuery.sizeOf(context).height;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -600 || _sheetLift > height * 0.35) {
      _settleSheet(target: height, complete: true);
    } else {
      _settleSheet(target: 0, complete: false);
    }
  }

  void _settleSheet({required double target, required bool complete}) {
    final animation = Tween(
      begin: _sheetLift,
      end: target,
    ).animate(CurvedAnimation(parent: _sheet, curve: Curves.easeOut));
    void listener() {
      if (!mounted) return;
      setState(() => _sheetLift = animation.value);
      _sleepEntry?.markNeedsBuild();
    }

    _sheet.addListener(listener);
    _sheet.forward(from: 0).whenComplete(() {
      _sheet.removeListener(listener);
      if (!mounted) return;
      if (complete) {
        _idleTimer?.cancel();
        setState(() {
          _sleeping = true;
          _sheetOwned = false;
          _sheetLift = 0;
        });
        _sleepEntry?.markNeedsBuild();
      } else {
        _removeSleepOverlay();
        if (mounted) setState(() {});
      }
    });
  }

  void _poke() {
    if (_sleeping || _voiceActive) return;
    _armIdle();
  }

  /// Home gesture hint: the bottom pill fades in while the user is actively
  /// touching/scrolling (hinting the swipe-up-to-sleep gesture) and hides
  /// ~1.4s after the interaction ends. Never steals touches.
  Timer? _pillTimer;
  bool _showPill = false;

  void _flashPill() {
    if (!mounted || _sleeping) return;
    if (!_showPill) setState(() => _showPill = true);
    _pillTimer?.cancel();
    _pillTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _showPill = false);
    });
  }

  void _wake() {
    setState(() => _sleeping = false);
    _syncSleepOverlay();
    _armIdle();
  }

  /// Swipe-up entry to sleep: only a clear upward fling counts, so normal
  /// scrolling never triggers it. Skipped while the gesture strip owns an
  /// interactive sheet (it drives the transition itself).
  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_sleeping || _voiceActive || _sleepEntry != null) return;
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dy;
    if (velocity < -500) {
      _idleTimer?.cancel();
      if (mounted) {
        setState(() => _sleeping = true);
        _syncSleepOverlay();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _wall == null) {
      return const _WallHomeScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _wall == null) {
      return _WallHomeScaffold(
        child: MessageView(
          message: 'No se pudo cargar la casa',
          onRetry: _load,
        ),
      );
    }
    return _WallHomeScaffold(
      // Any touch restarts the sleep countdown. Sleep itself renders as a
      // fullscreen OverlayEntry (covers the shell rail too) and consumes
      // its own taps to wake, so the page tree stays overlay-free.
      child: Listener(
        onPointerDown: (_) {
          _poke();
          _flashPill();
        },
        onPointerMove: (_) => _poke(),
        onPointerUp: (_) => _poke(),
        child: GestureDetector(
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification ||
                  notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) {
                _flashPill();
              }
              return false;
            },
            child: Stack(
              children: [
                _WallHomeBody(
                  api: widget.api,
                  snapshot: _snapshot!,
                  wall: _wall!,
                  refreshError: _refreshError,
                  onRefresh: _load,
                  onOpenArea: _showAreaMenu,
                  onAreaLongPress: _areaLongPress,
                  onOpenAttention: _openAttention,
                  voice: _voice,
                  quickOrder: _quickOrder,
                  quickBusy: _quickBusy,
                  quickBusyKey: _quickBusyKey,
                  onQuickAction: _runQuickAction,
                  spotifyPollInterval: widget.spotifyPollInterval,
                ),
                // Tablet-style gesture pill: floats at the bottom of Inicio
                // and only shows while sliding, hinting swipe-up-to-sleep.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: SafeArea(
                      top: false,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: _showPill || _sheetLift > 0 ? 1.0 : 0.0,
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            width: 134,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1C1F2B,
                              ).withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Dedicated gesture strip: bottom-edge drags pull the sleep
                // sheet up following the finger, tablet-style. Transparent,
                // 36px tall over empty scroll padding — never blocks taps.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 36,
                  child: GestureDetector(
                    key: const ValueKey('wall-sleep-gesture-strip'),
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: _onSheetDragStart,
                    onVerticalDragUpdate: _onSheetDragUpdate,
                    onVerticalDragEnd: _onSheetDragEnd,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tap or long-press on a home area card: a centered menu with
  /// Ver dispositivos / Editar / Eliminar. Mutations reload so the grid
  /// converges on canonical data.
  Future<void> _showAreaMenu(WallAreaSummary area) async {
    final action = await _showWallAreaActions(context, area.name);
    if (action == null || !mounted) return;
    switch (action) {
      case _WallAreaAction.view:
        _openAreaDevices(area);
      case _WallAreaAction.edit:
        await _editArea(area);
      case _WallAreaAction.delete:
        await _deleteArea(area);
    }
  }

  /// Deep link into the wall devices list, pre-filtered to this area.
  void _openAreaDevices(WallAreaSummary area) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Theme-aware route: pushed pages live outside the shell's backdrop,
        // so they carry it explicitly (the devices page root is transparent).
        builder: (_) => HomeThemeBackground(
          child: WallDevicesPage(
            api: widget.api,
            repository: widget.repository,
            initialLocationId: area.areaId,
            showBackButton: true,
          ),
        ),
      ),
    );
  }

  HomeArea? _homeArea(String areaId) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    for (final area in snapshot.areas) {
      if (area.id == areaId) return area;
    }
    return null;
  }

  /// Long-press on a home area card: edit or delete it without leaving
  /// Inicio. Mutations reload so the grid converges on canonical data.
  Future<void> _areaLongPress(WallAreaSummary area) async {
    await _showAreaMenu(area);
  }

  Future<void> _editArea(WallAreaSummary area) async {
    final current = _homeArea(area.areaId);
    final result = await showWallAreaEditor(
      context: context,
      api: widget.api,
      title: 'Editar área',
      subtitle: 'Actualizá el nombre',
      submitLabel: 'Guardar',
      initialName: current?.name ?? area.name,
      initialAliases: current?.aliases ?? const [],
    );
    if (result == null || !mounted) return;
    try {
      await widget.repository.updateArea(
        area.areaId,
        name: result.name,
        aliases: result.aliases,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área actualizada.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  Future<void> _deleteArea(WallAreaSummary area) async {
    final confirmed = await showAreaDeleteConfirm(context, area.name);
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.deleteArea(area.areaId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Área eliminada.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(areaErrorMessage(error))));
    }
  }

  void _openAttention() {
    // Configuration attention routes to the wall Devices tab: same
    // destination as the dock entry, so the dock stays visible and back is
    // never needed. Standalone builds without a shell keep the push fallback.
    final select = widget.onSelectDestination;
    if (select != null) {
      select(1); // Dispositivos destination (appDestinations order)
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Theme-aware route: pushed pages live outside the shell's backdrop,
        // so they carry it explicitly (the devices page root is transparent).
        builder: (_) => HomeThemeBackground(
          child: WallDevicesPage(
            api: widget.api,
            repository: widget.repository,
            showBackButton: true,
          ),
        ),
      ),
    );
  }
}

/// Stable outer shell for every wall home state: same header and content
/// width regardless of loading/error/data, so transitions are calm.
class _WallHomeScaffold extends StatelessWidget {
  const _WallHomeScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: child,
        ),
      ),
    );
  }
}

class _WallHomeBody extends StatelessWidget {
  const _WallHomeBody({
    required this.api,
    required this.snapshot,
    required this.wall,
    required this.onOpenArea,
    required this.onAreaLongPress,
    required this.onOpenAttention,
    required this.voice,
    required this.quickOrder,
    required this.quickBusy,
    required this.quickBusyKey,
    required this.onQuickAction,
    required this.spotifyPollInterval,
    this.refreshError,
    this.onRefresh,
  });

  final ApiClient api;
  final DeviceInventorySnapshot snapshot;
  final WallHomeSnapshot wall;
  final ValueChanged<WallAreaSummary> onOpenArea;
  final ValueChanged<WallAreaSummary> onAreaLongPress;
  final VoidCallback onOpenAttention;
  final WallVoiceController voice;
  final List<String> quickOrder;
  final bool quickBusy;
  final String? quickBusyKey;
  final ValueChanged<_QuickActionDef> onQuickAction;
  final Duration spotifyPollInterval;

  /// Non-destructive refresh failure shown above the retained snapshot.
  final Object? refreshError;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final byKey = {for (final a in _wallQuickActions) a.key: a};
    final ordered = [
      for (final key in quickOrder)
        if (byKey.containsKey(key)) byKey[key]!,
    ];
    return RefreshIndicator(
      onRefresh: () async {
        await onRefresh?.call();
      },
      // SingleChildScrollView + Column (not ListView): the wall home is a
      // short screen and every section must exist eagerly at any viewport.
      // A lazy ListView leaves below-the-fold sections unbuilt, which also
      // breaks below-the-fold finders in widget tests.
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mi casa',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            _WallHeroRow(
              api: api,
              voice: voice,
              spotifyPollInterval: spotifyPollInterval,
            ),
            if (refreshError != null) ...[
              const SizedBox(height: 12),
              _RefreshErrorBanner(onRetry: onRefresh),
            ],
            if (wall.attentionCount > 0) ...[
              const SizedBox(height: 12),
              _WallAttentionCard(
                attentionCount: wall.attentionCount,
                onTap: onOpenAttention,
              ),
            ],
            const SizedBox(height: 20),
            const _WallSectionTitle('Acciones rápidas'),
            const SizedBox(height: 12),
            _WallQuickGrid(
              actions: ordered,
              busy: quickBusy,
              busyKey: quickBusyKey,
              onTap: onQuickAction,
            ),
            const SizedBox(height: 20),
            _WallCamerasSection(api: api),
            const SizedBox(height: 20),
            const _WallSectionTitle('Habitaciones'),
            const SizedBox(height: 12),
            _WallAreaGrid(
              areas: wall.areas,
              onOpenArea: onOpenArea,
              onAreaLongPress: onAreaLongPress,
              onOpenDevices: onOpenAttention,
            ),
          ],
        ),
      ),
    );
  }
}

/// Press-down shrink used on every wall tile: finger feedback without
/// changing the tap handler underneath.
class _TapScale extends StatefulWidget {
  const _TapScale({required this.child});

  final Widget child;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _scale = 0.96),
      onPointerUp: (_) => setState(() => _scale = 1.0),
      onPointerCancel: (_) => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _WallSectionTitle extends StatelessWidget {
  const _WallSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    );
  }
}

/// Top hero row from the reference layout: assistant + music side by side,
/// stacked on narrow widths. Floating cards with press animation.
class _WallHeroRow extends StatelessWidget {
  const _WallHeroRow({
    required this.api,
    required this.voice,
    required this.spotifyPollInterval,
  });

  final ApiClient api;
  final WallVoiceController voice;
  final Duration spotifyPollInterval;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        if (narrow) {
          return Column(
            children: [
              _WallAssistantCard(voice: voice),
              const SizedBox(height: 14),
              _WallMusicCard(api: api, pollInterval: spotifyPollInterval),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            // Both hero cards share the row's (tallest) height in every
            // Spotify/assistant state: no disproportionate pair.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _WallAssistantCard(voice: voice)),
              const SizedBox(width: 14),
              Expanded(
                child: _WallMusicCard(
                  api: api,
                  pollInterval: spotifyPollInterval,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Wall assistant talks inline: tapping the orb toggles the same VAD-gated
/// voice loop as mobile/desktop, with live state, waves and transcript
/// right in the card. No navigation to another screen.
class _WallAssistantCard extends StatelessWidget {
  const _WallAssistantCard({required this.voice});

  final WallVoiceController voice;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('wall-assistant-card'),
      // Centered vertically: the hero row stretches both cards to the same
      // height in every Spotify state.
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: ListenableBuilder(
        listenable: voice,
        builder: (context, _) {
          final listening = voice.listening;
          final error = voice.error;
          final thought = voice.thought;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: 192,
                    height: 192,
                    child: AssistantOrb(
                      state: voice.state,
                      onTap: voice.busy ? null : voice.toggle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'GAMMA',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _voiceStatusCopy(voice),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // Fixed slot: waves / error / thought / hint all share the
              // same height, so toggling "Te escucho…" never resizes the
              // card ni empuja lo de abajo.
              SizedBox(
                height: 44,
                child: Center(
                  child: listening
                      ? const AudioWaves(listening: true)
                      : error != null
                      ? Text(
                          error,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.red,
                          ),
                        )
                      : thought.isNotEmpty
                      ? Text(
                          thought,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textDim,
                          ),
                        )
                      : const Text(
                          'Tocá el orbe y hablá',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textDim,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _voiceStatusCopy(WallVoiceController c) {
  if (c.error != null) return 'Algo no salió bien';
  return switch (c.state) {
    LoopState.listening => 'Te escucho…',
    LoopState.processing => 'Procesando…',
    LoopState.speaking => 'Respondiendo…',
    LoopState.error => 'Algo no salió bien',
    LoopState.idle => c.busy ? 'Procesando…' : '¿En qué te ayudo?',
  };
}

class _WallMusicCard extends StatefulWidget {
  const _WallMusicCard({required this.api, required this.pollInterval});

  final ApiClient api;

  /// Playback polling cadence; zero disables polling entirely.
  final Duration pollInterval;

  @override
  State<_WallMusicCard> createState() => _WallMusicCardState();
}

class _WallMusicCardState extends State<_WallMusicCard> {
  static const _externalUrlChannel = MethodChannel('gamma_app/external_url');

  /// Shared app-wide controller when the app provides it (single poll/SSE for
  /// every surface); otherwise this card owns a local one.
  late final SpotifyControllerOwner _spotifyOwner = SpotifyControllerOwner(
    api: widget.api,
    interval: widget.pollInterval,
  );

  SpotifyPlayerController get _spotify => _spotifyOwner.controller;

  bool _spotifyListening = false;

  bool _loading = true;
  bool _connecting = false;
  bool _waitingAuth = false;
  bool _connected = false;
  String? _error;
  Timer? _oauthPoll;

  /// Local scrub position while the user drags the progress slider; null
  /// means "follow the controller's interpolated position".
  int? _seekPreviewMs;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spotifyOwner.attach(context);
    // Playback state is its own async source: the card renders whatever the
    // backend confirms and never blocks the home load on it.
    _spotifyOwner.start();
    // The settings read happens once in [_loadStatus]; the listener converges
    // the card when the playback backend starts answering (fresh auth).
    if (!_spotifyListening) {
      _spotifyListening = true;
      _spotify.addListener(_onSpotifyAvailabilityChanged);
    }
  }

  @override
  void dispose() {
    if (_spotifyListening) {
      _spotify.removeListener(_onSpotifyAvailabilityChanged);
    }
    _oauthPoll?.cancel();
    _spotifyOwner.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.spotifySettings();
      if (!mounted) return;
      setState(() {
        _connected =
            settings['authenticated'] == true &&
            settings['client_id_configured'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final data = await widget.api.spotifyAuthStart();
      final url = data['auth_url']?.toString();
      if (url == null || url.isEmpty) {
        throw StateError('URL de autorización vacía');
      }
      final warning = data['callback_warning']?.toString() ?? '';
      if (warning.isNotEmpty && mounted) {
        setState(() => _error = warning);
      }
      await _openExternalUrl(url);
      if (!mounted) return;
      setState(() => _waitingAuth = true);
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  Future<void> _openExternalUrl(String url) async {
    if (kIsWeb) {
      openInNewTab(url);
      return;
    }
    if (Platform.isAndroid) {
      await _externalUrlChannel.invokeMethod<void>('openUrl', {'url': url});
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

  void _startPolling() {
    _oauthPoll?.cancel();
    var attempts = 0;
    _oauthPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      try {
        final settings = await widget.api.spotifySettings();
        if (!mounted) return;
        final connected =
            settings['authenticated'] == true &&
            settings['client_id_configured'] == true;
        if (connected) {
          timer.cancel();
          setState(() {
            _connected = true;
            _connecting = false;
            _waitingAuth = false;
          });
          // Freshly authorized: pull the now-available playback state.
          unawaited(_spotify.refresh());
          return;
        }
        if (attempts >= 60) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _connecting = false;
            _waitingAuth = false;
            _error = 'Tiempo de espera agotado. Intentá de nuevo.';
          });
        }
      } catch (_) {
        if (attempts >= 60) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _connecting = false;
            _waitingAuth = false;
            _error = 'No se pudo confirmar la conexión.';
          });
        }
      }
    });
  }

  /// Converges the card when the playback backend starts answering without
  /// pressing Conectar (authorization completed from Settings or desktop): a
  /// player response is proof of a usable account, so the OAuth poll — if any
  /// — is no longer needed.
  void _onSpotifyAvailabilityChanged() {
    if (!mounted || _connected) return;
    if (_spotify.needsAuth || _spotify.player == null) return;
    _oauthPoll?.cancel();
    _oauthPoll = null;
    setState(() {
      _connected = true;
      _connecting = false;
      _waitingAuth = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('wall-music-card'),
      // Centered vertically: the hero row stretches both cards to the same
      // height in every Spotify state (playing, idle, disconnected).
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: ListenableBuilder(
        listenable: _spotify,
        builder: (context, _) {
          // A player 401/503 means the account is not usable, even when the
          // last settings read said otherwise: show the connect affordance.
          final connected = _connected && !_spotify.needsAuth;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!connected) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Sin conectar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _waitingAuth
                      ? 'Autorizá GAMMA en Spotify y se conecta sola.'
                      : 'Conectá tu cuenta para ver tu música acá.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded, size: 18),
                  label: Text(
                    _waitingAuth ? 'Esperando...' : 'Conectar Spotify',
                  ),
                ),
              ] else if (_hasPlayback) ...[
                _nowPlaying(),
                _progress(),
                const SizedBox(height: 14),
                _transport(),
                _upNextLine(),
                if (_spotify.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _spotify.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.errorRed,
                    ),
                  ),
                  TextButton(
                    onPressed: _spotify.refresh,
                    child: const Text('Reintentar reproducción'),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 6),
                const Text(
                  'Sin reproducción',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.textDim),
                ),
                if (_spotify.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _spotify.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.errorRed,
                    ),
                  ),
                  TextButton(
                    onPressed: _spotify.refresh,
                    child: const Text('Reintentar reproducción'),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.errorRed,
                  ),
                ),
                TextButton(
                  onPressed: _loadStatus,
                  child: const Text('Reintentar Spotify'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// True when the backend reports loaded playback (or a track map arrived):
  /// drives the player body versus the launcher hint.
  bool get _hasPlayback =>
      (_spotify.player != null && _spotify.player!['has_playback'] == true) ||
      _spotify.track != null;

  /// Hero row: album art + track + `Artist · device` subtitle.
  Widget _nowPlaying() {
    final track = _spotify.track;
    if (track == null) {
      return const Text(
        'Sin reproducción',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: AppColors.textDim),
      );
    }
    final name = track['name']?.toString();
    final artist = track['artist']?.toString();
    final deviceName = _spotify.activeDevice?['name']?.toString();
    final subtitle = [
      if (artist != null && artist.isNotEmpty) artist,
      if (deviceName != null && deviceName.isNotEmpty) deviceName,
    ].join(' · ');
    final imageUrl = track['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    Widget artworkFallback() => Container(
      color: AppColors.surfaceRaised,
      child: const Icon(
        Icons.music_note_rounded,
        size: 40,
        color: AppColors.textFaint,
      ),
    );
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 96,
            height: 96,
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, _, _) => artworkFallback(),
                  )
                : artworkFallback(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (name == null || name.isEmpty) ? 'Sin título' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        const SpotifyLogo(size: 18),
      ],
    );
  }

  /// True when the scrubber may issue a seek: the backend advertises a
  /// resolvable device and, when it sends an explicit [actions] list, a
  /// `seek` entry. Legacy responses without actions keep the old device check.
  bool _seekEnabled() {
    if (_spotify.activeDevice == null) return false;
    final actions = _spotify.player?['actions'];
    final gated = actions is List && actions.isNotEmpty;
    return gated ? _spotify.actionEnabled('seek') : true;
  }

  /// Progress scrubber: a touch-sized slider over the controller's
  /// interpolated position. Dragging previews locally (label follows the
  /// finger, no traffic); the seek commits on drag end / tap. When seeking is
  /// disabled it degrades to the non-interactive bar.
  Widget _progress() {
    final duration = _spotify.durationMs;
    if (_spotify.track == null || duration == null || duration <= 0) {
      return const SizedBox.shrink();
    }
    final canonical = (_spotify.progressMs ?? 0).clamp(0, duration);
    if (!_seekEnabled()) {
      return _progressBar(canonical, duration);
    }
    final position = (_seekPreviewMs ?? canonical).clamp(0, duration);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 8,
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.accent,
                // 24px visual thumb with a 48px overlay/hit region.
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              ),
              child: Slider(
                key: const ValueKey('wall-spotify-progress'),
                value: position.toDouble(),
                max: duration.toDouble(),
                onChanged: (value) =>
                    setState(() => _seekPreviewMs = value.round()),
                onChangeEnd: (value) {
                  final target = value.round().clamp(0, duration);
                  setState(() => _seekPreviewMs = null);
                  unawaited(_spotify.seek(target));
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_formatPlaybackTime(position)} / ${_formatPlaybackTime(duration)}',
            style: const TextStyle(fontSize: 15, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  /// Non-interactive fallback for the progress row (no device, or the
  /// backend does not advertise `seek`).
  Widget _progressBar(int position, int duration) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: duration <= 0 ? 0 : position / duration,
                minHeight: 8,
                backgroundColor: AppColors.accentTint,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_formatPlaybackTime(position)} / ${_formatPlaybackTime(duration)}',
            style: const TextStyle(fontSize: 15, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  /// Single up-next line; hidden while the queue is empty. Tapping opens the
  /// touch-sized queue sheet.
  Widget _upNextLine() {
    final upcoming = _spotify.upcomingQueue;
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: const ValueKey('wall-spotify-up-next'),
        borderRadius: BorderRadius.circular(12),
        onTap: _openQueueSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: AppColors.textFaint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A continuación · ${_formatUpNextItem(upcoming.first)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transportButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      iconSize: primary ? 38 : 32,
      icon: Icon(icon),
      color: primary ? Colors.white : AppColors.accent,
      disabledColor: AppColors.textFaint,
      style: IconButton.styleFrom(
        backgroundColor: primary ? AppColors.accent : AppColors.accentTint,
        disabledBackgroundColor: AppColors.surfaceRaised,
        padding: const EdgeInsets.all(14),
      ),
    );
  }

  /// Transport row. When the backend advertises the executable [actions]
  /// (SSE state), gating follows that list; otherwise it falls back to the
  /// device check (a command with no active device is a guaranteed 409).
  Widget _transport() {
    final actions = _spotify.player?['actions'];
    final gated = actions is List && actions.isNotEmpty;
    final hasDevice = _spotify.activeDevice != null;
    bool enabledFor(String action) =>
        gated ? _spotify.actionEnabled(action) : hasDevice;
    final playing = _spotify.isPlaying;
    // Transport stays centered; the device and volume buttons sit flush
    // right (respecting the card padding), replacing the old icon row.
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _transportButton(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Anterior',
              enabled: enabledFor('skip_prev'),
              onPressed: _spotify.previous,
            ),
            const SizedBox(width: 12),
            _transportButton(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              tooltip: playing ? 'Pausar' : 'Reproducir',
              enabled: enabledFor(playing ? 'pause' : 'play'),
              onPressed: playing ? _spotify.pause : _spotify.play,
              primary: true,
            ),
            const SizedBox(width: 12),
            _transportButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Siguiente',
              enabled: enabledFor('skip_next'),
              onPressed: _spotify.next,
            ),
          ],
        ),
        Align(alignment: Alignment.centerLeft, child: _volumeButton()),
        Align(alignment: Alignment.centerRight, child: _deviceButton()),
      ],
    );
  }

  Widget _volumeButton() {
    final volume = _spotifyVolume();
    final muted = volume != null && volume <= 0;
    final volumeUnsupported = _spotify.targetSupportsVolume == false;
    return IconButton(
      key: const ValueKey('wall-spotify-volume'),
      tooltip: volumeUnsupported ? spotifyVolumeUnsupportedTooltip : 'Volumen',
      onPressed: volumeUnsupported ? null : _openVolumeSheet,
      iconSize: 28,
      color: AppColors.text,
      disabledColor: AppColors.textFaint,
      icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
    );
  }

  /// Volume reported by the player, else by the active device, else null.
  int? _spotifyVolume() {
    final playerVolume = _spotify.player?['volume_percent'];
    final deviceVolume = _spotify.activeDevice?['volume_percent'];
    if (playerVolume is int) return playerVolume;
    if (deviceVolume is int) return deviceVolume;
    return null;
  }

  Widget _volume() {
    // Explicit `supports_volume == false` disables the slider; the row stays
    // visible read-only with a hint. Unknown/null keeps the legacy behavior.
    final volumeUnsupported = _spotify.targetSupportsVolume == false;
    return _WallVolumeSlider(
      value: _spotifyVolume(),
      enabled: _spotify.activeDevice != null && !volumeUnsupported,
      hint: volumeUnsupported ? spotifyVolumeUnsupportedHint : null,
      onCommit: _spotify.setVolume,
    );
  }

  /// Icon-only secondary actions: volume sheet, device sheet, queue sheet
  /// (only with a known queue) and the overflow menu.
  Widget _deviceButton() {
    final name = _spotify.activeDevice?['name']?.toString();
    final empty = name == null || name.isEmpty;
    return IconButton(
      key: const ValueKey('wall-spotify-device'),
      tooltip: empty ? 'Sin dispositivo activo' : 'Elegir dispositivo',
      onPressed: _pickDevice,
      iconSize: 28,
      color: AppColors.text,
      icon: Icon(empty ? Icons.speaker_outlined : Icons.speaker_rounded),
    );
  }

  /// Touch-sized volume sheet with the existing full-width slider.
  Future<void> _openVolumeSheet() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          child: ListenableBuilder(
            listenable: _spotify,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Volumen',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                _volume(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Touch-sized queue sheet: "A continuación" rows (up to 10) plus an
  /// "Anteriores" section when the backend reports previous tracks.
  Future<void> _openQueueSheet() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: _spotify,
            builder: (context, _) {
              final upcoming = _spotify.upcomingQueue.take(10).toList();
              final previous = _spotify.previousQueue.take(10).toList();
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'A continuación',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (upcoming.isEmpty)
                      const Text(
                        'No hay elementos en la cola.',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textDim,
                        ),
                      )
                    else
                      for (final item in upcoming) _queueRow(item),
                    if (previous.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Anteriores',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in previous) _queueRow(item),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _queueRow(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 20,
            color: AppColors.textFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _formatQueueItem(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  /// Overflow menu on the wall: full settings page for the Spotify account.
  /// Touch-sized device picker: every target is a full-width 56px row and
  /// "Automático" clears the explicit pick (the backend resolves it).
  Future<void> _pickDevice() async {
    // Fresh listing regardless of the cadence: the user may have just started
    // Spotify on another device that the cached listing does not know yet.
    unawaited(_spotify.refreshNow());
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return SafeArea(
          // The sheet rebuilds with the controller so a listing that lands
          // after opening (forced read) shows the fresh targets immediately.
          child: ListenableBuilder(
            listenable: _spotify,
            builder: (context, _) {
              final activeId = _spotify.activeDevice?['id'];
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text(
                        'Reproducir en',
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.auto_awesome,
                        color: AppColors.textDim,
                      ),
                      title: const Text(
                        'Automático',
                        style: TextStyle(color: AppColors.text),
                      ),
                      subtitle: const Text(
                        'GAMMA elige el dispositivo activo',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                      trailing:
                          _spotify.selectedDeviceId == null && activeId != null
                          ? Icon(Icons.check, color: AppColors.accent)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, ''),
                    ),
                    for (final device in _spotify.devices)
                      ListTile(
                        leading: Icon(
                          device['is_active'] == true
                              ? Icons.speaker
                              : Icons.speaker_outlined,
                          color: AppColors.textDim,
                        ),
                        title: Text(
                          device['name']?.toString() ??
                              device['id']?.toString() ??
                              'Dispositivo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.text),
                        ),
                        subtitle: device['is_default'] == true
                            ? const Text(
                                'Predeterminado',
                                style: TextStyle(color: AppColors.textFaint),
                              )
                            : null,
                        trailing: device['id'] == activeId
                            ? Icon(Icons.check, color: AppColors.accent)
                            : null,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          device['id']?.toString(),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice.isEmpty) {
      _spotify.selectDevice(null);
      return;
    }
    await _spotify.transferTo(choice);
  }
}

/// Touch-sized volume slider. Drag value is local so a polling refresh never
/// fights the finger; only the drag end commits to the backend. A non-null
/// [hint] renders under the row when the device cannot be volume-controlled.
class _WallVolumeSlider extends StatefulWidget {
  const _WallVolumeSlider({
    required this.value,
    required this.enabled,
    required this.onCommit,
    this.hint,
  });

  final int? value;
  final bool enabled;
  final ValueChanged<int> onCommit;
  final String? hint;

  @override
  State<_WallVolumeSlider> createState() => _WallVolumeSliderState();
}

class _WallVolumeSliderState extends State<_WallVolumeSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value?.toDouble() ?? 0).clamp(0.0, 100.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.volume_down_rounded, color: AppColors.textDim),
            Expanded(
              child: Slider(
                key: const ValueKey('wall-spotify-volume-slider'),
                value: value,
                max: 100,
                activeColor: AppColors.accent,
                inactiveColor: AppColors.border,
                onChanged: widget.enabled
                    ? (v) => setState(() => _drag = v)
                    : null,
                onChangeEnd: widget.enabled
                    ? (v) {
                        setState(() => _drag = null);
                        widget.onCommit(v.round());
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${value.round()}%',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13, color: AppColors.textDim),
              ),
            ),
          ],
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              color: AppColors.textFaint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Four 1-tap tiles in a touch-first wrap (kept outside the rooms GridView).
class _WallQuickGrid extends StatelessWidget {
  const _WallQuickGrid({
    required this.actions,
    required this.busy,
    required this.busyKey,
    required this.onTap,
  });

  final List<_QuickActionDef> actions;
  final bool busy;
  final String? busyKey;
  final ValueChanged<_QuickActionDef> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 3 * 14) / 4
            : (constraints.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final action in actions)
              SizedBox(
                width: tileWidth,
                child: _TapScale(
                  child: TextButton(
                    onPressed: busy ? null : () => onTap(action),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 20,
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.text,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.accentTint,
                            shape: BoxShape.circle,
                          ),
                          child: busy && busyKey == action.key
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  action.icon,
                                  size: 24,
                                  color: AppColors.accent,
                                ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          action.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Live cameras strip for the wall home: sits between quick actions and
/// rooms. The header is always visible; only the body varies (loading,
/// empty, or live tiles). Never invents cameras.
class _WallCamerasSection extends StatefulWidget {
  const _WallCamerasSection({required this.api});

  final ApiClient api;

  @override
  State<_WallCamerasSection> createState() => _WallCamerasSectionState();
}

class _WallCamerasSectionState extends State<_WallCamerasSection> {
  List<Map<String, dynamic>> _cameras = [];
  Map<String, bool?> _onlineById = {};
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final module = await widget.api.cameraModule();
      if (!mounted) return;
      if (!module.enabled || module.cameras.isEmpty) {
        setState(() {
          _cameras = [];
          _loading = false;
          _loadFailed = false;
        });
        return;
      }
      Map<String, bool?> onlineById = {};
      try {
        final status = await widget.api.cameraStatus();
        final list =
            (status['statuses'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        for (final entry in list) {
          final id = entry['camera_id']?.toString();
          if (id != null) {
            final online = entry['online'];
            onlineById[id] = online is bool ? online : null;
          }
        }
      } catch (_) {
        // Status is best-effort: cards still render without the dot logic.
      }
      if (!mounted) return;
      setState(() {
        _cameras = module.cameras.take(3).toList();
        _onlineById = onlineById;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameras = [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _openAll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CamerasPage(api: widget.api, showBackButton: true),
      ),
    );
  }

  void _openCamera(Map<String, dynamic> camera) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraPlayerPage(api: widget.api, camera: camera),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _WallSectionTitle('Cámaras en vivo'),
            TextButton(onPressed: _openAll, child: const Text('Ver todas ›')),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const _WallCameraPlaceholders()
        else if (_cameras.isEmpty)
          _WallCameraEmpty(
            loadFailed: _loadFailed,
            onRetry: _load,
            onOpenAll: _openAll,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 2 * 14) / 3
                  : (constraints.maxWidth - 14) / 2;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final camera in _cameras)
                    SizedBox(
                      width: tileWidth,
                      child: _WallCameraTile(
                        camera: camera,
                        online: _onlineById[camera['camera_id']?.toString()],
                        snapshotUrl: widget.api.cameraSnapshotUrl(
                          camera['camera_id'].toString(),
                        ),
                        onTap: () => _openCamera(camera),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _WallCameraPlaceholders extends StatelessWidget {
  const _WallCameraPlaceholders();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 2 * 14) / 3
            : (constraints.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (var i = 0; i < 3; i++)
              SizedBox(
                width: tileWidth,
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141826).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WallCameraEmpty extends StatelessWidget {
  const _WallCameraEmpty({
    required this.loadFailed,
    required this.onRetry,
    required this.onOpenAll,
  });

  final bool loadFailed;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam_outlined, color: AppColors.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loadFailed
                  ? 'No se pudieron cargar las cámaras'
                  : 'No hay cámaras disponibles',
              style: const TextStyle(fontSize: 15, color: AppColors.textDim),
            ),
          ),
          TextButton(
            onPressed: loadFailed ? () => onRetry() : onOpenAll,
            child: Text(loadFailed ? 'Reintentar' : 'Ver cámaras'),
          ),
        ],
      ),
    );
  }
}

class _WallCameraTile extends StatelessWidget {
  const _WallCameraTile({
    required this.camera,
    required this.online,
    required this.snapshotUrl,
    required this.onTap,
  });

  final Map<String, dynamic> camera;
  final bool? online;
  final String snapshotUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = camera['name']?.toString() ?? 'Cámara';
    final dotColor = online == null
        ? Colors.grey
        : online!
        ? const Color(0xFF4ADE80)
        : const Color(0xFFF87171);
    return _TapScale(
      child: Material(
        color: const Color(0xFF141826),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  snapshotUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const Center(
                    child: Icon(
                      Icons.videocam_outlined,
                      color: Colors.white24,
                      size: 32,
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x66000000)],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-destructive refresh failure: the previous snapshot stays visible.
class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.sync_problem, color: AppColors.textDim),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No se pudo actualizar',
                style: TextStyle(fontSize: 15, color: AppColors.textDim),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Actionable configuration attention, household language only.
class _WallAttentionCard extends StatelessWidget {
  const _WallAttentionCard({required this.attentionCount, required this.onTap});

  final int attentionCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          alignment: Alignment.centerLeft,
          backgroundColor: AppColors.surfaceRaised,
          foregroundColor: AppColors.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.amber),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.amber),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Necesita atención',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            // Flexible so the count wraps instead of overflowing on narrow
            // panels; the title keeps priority via Expanded above.
            Flexible(
              child: Text(
                _attentionLabel(attentionCount),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 16, color: AppColors.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _attentionLabel(int count) {
  if (count == 1) return '1 dispositivo por configurar';
  return '$count dispositivos por configurar';
}

/// Room-first grid with large touch tiles. Adaptive max extent, wall-only
/// density: medium -> usually 2 columns, expanded -> 3, large -> 3-4 with the
/// max card extent capping stretch on very wide displays.
/// Long-press actions for a home area card.
enum _WallAreaAction { view, edit, delete }

/// Wall-styled centered menu for a tapped/long-pressed area: the area name
/// on top with large view/edit/delete rows and a pop-in animation.
/// Returns the choice, or null on dismiss.
Future<_WallAreaAction?> _showWallAreaActions(
  BuildContext context,
  String areaName,
) {
  return showWallCenterDialog<_WallAreaAction>(
    context: context,
    builder: (dialogContext) => WallCenterDialog(
      title: areaName,
      subtitle: 'Elegí una acción',
      children: [
        WallSheetOption(
          label: 'Ver dispositivos',
          icon: Icons.devices_outlined,
          onTap: () => Navigator.of(dialogContext).pop(_WallAreaAction.view),
        ),
        const SizedBox(height: 10),
        WallSheetOption(
          label: 'Editar área',
          icon: Icons.edit_outlined,
          onTap: () => Navigator.of(dialogContext).pop(_WallAreaAction.edit),
        ),
        const SizedBox(height: 10),
        WallSheetOption(
          label: 'Eliminar área',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => Navigator.of(dialogContext).pop(_WallAreaAction.delete),
        ),
      ],
    ),
  );
}

class _WallAreaGrid extends StatelessWidget {
  const _WallAreaGrid({
    required this.areas,
    required this.onOpenArea,
    required this.onAreaLongPress,
    required this.onOpenDevices,
  });

  final List<WallAreaSummary> areas;
  final ValueChanged<WallAreaSummary> onOpenArea;
  final ValueChanged<WallAreaSummary> onAreaLongPress;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    if (areas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aún no hay habitaciones configuradas',
              style: TextStyle(fontSize: 17, color: AppColors.textDim),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpenDevices,
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Ver dispositivos'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        // 160 (not 150): icon + two scaled texts must survive 1.5x text
        // scale without clipping (see wall_home_semantics_test).
        mainAxisExtent: 160,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
      ),
      itemCount: areas.length,
      itemBuilder: (context, index) {
        final area = areas[index];
        return _WallAreaCard(
          key: ValueKey('wall-area-${area.areaId}'),
          area: area,
          pastelIndex: index,
          onTap: () => onOpenArea(area),
          onLongPress: () => onAreaLongPress(area),
        );
      },
    );
  }
}

const _wallPastels = [
  Color(0xFFC7D6FE),
  Color(0xFFBFE9CF),
  Color(0xFFF6DFA8),
  Color(0xFFD8CBF5),
];

IconData _wallAreaIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('cocin')) return Icons.restaurant_outlined;
  if (lower.contains('living') || lower.contains('sala')) {
    return Icons.weekend_outlined;
  }
  if (lower.contains('patio') || lower.contains('jard')) {
    return Icons.local_florist_outlined;
  }
  if (lower.contains('recamar') ||
      lower.contains('dormi') ||
      lower.contains('cuarto') ||
      lower.contains('habita')) {
    return Icons.bed_outlined;
  }
  if (lower.contains('comedor')) return Icons.table_restaurant_outlined;
  if (lower.contains('pasillo')) return Icons.meeting_room_outlined;
  return Icons.home_work_outlined;
}

class _WallAreaCard extends StatelessWidget {
  const _WallAreaCard({
    super.key,
    required this.area,
    required this.pastelIndex,
    required this.onTap,
    required this.onLongPress,
  });

  final WallAreaSummary area;
  final int pastelIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    // The semantic label is merged onto the button; the Texts below carry the
    // visible wording and fold into one readable node via MergeSemantics.
    return MergeSemantics(
      child: _TapScale(
        child: TextButton(
          onPressed: onTap,
          onLongPress: onLongPress,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.centerLeft,
            backgroundColor: _wallPastels[pastelIndex % _wallPastels.length],
            foregroundColor: AppColors.text,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_wallAreaIcon(area.name), size: 26, color: AppColors.text),
              const SizedBox(height: 6),
              Text(
                area.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${area.controlCount} '
                '${area.controlCount == 1 ? 'control' : 'controles'}',
                style: const TextStyle(fontSize: 14, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fullscreen sleep screen for the wall panel: photo background with a dark
/// veil, compact date header, huge bold clock, tap or swipe up to wake.
///
/// Rendered as an [OverlayEntry] so it covers the whole window, shell side
/// rail included. Temperature is REAL ambient data from Open-Meteo
/// (see [WeatherRepository]); while it loads or when offline only the
/// icon + date show, never an invented number.
///
/// Rendered as an [OverlayEntry] so it covers the whole window, shell side
/// rail included. Temperature is intentionally absent: the backend exposes
/// no weather, and the wall never invents state — when the backend offers
/// real weather, a live reading can take the header slot next to the date.
class _WallSleepOverlay extends StatefulWidget {
  const _WallSleepOverlay({
    super.key,
    required this.onWake,
    required this.api,
    this.pollInterval = Duration.zero,
    this.liftPx = double.infinity,
    this.gesturesEnabled = true,
    this.animateEntrance = true,
  });

  final VoidCallback onWake;

  /// Backend client for the read-only now-playing chip shown while sleeping.
  final ApiClient api;

  /// Fallback poll interval for the now-playing chip (zero disables).
  final Duration pollInterval;

  /// Interactive reveal driven by the home gesture strip: px of the sheet
  /// pulled up from the bottom edge. Infinity = fully presented.
  final double liftPx;

  /// False while the home page owns the drag driving [liftPx]: wake
  /// gestures stay off so the two gesture owners never fight.
  final bool gesturesEnabled;

  /// False for gesture-driven presentations — the drag IS the entrance.
  final bool animateEntrance;

  @override
  State<_WallSleepOverlay> createState() => _WallSleepOverlayState();
}

class _WallSleepOverlayState extends State<_WallSleepOverlay>
    with TickerProviderStateMixin {
  Timer? _timer;
  DateTime _now = DateTime.now();

  /// Real Culiacán weather for the header. Seeded from the prefetch cache
  /// so the first frame already shows it (no icon-only flash).
  late final WeatherRepository _weatherRepo = WeatherRepository();
  WeatherReading? _weather;
  Timer? _weatherTimer;

  /// Read-only now-playing chip for the idle screen; same canonical state as
  /// the music card (SSE + optional fallback poll). Resolves the app-wide
  /// shared controller when present, so the chip never opens a second stream.
  late final SpotifyControllerOwner _spotifyOwner = SpotifyControllerOwner(
    api: widget.api,
    interval: widget.pollInterval,
  );

  SpotifyPlayerController get _spotify => _spotifyOwner.controller;

  /// Exit/snap-back driver for the swipe-up-to-wake gesture.
  late final AnimationController _fling = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Interactive upward drag in logical px (0 = resting, negative = lifted).
  double _drag = 0.0;
  bool _leaving = false;

  double get _dragOpacity => (1 + _drag / 480).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _scheduleNextMinute();
    // Prefetch cache first: the home warms it while loading, so the idle
    // screen usually paints the temperature on frame one.
    _weather = WeatherRepository.cached;
    _loadWeather();
    // Best-effort refresh every 10 minutes; failures keep the last reading.
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _loadWeather(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spotifyOwner.attach(context);
    _spotifyOwner.start();
  }

  void _scheduleNextMinute() {
    _timer?.cancel();
    final now = DateTime.now();
    _now = now;
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final delay = nextMinute.difference(now);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextMinute();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _weatherTimer?.cancel();
    _weatherRepo.close();
    _spotifyOwner.dispose();
    _fling.dispose();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    final reading = await _weatherRepo.current();
    if (!mounted || reading == null) return;
    setState(() => _weather = reading);
  }

  /// Compact read-only now-playing chip for the idle screen, mirroring the
  /// weather corner. Hidden when no track is loaded; state comes from the
  /// shared canonical controller (SSE + optional fallback poll).
  Widget _sleepNowPlaying() {
    final track = _spotify.track;
    if (track == null) return const SizedBox.shrink();
    final name = track['name']?.toString() ?? '';
    final artist = track['artist']?.toString() ?? '';
    final imageUrl = track['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    if (name.isEmpty && artist.isEmpty && !hasImage) {
      return const SizedBox.shrink();
    }
    Widget fallback() => Container(
      color: const Color(0xFF262B3D).withValues(alpha: 0.7),
      child: const Icon(
        Icons.music_note_rounded,
        size: 24,
        color: Colors.white54,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, _, _) => fallback(),
                  )
                : fallback(),
          ),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.isEmpty ? 'Sin título' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 12, color: Color(0x66000000))],
                ),
              ),
              if (artist.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    decoration: TextDecoration.none,
                    color: Colors.white70,
                    shadows: [Shadow(blurRadius: 12, color: Color(0x66000000))],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Tablet-style wake: drag the sleep screen up (the bottom pill hints it)
  /// and it slides away revealing home. Tap still wakes too.
  void _onDragUpdate(DragUpdateDetails details) {
    if (_leaving) return;
    setState(() {
      _drag = (_drag + details.delta.dy).clamp(-320.0, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_leaving) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -600 || _drag < -140) {
      _leaving = true;
      _animateDragTo(-MediaQuery.sizeOf(context).height, wake: true);
    } else if (_drag != 0) {
      _animateDragTo(0, wake: false);
    }
  }

  void _animateDragTo(double target, {required bool wake}) {
    final animation = Tween(begin: _drag, end: target).animate(
      CurvedAnimation(
        parent: _fling,
        curve: wake ? Curves.easeIn : Curves.easeOut,
      ),
    );
    void listener() {
      if (!mounted) return;
      setState(() => _drag = animation.value);
    }

    _fling.addListener(listener);
    _fling.forward(from: 0).whenComplete(() {
      _fling.removeListener(listener);
      if (!mounted || !wake) return;
      widget.onWake();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    // Interactive reveal offset: the sheet peeks from the bottom edge while
    // the home drag owns it, fullscreen once presented.
    final liftOffset = widget.liftPx.isInfinite
        ? 0.0
        : math.max(0.0, MediaQuery.sizeOf(context).height - widget.liftPx);
    final gestures = widget.gesturesEnabled && !_leaving;
    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: gestures ? widget.onWake : null,
      onVerticalDragUpdate: gestures ? _onDragUpdate : null,
      onVerticalDragEnd: gestures ? _onDragEnd : null,
      child: Transform.translate(
        offset: Offset(0, _drag + liftOffset),
        child: Container(
          constraints: const BoxConstraints.expand(),
          // Simple dark gradient fallback behind the photo (no blurred
          // shapes); the photo covers it when the asset exists.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101828), Color(0xFF1C2742)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo background; a missing asset falls back to the
              // gradient above instead of breaking the screen.
              Image.asset(
                'assets/images/Fondo1.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
              // Dark veil so white text stays legible over the photo.
              Container(color: Colors.black.withValues(alpha: 0.35)),
              SafeArea(
                // Reference layout, responsive: vertical positions are a
                // fraction of the available height (not fixed px), so the
                // clock and hint scale with the window while the photo
                // re-crops behind them. Lower third stays empty.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final clockTop = constraints.maxHeight * 0.20;
                    return Stack(
                      children: [
                        // Weather + date: top-left corner, 24px padding.
                        // Big icon above, real temperature beside it and
                        // date below, like the reference. Until the reading
                        // arrives (or offline) only icon + date show.
                        Positioned(
                          top: 24,
                          left: 24,
                          right: 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    weatherIconFor(
                                      _weather?.code,
                                      isDay: _weather?.isDay ?? true,
                                    ),
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                  if (_weather != null) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      _weather!.label,
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.none,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 12,
                                            color: Color(0x66000000),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _sleepDateLabel(_now),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 12,
                                      color: Color(0x66000000),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Now-playing chip: top-right mirror of the weather
                        // block; hidden while nothing is loaded.
                        Positioned(
                          top: 24,
                          right: 24,
                          child: ListenableBuilder(
                            listenable: _spotify,
                            builder: (context, _) => _sleepNowPlaying(),
                          ),
                        ),
                        // Clock: horizontally centered, upper third.
                        Positioned(
                          top: clockTop,
                          left: 0,
                          right: 0,
                          child: Text(
                            '$hour:$minute',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 128,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                              letterSpacing: -2,
                              height: 1.0,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  blurRadius: 32,
                                  color: Color(0x66000000),
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Hint right under the clock, centered with it.
                        Positioned(
                          top: clockTop + 152,
                          left: 0,
                          right: 0,
                          child: const Text(
                            'Deslizá hacia arriba o tocá para continuar',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              decoration: TextDecoration.none,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        // Tablet-style gesture pill: hints swipe-up-to-wake.
                        Positioned(
                          bottom: 40,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 134,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!widget.animateEntrance) return content;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity * _dragOpacity, child: child),
      child: content,
    );
  }
}

String _sleepDateLabel(DateTime now) {
  const weekdays = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  final weekday = weekdays[now.weekday - 1];
  final capitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$capitalized, ${now.day} de ${months[now.month - 1]}';
}

/// `mm:ss` for a playback position/duration in milliseconds.
String _formatPlaybackTime(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).floor();
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// `name · artist` for a queue item, degrading to whichever field exists.
String _formatQueueItem(Map<String, dynamic> item) {
  final name = item['name']?.toString() ?? '';
  final artist = item['artist']?.toString() ?? '';
  if (artist.isEmpty) return name;
  if (name.isEmpty) return artist;
  return '$name · $artist';
}

/// `name — artist` for the single up-next line, so the enclosing
/// "A continuación ·" prefix does not double the separator dot.
String _formatUpNextItem(Map<String, dynamic> item) {
  final name = item['name']?.toString() ?? '';
  final artist = item['artist']?.toString() ?? '';
  if (artist.isEmpty) return name;
  if (name.isEmpty) return artist;
  return '$name — $artist';
}
