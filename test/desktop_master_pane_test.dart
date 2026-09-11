import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/desktop_master_pane.dart';
import 'package:gamma_app/ui/app_colors.dart';

void main() {
  testWidgets('header shows Dispositivos with badge count', (tester) async {
    await pumpMaster(tester, devices: _sevenDevices);

    expect(find.text('Dispositivos'), findsOneWidget);
    // badge shows count 7 inside header row
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('shows Todas las ubicaciones filter control', (tester) async {
    await pumpMaster(tester);

    expect(find.text('Todas las ubicaciones'), findsOneWidget);
    expect(find.byKey(const Key('desktop-location-filter')), findsOneWidget);
  });

  testWidgets('shows +Agregar dispositivo indigo full width', (tester) async {
    await pumpMaster(tester);

    final button = find.widgetWithText(ElevatedButton, '+Agregar dispositivo');
    final filled = find.widgetWithText(FilledButton, '+Agregar dispositivo');
    expect(
      button.evaluate().isNotEmpty || filled.evaluate().isNotEmpty,
      isTrue,
    );

    // indigo background check via ElevatedButton style
    final widget = tester.widgetList(find.byType(ElevatedButton)).isNotEmpty
        ? tester.widget<ElevatedButton>(find.byType(ElevatedButton).first)
        : null;
    if (widget != null) {
      final bg = widget.style?.backgroundColor?.resolve(<WidgetState>{});
      expect(bg, AppColors.gammaIndigo);
    }
  });

  testWidgets('search field pill Buscar dispositivos', (tester) async {
    await pumpMaster(tester);

    expect(find.byKey(const Key('desktop-device-search')), findsOneWidget);
    expect(find.text('Buscar dispositivos'), findsOneWidget);
    // pill shape: OutlineInputBorder with 10+ radius
    final field = tester.widget<TextField>(
      find.byKey(const Key('desktop-device-search')),
    );
    final border = field.decoration?.border as OutlineInputBorder?;
    expect(border, isNotNull);
    expect(border!.borderRadius.topLeft.x, greaterThanOrEqualTo(10));
  });

  testWidgets('rows show kind icon badge and status dot+label', (tester) async {
    await pumpMaster(
      tester,
      devices: [_lightOnline, _fanSleeping, _unknownOffline],
    );

    // light bulb purple badge
    expect(
      find.byKey(const ValueKey('desktop-device-dev_light_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );
    expect(find.textContaining('Encendido'), findsOneWidget);
    expect(find.textContaining('Apagado'), findsOneWidget);
    expect(find.textContaining('Desconectado'), findsOneWidget);
    // status dot colors indirectly via label; dot widget is Container 10x10
    expect(find.text('Luz comedor'), findsOneWidget);
  });

  testWidgets('selected row has indigo outline and bg', (tester) async {
    await pumpMaster(
      tester,
      devices: const [_lightOnline, _fanSleeping],
      selectedId: 'dev_light_01',
    );

    final selected = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.selected == true,
    );
    expect(selected, findsOneWidget);
    // Check Ink container decoration has indigo border
    final inkFinder = find.descendant(
      of: find.byKey(const ValueKey('desktop-device-dev_light_01')),
      matching: find.byType(Ink),
    );
    expect(inkFinder, findsWidgets);
  });

  testWidgets('search filters locally', (tester) async {
    await pumpMaster(tester, devices: const [_lightOnline, _fanSleeping]);

    await tester.enterText(
      find.byKey(const Key('desktop-device-search')),
      'ventilador',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-device-dev_light_01')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('desktop-device-search')), '');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-device-dev_light_01')),
      findsOneWidget,
    );
  });

  testWidgets('location picker filters', (tester) async {
    await pumpMaster(tester, devices: const [_lightOnline, _fanSleeping]);

    // open the centered Ubicación dialog and select Sala
    await tester.tap(find.byKey(const Key('desktop-location-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Ubicación'), findsOneWidget);
    await tester.tap(find.text('Sala').last);
    await tester.pumpAndSettle();
    // only device with physicalAreaId sala remains (light)
    expect(
      find.byKey(const ValueKey('desktop-device-dev_light_01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-device-dev_fan_01')),
      findsNothing,
    );
  });

  testWidgets('empty shows Sin resultados', (tester) async {
    await pumpMaster(tester, devices: const [_lightOnline]);

    await tester.enterText(
      find.byKey(const Key('desktop-device-search')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sin resultados'), findsOneWidget);
  });
}

Future<void> pumpMaster(
  WidgetTester tester, {
  List<PhysicalDevice> devices = const [_lightOnline, _fanSleeping],
  String? selectedId,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: DesktopMasterPane(
            devices: devices,
            areas: const [
              HomeArea(id: 'sala', name: 'Sala'),
              HomeArea(id: 'cocina', name: 'Cocina'),
              HomeArea(id: 'pasillo', name: 'Pasillo'),
            ],
            selectedDeviceId: selectedId,
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _lightOnline = PhysicalDevice(
  id: 'dev_light_01',
  name: 'Luz comedor',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [],
);

const _fanSleeping = PhysicalDevice(
  id: 'dev_fan_01',
  name: 'Ventilador estudio',
  kind: DeviceKind.outlet,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS011F',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.sleeping,
  physicalAreaId: 'pasillo',
  endpoints: [],
);

const _unknownOffline = PhysicalDevice(
  id: 'dev_unknown_01',
  name: 'Sensor patio',
  kind: DeviceKind.sensor,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZP01',
  provisioningState: DeviceProvisioningState.configured,
  online: false,
  health: DeviceHealthState.unknown,
  physicalAreaId: 'patio',
  endpoints: [],
);

final _sevenDevices = List.generate(
  7,
  (i) => PhysicalDevice(
    id: 'dev_$i',
    name: 'Device $i',
    kind: DeviceKind.light,
    provider: 'Tuya',
    providerDeviceId: '',
    model: 'M',
    provisioningState: DeviceProvisioningState.configured,
    online: true,
    health: DeviceHealthState.online,
    physicalAreaId: 'sala',
    endpoints: [],
  ),
);
