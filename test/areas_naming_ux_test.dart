import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/adaptive/adaptive_layout.dart';
import 'package:gamma_app/adaptive/adaptive_scope.dart';
import 'package:gamma_app/adaptive/adaptive_surface_preferences.dart';
import 'package:gamma_app/data/api_client.dart';
import 'package:gamma_app/features/areas/areas_page.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/devices_page.dart';

/// F2-C widget tests: Areas CRUD, device/endpoint rename, physical vs
/// controlled selectors, backend semantic display rendering.
void main() {
  group('AreasPage', () {
    testWidgets('shows empty state when no areas', (tester) async {
      final repo = _FakeRepo(areas: const []);
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay áreas.'), findsOneWidget);
    });

    testWidgets('lists areas with aliases', (tester) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala', aliases: ['sala principal']),
          HomeArea(id: 'area_COCINA', name: 'Cocina'),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Sala'), findsOneWidget);
      expect(find.text('Cocina'), findsOneWidget);
      expect(find.text('Aliases: sala principal'), findsOneWidget);
    });

    testWidgets('create area submits name and aliases', (tester) async {
      final repo = _FakeRepo(areas: const []);
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Patio');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
      await tester.pumpAndSettle();
      expect(repo.created.single.$1, 'Patio');
      expect(repo.created.single.$2, isEmpty);
      expect(find.text('Patio'), findsOneWidget);
    });

    testWidgets('edit area renames keeping opaque id', (tester) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
      );
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sala'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sala principal');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(repo.updated, ['area_SALA']);
      expect(find.text('Sala principal'), findsOneWidget);
    });

    testWidgets('delete unused area removes it after canonical refresh', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala'),
          HomeArea(id: 'area_COCINA', name: 'Cocina'),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.trash).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('Sala'), findsNothing);
      expect(find.text('Cocina'), findsOneWidget);
    });

    testWidgets('delete referenced area shows conflict and keeps area', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.trash));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se puede eliminar esta área porque todavía está asignada a uno o más dispositivos o canales.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sala'), findsOneWidget);
    });
  });

  group('Device detail naming', () {
    testWidgets('rename device sends user_name and converges', (tester) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            userName: null,
            providerName: 'Sala Comedor',
            physicalAreaId: 'area_SALA',
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      await tester.tap(find.byIcon(CupertinoIcons.pencil_outline).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mi interruptor');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(repo.renamedDevices, [('dev_1', 'Mi interruptor')]);
      expect(find.text('Mi interruptor'), findsOneWidget);
    });

    testWidgets('clear device name sends null', (tester) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            userName: 'Nombre viejo',
            providerName: 'Sala Comedor',
            physicalAreaId: 'area_SALA',
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      await tester.tap(find.byIcon(CupertinoIcons.pencil_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restablecer nombre'));
      await tester.pumpAndSettle();
      expect(repo.renamedDevices, [('dev_1', null)]);
    });

    testWidgets('provider name renders read-only secondary', (tester) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            userName: 'Mi nombre',
            providerName: 'Sala Comedor',
            physicalAreaId: 'area_SALA',
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      expect(find.text('Mi nombre'), findsOneWidget);
      expect(find.text('Sala Comedor'), findsOneWidget);
    });
  });

  group('Endpoint naming', () {
    testWidgets('renders backend semantic display name', (tester) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                displayNameSemantic: 'Luz',
                displayNameGlobal: 'Sala · Luz',
                controlledAreaId: 'area_SALA',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      expect(find.text('Luz'), findsWidgets);
      expect(find.text('Sala · Luz'), findsOneWidget);
    });

    testWidgets('endpoint rename sends user_name', (tester) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      await tester.tap(find.byIcon(CupertinoIcons.pencil_outline).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Luz de techo');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(repo.renamedEndpoints, [('dev_1', 'relay_1', 'Luz de techo')]);
    });
  });

  group('Selectors', () {
    testWidgets('physical and controlled labels appear above selectors', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala'),
          HomeArea(id: 'area_PASILLO', name: 'Pasillo'),
        ],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      expect(find.text('Ubicación física'), findsOneWidget);
      expect(find.text('Área que controla'), findsOneWidget);
      // Selector titles are rendered ABOVE the selector control: the label
      // text sits above the middle of the selector widget (the dropdown
      // control occupies the lower part of the composed field).
      final labelRect = tester.getRect(find.text('Ubicación física'));
      final fieldRect = tester.getRect(
        find.byKey(const Key('physical-area-dropdown')),
      );
      // Label bottom must be above the field's vertical center (the control).
      expect(labelRect.bottom, lessThan(fieldRect.center.dy));
    });

    testWidgets('physical change does not mutate endpoint areas', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala'),
          HomeArea(id: 'area_PASILLO', name: 'Pasillo'),
        ],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      await tester.tap(find.byKey(const Key('physical-area-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pasillo').last);
      await tester.pumpAndSettle();
      expect(repo.physicalAreaWrites, [('dev_1', 'area_PASILLO')]);
      expect(repo.endpointAreaWrites, isEmpty);
    });
  });

  f2cClosureHardeningTests();
  f2cReferentialHardeningTests();
}

Future<void> _pumpDetail(WidgetTester tester, _FakeRepo repo) async {
  // Tall viewport so endpoint editors (area + role selectors) are built by
  // the lazy CustomScrollView; otherwise their widgets never exist.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DevicesPage(api: FakeApiForDetail(), repository: repo),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The detail is reached through the landing's devices button and the flat
  // device list.
  await tester.tap(find.byKey(const ValueKey('open-devices-list')));
  await tester.pumpAndSettle();
  final device = repo.devices.first;
  await tester.tap(find.text(device.name));
  await tester.pumpAndSettle();
  // Per-channel configuration is collapsed by default; expand it so the
  // area/role selectors and rename affordances are built.
  await tester.tap(find.text('Configuración'));
  await tester.pumpAndSettle();
}

/// Pumps DevicesPage on the desktop surface at a narrow width: the desktop
/// master list is where the 'Habitaciones' entry (and its refetch-on-pop
/// contract) lives after the room grid left the mobile landing.
Future<void> _pumpDesktopDevices(WidgetTester tester, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AppAdaptiveScope(
        windowClass: AppWindowClass.expanded,
        effectiveSurface: EffectiveAppSurface.desktop,
        controller: AdaptiveSurfaceModeController(),
        child: Scaffold(
          body: DevicesPage(api: FakeApiForDetail(), repository: repo),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Minimal ApiClient subclass so DevicesPage construction works; the repo is
/// injected and used instead.
class FakeApiForDetail extends ApiClient {
  FakeApiForDetail() : super(baseUrl: 'http://fake');
}

DeviceEndpoint _endpoint({
  required String id,
  required String name,
  String? controlledAreaId,
  String? userName,
  String? displayNameSemantic,
  String? displayNameGlobal,
}) {
  return DeviceEndpoint(
    id: id,
    name: name,
    kind: DeviceKind.unknown,
    capabilities: const {},
    controlledAreaId: controlledAreaId,
    userName: userName,
    displayNameSemantic: displayNameSemantic,
    displayNameGlobal: displayNameGlobal,
  );
}

PhysicalDevice _device({
  required String id,
  required String name,
  String? userName,
  String? providerName,
  String? physicalAreaId,
  List<DeviceEndpoint> endpoints = const [],
}) {
  return PhysicalDevice(
    id: id,
    name: name,
    kind: DeviceKind.unknown,
    provider: 'tuya',
    providerDeviceId: '',
    model: 'M',
    provisioningState: DeviceProvisioningState.configured,
    online: true,
    health: DeviceHealthState.online,
    endpoints: endpoints,
    physicalAreaId: physicalAreaId,
    userName: userName,
    providerName: providerName,
  );
}

class _FakeRepo implements DeviceInventoryRepository {
  _FakeRepo({this.areas = const [], this.devices = const []});

  List<HomeArea> areas;
  List<PhysicalDevice> devices;
  final created = <(String, List<String>)>[];
  final updated = <String>[];
  final updatedAliases = <List<String>>[];
  int loadCalls = 0;
  int areaLoadCalls = 0;
  Object? deleteError;
  Object? listError;
  int listFailAfterLoads = 0;
  final renamedDevices = <(String, String?)>[];
  final renamedEndpoints = <(String, String, String?)>[];
  final physicalAreaWrites = <(String, String?)>[];
  final endpointAreaWrites = <(String, String, String?)>[];

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async {
    loadCalls++;
    return _snapshot();
  }

  @override
  Future<DeviceInventorySnapshot> discover() async => _snapshot();

  DeviceInventorySnapshot _snapshot() {
    // Emulate backend DTO refresh: the global display for endpoints follows
    // the canonical Area name (backend-owned; never Dart recomputation in
    // production — the fake models what the backend DTO returns).
    final areaById = {for (final a in areas) a.id: a};
    final refreshedDevices = [
      for (final d in devices)
        d.copyWith(
          endpoints: [
            for (final e in d.endpoints)
              e.copyWith(
                displayNameGlobal:
                    e.displayNameGlobal == null || e.controlledAreaId == null
                    ? e.displayNameGlobal
                    : '${areaById[e.controlledAreaId]?.name} · ${e.displayNameSemantic ?? e.name}',
              ),
          ],
        ),
    ];
    return DeviceInventorySnapshot(
      areas: List.unmodifiable(areas),
      devices: List.unmodifiable(refreshedDevices),
      gateways: const [],
      lastDiscoveryLabel: '',
    );
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    physicalAreaWrites.add((deviceId, areaId));
    return devices
        .firstWhere((d) => d.id == deviceId)
        .copyWith(physicalAreaId: areaId);
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    endpointAreaWrites.add((deviceId, endpointId, areaId));
    return devices.firstWhere((d) => d.id == deviceId);
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    final device = devices.firstWhere((d) => d.id == deviceId);
    final updated = device.copyWith(
      endpoints: device.endpoints
          .map((e) => e.id == endpointId ? e.copyWith(semanticRole: role) : e)
          .toList(),
    );
    devices[devices.indexOf(device)] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    renamedDevices.add((deviceId, userName));
    return devices
        .firstWhere((d) => d.id == deviceId)
        .copyWith(userName: userName);
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    renamedEndpoints.add((deviceId, endpointId, userName));
    return devices.firstWhere((d) => d.id == deviceId);
  }

  @override
  Future<List<HomeArea>> listAreas() async {
    areaLoadCalls++;
    if (listError != null && areaLoadCalls > listFailAfterLoads) {
      throw listError!;
    }
    return List.unmodifiable(areas);
  }

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    created.add((name, aliases));
    final area = HomeArea(id: 'area_N', name: name, aliases: aliases);
    areas = [...areas, area];
    return area;
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    updated.add(areaId);
    if (aliases != null) updatedAliases.add(aliases);
    final area = HomeArea(
      id: areaId,
      name: name ?? '',
      aliases: aliases ?? const [],
    );
    areas = [
      for (final a in areas)
        if (a.id == areaId) area else a,
    ];
    return area;
  }

  @override
  Future<void> deleteArea(String areaId) async {
    if (deleteError != null) throw deleteError!;
    final index = areas.indexWhere((area) => area.id == areaId);
    if (index < 0) throw ApiException(404, {'detail': 'área no encontrada'});
    final used = devices.any(
      (device) =>
          device.physicalAreaId == areaId ||
          device.endpoints.any(
            (endpoint) => endpoint.controlledAreaId == areaId,
          ),
    );
    if (used) {
      throw ApiException(409, {'detail': 'área en uso'});
    }
    areas = [
      for (final area in areas)
        if (area.id != areaId) area,
    ];
  }

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}

/// F2-C closure hardening tests: missing contract proofs and convergence.
void f2cClosureHardeningTests() {
  group('Endpoint user_name clear', () {
    testWidgets('reset sends null and restores semantic display', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
                userName: 'Lámpara Totoro',
                displayNameSemantic: 'Lámpara Totoro',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      await tester.tap(find.byIcon(CupertinoIcons.pencil_outline).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restablecer nombre'));
      await tester.pumpAndSettle();
      expect(repo.renamedEndpoints, [('dev_1', 'relay_1', null)]);
    });
  });

  group('Controlled-area clear', () {
    testWidgets('Sin asignar sends null and keeps physical area', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala'),
          HomeArea(id: 'area_PASILLO', name: 'Pasillo'),
        ],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_PASILLO',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      // Open the second dropdown (endpoint controlled-area) and pick
      // "Sin asignar" (null).
      final dropdowns = find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString().contains('DropdownButtonFormField'),
      );
      await tester.ensureVisible(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin asignar').last);
      await tester.pumpAndSettle();
      expect(repo.endpointAreaWrites, [('dev_1', 'relay_1', null)]);
    });
  });

  group('Endpoint→physical independence', () {
    testWidgets('endpoint change leaves physical area unchanged', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala'),
          HomeArea(id: 'area_COCINA', name: 'Cocina'),
        ],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
              ),
            ],
          ),
        ],
      );
      await _pumpDetail(tester, repo);
      final dropdowns = find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString().contains('DropdownButtonFormField'),
      );
      await tester.ensureVisible(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cocina').last);
      await tester.pumpAndSettle();
      expect(repo.endpointAreaWrites, [('dev_1', 'relay_1', 'area_COCINA')]);
      expect(repo.physicalAreaWrites, isEmpty);
    });
  });

  group('Alias add/remove', () {
    testWidgets('edits explicit aliases exactly', (tester) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_SALA', name: 'Sala', aliases: ['estancia']),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sala'));
      await tester.pumpAndSettle();
      // Replace the existing alias with a new explicit one.
      expect(
        find.byType(TextField).evaluate().length,
        2,
        reason: 'dialog should have name + alias fields',
      );
      await tester.enterText(find.byType(TextField).at(1), 'sala principal');
      final guardar = find.widgetWithText(FilledButton, 'Guardar');
      await tester.ensureVisible(guardar);
      await tester.pumpAndSettle();
      await tester.tap(guardar);
      await tester.pumpAndSettle();
      expect(repo.updated, isNotEmpty);
      expect(repo.updatedAliases, isNotEmpty);
      expect(repo.updatedAliases.last, ['sala principal']);
    });
  });

  group('Area rename convergence', () {
    testWidgets('DevicesPage refetches inventory after Areas pop', (
      tester,
    ) async {
      // _open() in DevicesPage calls _load() after Navigator.push returns,
      // so a rename inside AreasPage converges the canonical device DTO.
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
                displayNameSemantic: 'Luz',
                displayNameGlobal: 'Sala · Luz',
              ),
            ],
          ),
        ],
      );
      await _pumpDesktopDevices(tester, repo);
      expect(find.text('Sala · Luz'), findsNothing);
      // Open the desktop Areas workspace ('Habitaciones'), rename, and return:
      // the devices workspace refetches on pop.
      await tester.tap(find.text('Habitaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sala principal');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      // Back to the Areas list, then to the devices workspace. The Areas
      // workspace is a bare pane (no AppBar), so pop its route directly.
      await tester.pageBack();
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      // The fake repo refreshes its devices with the new global display.
      expect(repo.loadCalls, greaterThan(1));
    });
  });
}

/// F2-C referential-integrity hardening tests: DELETE 404 refresh and
/// visible rename convergence.
void f2cReferentialHardeningTests() {
  group('DELETE 404 refresh', () {
    testWidgets('404 triggers one canonical Areas reload', (tester) async {
      final repo = _FakeRepo(
        areas: const [
          HomeArea(id: 'area_STALE', name: 'Fantasma'),
          HomeArea(id: 'area_SALA', name: 'Sala'),
        ],
      )..deleteError = ApiException(404, {'detail': 'área no encontrada'});
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      final loadsBefore = repo.areaLoadCalls;
      await tester.tap(find.byIcon(CupertinoIcons.trash).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      // Exactly ONE canonical reload happened on 404.
      expect(repo.areaLoadCalls, loadsBefore + 1);
      // The message truthfully says the list was refreshed.
      expect(
        find.text('El área ya no existe. Se actualizó la lista.'),
        findsOneWidget,
      );
    });

    testWidgets('404 with refresh failure does NOT claim refresh', (
      tester,
    ) async {
      final repo =
          _FakeRepo(
              areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
            )
            ..deleteError = ApiException(404, {'detail': 'área no encontrada'})
            ..listError = ApiException(503, {'detail': 'backend down'})
            ..listFailAfterLoads = 1;
      await tester.pumpWidget(MaterialApp(home: AreasPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.trash));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      // Truthful failure wording; no false "se actualizó".
      expect(
        find.text('El área ya no existe. Se actualizó la lista.'),
        findsNothing,
      );
      expect(
        find.text('El área ya no existe, pero no se pudo actualizar la lista.'),
        findsOneWidget,
      );
      // Mutation flag reset (delete can be retried).
      expect(repo.areaLoadCalls, 2); // initial + one reload attempt
    });
  });

  group('Area rename visible convergence', () {
    testWidgets('global display converges to renamed backend DTO', (
      tester,
    ) async {
      final repo = _FakeRepo(
        areas: const [HomeArea(id: 'area_SALA', name: 'Sala')],
        devices: [
          _device(
            id: 'dev_1',
            name: 'Interruptor triple',
            physicalAreaId: 'area_SALA',
            endpoints: [
              _endpoint(
                id: 'relay_1',
                name: 'Luz',
                controlledAreaId: 'area_SALA',
                displayNameSemantic: 'Luz',
                displayNameGlobal: 'Sala · Luz',
              ),
            ],
          ),
        ],
      );
      await _pumpDesktopDevices(tester, repo);
      // Rename through the desktop Areas workspace and return; the fake repo
      // emulates the backend DTO refresh: after updateArea the device global
      // display uses the new Area name WITHOUT Dart recomputation.
      await tester.tap(find.text('Habitaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop-area-area_SALA')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sala principal');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The Areas workspace is a bare pane (no AppBar): pop its route directly.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      // Open the device detail: the endpoint global display is the backend DTO
      // value now reflecting the renamed Area.
      await tester.tap(find.byKey(const ValueKey('desktop-device-dev_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();
      expect(find.text('Sala principal · Luz'), findsOneWidget);
    });
  });
}
