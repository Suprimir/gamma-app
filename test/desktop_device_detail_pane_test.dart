import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamma_app/adaptive/adaptive_feature_controller.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/features/devices/desktop_device_detail_pane.dart';
import 'package:gamma_app/ui/app_colors.dart';

import 'fixtures/command_device_fake_repo.dart';

void main() {
  group('DesktopDeviceDetailPane', () {
    testWidgets('shows title Luz techo cocina + edit button', (tester) async {
      await pumpDetail(tester, device: _lightOnline);
      expect(find.text('Luz techo cocina'), findsOneWidget);
      // Device rename affordance plus one rename affordance per channel.
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
    });

    testWidgets('subtitle dot En línea · Cocina with success color', (
      tester,
    ) async {
      await pumpDetail(tester, device: _lightOnline);
      // subtitle contains En línea and Cocina and dot
      expect(find.textContaining('En línea'), findsOneWidget);
      expect(find.textContaining('Cocina'), findsWidgets);
      // dot container 8x8 with success color
      final dotFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == AppColors.statusEncendido,
      );
      expect(dotFinder, findsWidgets);
      // also check middle dot or bullet present
      expect(find.textContaining('●'), findsWidgets);
    });

    testWidgets(
      'Ubicación física card with Habitación dropdown dirty no repo call',
      (tester) async {
        final repo = _DetailFakeRepo(devices: [_lightOnline]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_light_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        expect(find.text('Ubicación física'), findsOneWidget);
        expect(find.text('Habitación'), findsOneWidget);
        expect(
          find.byKey(const Key('desktop-location-dropdown')),
          findsOneWidget,
        );

        // change location to Sala
        await tester.tap(find.byKey(const Key('desktop-location-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sala').last);
        await tester.pumpAndSettle();

        expect(controller.pendingLocationId, 'sala');
        expect(controller.hasPendingChanges, isTrue);
        expect(repo.assignCalls, isEmpty);
        // dropdown value shows Sala
        expect(find.text('Sala'), findsWidgets);
      },
    );

    testWidgets(
      'Controles muestran la funcion real del canal (luz regulable)',
      (tester) async {
        await pumpDetail(tester, device: _lightOnline);
        expect(find.text('Controles del dispositivo'), findsOneWidget);
        // Friendly per-channel function, no fake global switch/brightness.
        expect(find.text('Luz regulable'), findsWidgets);
        expect(find.text('Encendida'), findsNothing);
        expect(find.text('Brillo'), findsNothing);
        expect(find.text('10%'), findsNothing);
        expect(find.byType(Switch), findsNothing);
        // Each channel exposes its real mutations.
        expect(
          find.byKey(const Key('desktop-channel-area-light')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('desktop-channel-role-light')),
          findsOneWidget,
        );
        expect(find.text('Controla'), findsOneWidget);
        expect(find.text('Tipo'), findsWidgets);
      },
    );

    testWidgets('channel area change persists via repository', (tester) async {
      final repo = _DetailFakeRepo(devices: [_lightOnline]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_light_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      await tester.tap(find.byKey(const Key('desktop-channel-area-light')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sala').last);
      await tester.pumpAndSettle();

      expect(repo.endpointAreaCalls, [('dev_light_01', 'light', 'sala')]);
      expect(
        controller.snapshot!.devices
            .firstWhere((d) => d.id == 'dev_light_01')
            .endpoints
            .firstWhere((e) => e.id == 'light')
            .controlledAreaId,
        'sala',
      );
    });

    testWidgets('channel role change persists via repository', (tester) async {
      final repo = _DetailFakeRepo(devices: [_tripleChannel]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_triple_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      // Triple switch exposes one independent row per channel.
      expect(find.text('3 canales independientes'), findsOneWidget);
      expect(find.text('Canal 1'), findsOneWidget);
      expect(find.text('Canal 2'), findsOneWidget);
      expect(find.text('Canal 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('desktop-channel-role-relay_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ventilador').last);
      await tester.pumpAndSettle();

      expect(repo.roleCalls, [('dev_triple_01', 'relay_1', 'fan')]);
    });

    testWidgets('sensor shows Solo lectura without power controls', (
      tester,
    ) async {
      await pumpDetail(tester, device: _sensorNoBrightness);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Encendida'), findsNothing);
      expect(find.text('10%'), findsNothing);
      expect(find.text('Sensor de movimiento'), findsWidgets);
      expect(find.text('Solo lectura'), findsWidgets);
    });

    testWidgets('canonical POWER capability is honored (uppercase)', (
      tester,
    ) async {
      await pumpDetail(tester, device: _lightCanonicalPower);
      expect(find.text('Luz regulable'), findsWidgets);
      expect(find.text('Solo lectura'), findsNothing);
    });

    testWidgets('Información técnica ExpansionTile collapsed then expands', (
      tester,
    ) async {
      await pumpDetail(tester, device: _lightOnline);
      expect(find.text('Información técnica'), findsOneWidget);
      // initially collapsed: ID row not visible
      expect(find.textContaining('ID'), findsNothing);
      // tap to expand
      await tester.tap(find.text('Información técnica'));
      await tester.pumpAndSettle();
      expect(find.textContaining('dev_light_01'), findsOneWidget);
      expect(find.textContaining('ZB-DL01'), findsOneWidget);
      expect(find.textContaining('Moes'), findsOneWidget);
      expect(find.textContaining('Gateway'), findsWidgets);
    });

    testWidgets('Guardar cambios disabled when clean enabled when dirty', (
      tester,
    ) async {
      final repo = _DetailFakeRepo(devices: [_lightOnline]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_light_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      final saveFinder = find.text('Guardar cambios');
      expect(saveFinder, findsOneWidget);
      ElevatedButton btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Guardar cambios'),
      );
      expect(btn.onPressed, isNull); // disabled when clean

      // make dirty
      controller.markPendingLocation('sala');
      await tester.pumpAndSettle();
      btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Guardar cambios'),
      );
      expect(btn.onPressed, isNotNull);
      // indigo background
      final bg = btn.style?.backgroundColor?.resolve(<WidgetState>{});
      expect(bg, AppColors.gammaIndigo);
    });

    testWidgets(
      'toast dark pill #1F2937 shows on save success with X dismiss',
      (tester) async {
        final repo = _DetailFakeRepo(devices: [_lightOnline]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_light_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        controller.markPendingLocation('cocina');
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Guardar cambios'),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Cambios guardados'), findsOneWidget);
        // dark pill color #1F2937
        final containers = tester.widgetList<Container>(find.byType(Container));
        final hasDark = containers.any(
          (c) =>
              c.color == AppColors.toastDark ||
              (c.decoration as BoxDecoration?)?.color == AppColors.toastDark,
        );
        expect(hasDark, isTrue);
        expect(find.text('✓'), findsWidgets);
        // X dismiss
        expect(find.byIcon(Icons.close), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.textContaining('Cambios guardados'), findsNothing);
      },
    );

    testWidgets('toast auto-dismiss after 3s', (tester) async {
      final repo = _DetailFakeRepo(devices: [_lightOnline]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_light_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      controller.markPendingLocation('cocina');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cambios guardados'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cambios guardados'), findsNothing);
    });

    testWidgets('SnackBar on failure keeps dirty', (tester) async {
      final repo = _DetailFakeRepo(
        devices: [_lightOnline],
        shouldFailAssign: true,
      );
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_light_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      controller.markPendingLocation('cocina');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Cambios guardados'), findsNothing);
      expect(controller.hasPendingChanges, isTrue);
    });

    testWidgets(
      'single-channel power switch commands its endpoint and merges the '
      'observation',
      (tester) async {
        final repo = CommandDeviceFakeRepo(devices: const [_commandPowerLight]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_power_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        // One switch only, inside the channel editor: no device-level control
        // exists anymore, even for single-channel devices.
        expect(find.byType(Switch), findsOneWidget);
        final editor = desktopEndpointEditor('Luz');
        final switchFinder = find.descendant(
          of: editor,
          matching: find.byType(Switch),
        );
        expect(switchFinder, findsOneWidget);
        await tester.ensureVisible(switchFinder);
        await tester.pumpAndSettle();

        // No observation: the switch is off but the label carries the truth.
        expect(
          find.descendant(of: editor, matching: find.text('Sin datos')),
          findsOneWidget,
        );
        expect(tester.widget<Switch>(switchFinder).value, isFalse);

        await tester.tap(switchFinder);
        await tester.pump();

        expect(repo.powerCalls, [('dev_power_01', 'light', true)]);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: editor, matching: find.text('Encendido')),
          findsOneWidget,
        );
        expect(tester.widget<Switch>(switchFinder).value, isTrue);
        expect(find.text('Sin datos'), findsNothing);
      },
    );

    testWidgets(
      'channel rename failure keeps the old name and shows the error',
      (tester) async {
        final repo = _DetailFakeRepo(devices: [_lightOnline])
          ..renameError = StateError('rechazado por el backend');
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_light_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        await tester.tap(find.byTooltip('Cambiar nombre del canal'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Nombre nuevo');
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
        await tester.pumpAndSettle();

        expect(find.textContaining('rechazado por el backend'), findsOneWidget);
        expect(find.text('Nombre actualizado'), findsNothing);
        expect(
          controller.snapshot!.devices
              .firstWhere((d) => d.id == 'dev_light_01')
              .endpoints
              .firstWhere((e) => e.id == 'light')
              .userName,
          isNull,
        );
      },
    );

    testWidgets(
      'device rename failure keeps the old name and shows the error',
      (tester) async {
        final repo = _DetailFakeRepo(devices: [_lightOnline])
          ..renameError = StateError('rechazado por el backend');
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_light_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        await tester.tap(find.byTooltip('Cambiar nombre'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Nombre nuevo');
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
        await tester.pumpAndSettle();

        expect(find.textContaining('rechazado por el backend'), findsOneWidget);
        expect(find.text('Nombre actualizado'), findsNothing);
        expect(
          controller.snapshot!.devices
              .firstWhere((d) => d.id == 'dev_light_01')
              .userName,
          isNull,
        );
      },
    );

    testWidgets('test connection reports provider refusal honestly', (
      tester,
    ) async {
      final repo = CommandDeviceFakeRepo(devices: const [_commandPowerLight]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_power_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      await tester.tap(find.text('Probar conexión'));
      await tester.pumpAndSettle();

      expect(
        find.text('El proveedor no soporta identificación'),
        findsOneWidget,
      );
    });

    testWidgets('confirmed observations drive brightness and color temp', (
      tester,
    ) async {
      final device = _commandCapsLight.copyWith(
        endpoints: [
          _commandCapsLight.endpoints.first.copyWith(
            observedCapabilities: const {
              'BRIGHTNESS': EndpointCapabilityObservation(
                value: 42,
                quality: 'confirmed',
              ),
              'COLOR_TEMPERATURE': EndpointCapabilityObservation(
                value: 30,
                quality: 'confirmed',
              ),
            },
          ),
          ..._commandCapsLight.endpoints.skip(1),
        ],
      );
      final repo = CommandDeviceFakeRepo(devices: [device]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      expect(find.text('Brillo'), findsOneWidget);
      expect(find.text('42 %'), findsOneWidget);
      expect(find.text('Temperatura de color'), findsOneWidget);
      expect(find.text('30 %'), findsOneWidget);
    });

    testWidgets('confirmed SPEED percent selects the matching fan level', (
      tester,
    ) async {
      final device = _commandFanCaps.copyWith(
        endpoints: [
          _commandFanCaps.endpoints.first.copyWith(
            observedCapabilities: const {
              'SPEED': EndpointCapabilityObservation(
                value: 67,
                quality: 'confirmed',
              ),
            },
          ),
        ],
      );
      final repo = CommandDeviceFakeRepo(devices: [device]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_fan_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      final fanColumn = find
          .ancestor(of: find.text('Velocidad'), matching: find.byType(Column))
          .first;
      final speedTwo = find.descendant(of: fanColumn, matching: find.text('2'));
      final material = tester.widget<Material>(
        find.ancestor(of: speedTwo, matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.gammaIndigoLight);
    });

    testWidgets('blinds expose the position control with the observation', (
      tester,
    ) async {
      final device = _commandBlindCaps.copyWith(
        endpoints: [
          _commandBlindCaps.endpoints.first.copyWith(
            observedCapabilities: const {
              'POSITION': EndpointCapabilityObservation(
                value: 35,
                quality: 'confirmed',
              ),
            },
          ),
        ],
      );
      final repo = CommandDeviceFakeRepo(devices: [device]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_blind_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      expect(find.text('Posición'), findsOneWidget);
      expect(find.text('35 %'), findsOneWidget);
    });

    testWidgets('mode chips come from the descriptor enum values', (
      tester,
    ) async {
      final repo = CommandDeviceFakeRepo(devices: const [_commandClimateCaps]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_climate_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      expect(find.text('eco'), findsOneWidget);
      expect(find.text('turbo'), findsOneWidget);
      final turbo = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'turbo'),
      );
      expect(turbo.selected, isTrue);
    });

    testWidgets('an out-of-domain mode is still rendered as selected', (
      tester,
    ) async {
      final device = _commandClimateCaps.copyWith(
        endpoints: [
          _commandClimateCaps.endpoints.first.copyWith(
            observedCapabilities: const {
              'MODE': EndpointCapabilityObservation(
                value: 'guard',
                quality: 'confirmed',
              ),
            },
          ),
        ],
      );
      final repo = CommandDeviceFakeRepo(devices: [device]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_climate_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      final guard = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'guard'),
      );
      expect(guard.selected, isTrue);
    });

    testWidgets('save issues canonical actions with mapped values', (
      tester,
    ) async {
      final repo = CommandDeviceFakeRepo(devices: const [_commandCapsLight]);
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      controller.markPendingBrightness(70);
      controller.markPendingFanSpeed(2);
      controller.markPendingClimateMode('manual');
      controller.markPendingPosition(40);
      controller.markPendingColorTemperature(30);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      expect(repo.actionCalls, [
        ('dev_caps_01', 'light', 'set_brightness', 70),
        ('dev_caps_01', 'fan', 'set_speed', 67),
        ('dev_caps_01', 'mode', 'set_mode', 'manual'),
        ('dev_caps_01', 'blind', 'set_position', 40),
        ('dev_caps_01', 'light', 'set_color_temperature', 30),
      ]);
      expect(find.textContaining('Cambios guardados'), findsOneWidget);
      expect(controller.hasPendingChanges, isFalse);
    });

    testWidgets('save surfaces the writes-disabled notice instead of success', (
      tester,
    ) async {
      final repo = CommandDeviceFakeRepo(
        devices: const [_commandCapsLight],
        actionResult: const CapabilityActionResult(
          action: 'set_brightness',
          capability: 'BRIGHTNESS',
          outcome: 'EXECUTION_DISABLED',
          changed: false,
        ),
      );
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      controller.markPendingBrightness(70);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      expect(
        find.text('Escritura deshabilitada en el modo actual'),
        findsOneWidget,
      );
      expect(find.textContaining('Cambios guardados'), findsNothing);
    });

    testWidgets('save surfaces the unconfirmed notice instead of success', (
      tester,
    ) async {
      final repo = CommandDeviceFakeRepo(
        devices: const [_commandCapsLight],
        actionResult: const CapabilityActionResult(
          action: 'set_brightness',
          capability: 'BRIGHTNESS',
          outcome: 'unconfirmed',
          responseParsed: false,
        ),
      );
      final controller = AdaptiveFeatureController(repo);
      await controller.loadDevices();
      controller.selectDevice('dev_caps_01');
      await pumpDetailWithController(
        tester,
        controller: controller,
        deviceFrom: controller,
      );

      controller.markPendingColorTemperature(30);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      expect(
        find.text('Orden enviada — sin confirmación del dispositivo'),
        findsOneWidget,
      );
      expect(find.textContaining('Cambios guardados'), findsNothing);
    });

    testWidgets('multi-gang channels show each control state', (tester) async {
      await pumpDetail(tester, device: _observedTriple);
      expect(find.text('3 canales independientes'), findsOneWidget);

      expect(
        find.descendant(
          of: desktopEndpointEditor('Canal 1'),
          matching: find.text('Encendido'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: desktopEndpointEditor('Canal 2'),
          matching: find.text('Apagado'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: desktopEndpointEditor('Canal 3'),
          matching: find.text('Sin datos'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'channel power switch commands relay_2 and merges the observation',
      (tester) async {
        final repo = CommandDeviceFakeRepo(devices: const [_observedTriple]);
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_observed_triple_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        final relay2 = desktopEndpointEditor('Canal 2');
        final switchFinder = find.descendant(
          of: relay2,
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(switchFinder);
        await tester.pumpAndSettle();
        // One switch per channel and no device-level control on top: the old
        // header switch is gone, so each power label lives in its channel row.
        expect(find.byType(Switch), findsNWidgets(3));
        expect(find.text('Encendido'), findsOneWidget);
        expect(find.text('Apagado'), findsOneWidget);
        expect(find.text('Sin datos'), findsOneWidget);
        for (final channel in ['Canal 1', 'Canal 2', 'Canal 3']) {
          expect(
            find.descendant(
              of: desktopEndpointEditor(channel),
              matching: find.byType(Switch),
            ),
            findsOneWidget,
          );
        }
        // relay_2 has a confirmed off observation: the switch starts off.
        expect(tester.widget<Switch>(switchFinder).value, isFalse);

        await tester.tap(switchFinder);
        await tester.pump();

        expect(repo.powerCalls, [('dev_observed_triple_01', 'relay_2', true)]);
        await tester.pumpAndSettle();

        // The controller merged the confirmed observation into the snapshot.
        expect(tester.widget<Switch>(switchFinder).value, isTrue);
        final merged = controller.snapshot!.devices
            .firstWhere((d) => d.id == 'dev_observed_triple_01')
            .endpoints
            .firstWhere((e) => e.id == 'relay_2');
        expect(merged.observedPower, isTrue);
        expect(merged.observedQuality, 'confirmed');
        expect(
          find.descendant(of: relay2, matching: find.text('Encendido')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'channel power switch surfaces writes-disabled without flipping',
      (tester) async {
        final repo = CommandDeviceFakeRepo(
          devices: const [_observedTriple],
          powerResult: const EndpointPowerResult(
            outcome: 'EXECUTION_DISABLED',
            changed: false,
          ),
        );
        final controller = AdaptiveFeatureController(repo);
        await controller.loadDevices();
        controller.selectDevice('dev_observed_triple_01');
        await pumpDetailWithController(
          tester,
          controller: controller,
          deviceFrom: controller,
        );

        final relay2 = desktopEndpointEditor('Canal 2');
        final switchFinder = find.descendant(
          of: relay2,
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(switchFinder);
        await tester.pumpAndSettle();

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(repo.powerCalls, [('dev_observed_triple_01', 'relay_2', true)]);
        expect(
          find.text('Escritura deshabilitada en el modo actual'),
          findsOneWidget,
        );
        // No confirmed observation: the switch and the badge stay untouched.
        expect(tester.widget<Switch>(switchFinder).value, isFalse);
        expect(
          find.descendant(of: relay2, matching: find.text('Apagado')),
          findsOneWidget,
        );
      },
    );

    testWidgets('header shows Sin credenciales when pending_key is true', (
      tester,
    ) async {
      await pumpDetail(tester, device: _pendingKeyLight);

      expect(find.text('Sin credenciales'), findsOneWidget);
    });

    testWidgets('header hides Sin credenciales when credentials exist', (
      tester,
    ) async {
      await pumpDetail(tester, device: _hasKeyLight);

      expect(find.text('Sin credenciales'), findsNothing);
    });
  });
}

/// The desktop per-channel editor that owns [channelName].
Finder desktopEndpointEditor(String channelName) => find.ancestor(
  of: find.text(channelName),
  matching: find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_EndpointEditor',
  ),
);

Future<void> pumpDetail(
  WidgetTester tester, {
  required PhysicalDevice device,
}) async {
  final repo = _DetailFakeRepo(devices: [device]);
  final controller = AdaptiveFeatureController(repo);
  await controller.loadDevices();
  controller.selectDevice(device.id);
  await pumpDetailWithController(
    tester,
    controller: controller,
    deviceFrom: controller,
  );
}

Future<void> pumpDetailWithController(
  WidgetTester tester, {
  required AdaptiveFeatureController controller,
  required AdaptiveFeatureController deviceFrom,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final device = deviceFrom.selectedDevice!;
  final snapshot = deviceFrom.snapshot!;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DesktopDeviceDetailPane(
          device: device,
          areas: snapshot.areas,
          gateways: snapshot.gateways,
          controller: controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _lightOnline = PhysicalDevice(
  id: 'dev_light_01',
  name: 'Luz techo cocina',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: 'tuya-bf31',
  model: 'ZB-DL01',
  manufacturer: 'Moes',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'cocina',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'on_off', 'brightness'},
    ),
  ],
);

const _sensorNoBrightness = PhysicalDevice(
  id: 'dev_sensor_01',
  name: 'Sensor patio',
  kind: DeviceKind.sensor,
  provider: 'Tuya',
  providerDeviceId: 'tuya-xxxx',
  model: 'ZP01',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'patio',
  provisioningState: DeviceProvisioningState.configured,
  online: false,
  health: DeviceHealthState.offline,
  endpoints: [
    DeviceEndpoint(
      id: 'motion',
      name: 'Movimiento',
      kind: DeviceKind.sensor,
      capabilities: {'motion'},
    ),
  ],
);

const _tripleChannel = PhysicalDevice(
  id: 'dev_triple_01',
  name: 'Interruptor triple',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS0013',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'pasillo',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'relay_1',
      name: 'Canal 1',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'comedor',
      capabilities: {'on_off'},
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'patio',
      capabilities: {'on_off'},
    ),
  ],
);

const _lightCanonicalPower = PhysicalDevice(
  id: 'dev_light_02',
  name: 'Luz sala',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: 'tuya-aa11',
  model: 'ZB-DL01',
  manufacturer: 'Moes',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'sala',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER', 'BRIGHTNESS'},
    ),
  ],
);

/// Multi-gang with per-endpoint observations: relay_1 confirmed on, relay_2
/// confirmed off, relay_3 reported without a power value (unknown).
const _observedTriple = PhysicalDevice(
  id: 'dev_observed_triple_01',
  name: 'Interruptor triple observado',
  kind: DeviceKind.switchController,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'TS0013',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'pasillo',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'relay_1',
      name: 'Canal 1',
      kind: DeviceKind.switchController,
      controlledAreaId: 'sala',
      capabilities: {'on_off'},
      observedPower: true,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_2',
      name: 'Canal 2',
      kind: DeviceKind.switchController,
      controlledAreaId: 'comedor',
      capabilities: {'on_off'},
      observedPower: false,
      observedQuality: 'confirmed',
    ),
    DeviceEndpoint(
      id: 'relay_3',
      name: 'Canal 3',
      kind: DeviceKind.switchController,
      controlledAreaId: 'patio',
      capabilities: {'on_off'},
      observedQuality: 'unknown',
    ),
  ],
);

/// Credential setup still pending (`pending_key == true`).
const _pendingKeyLight = PhysicalDevice(
  id: 'dev_pending_01',
  name: 'Luz sin credenciales',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'sala',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  pendingKey: true,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);

/// Credentials already stored (`has_key == true`): no chip expected.
const _hasKeyLight = PhysicalDevice(
  id: 'dev_has_key_01',
  name: 'Luz con credenciales',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'sala',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  hasKey: true,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);

const _commandPowerLight = PhysicalDevice(
  id: 'dev_power_01',
  name: 'Luz comandable',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: 'tuya-aa22',
  model: 'ZB-DL01',
  manufacturer: 'Moes',
  gatewayId: 'gw_tuya_01',
  physicalAreaId: 'sala',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      capabilities: {'POWER'},
    ),
  ],
);

const _commandCapsLight = PhysicalDevice(
  id: 'dev_caps_01',
  name: 'Luz comandable',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'ZB-DL01',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'light',
      name: 'Luz',
      kind: DeviceKind.light,
      semanticRole: 'light',
      capabilities: {'POWER', 'BRIGHTNESS', 'COLOR_TEMPERATURE'},
      capabilityDetails: {
        'BRIGHTNESS': DeviceCapability(
          name: 'BRIGHTNESS',
          readable: true,
          writable: true,
          range: [0, 100],
        ),
        'COLOR_TEMPERATURE': DeviceCapability(
          name: 'COLOR_TEMPERATURE',
          readable: true,
          writable: true,
          range: [0, 100],
        ),
      },
    ),
    DeviceEndpoint(
      id: 'fan',
      name: 'Ventilador',
      kind: DeviceKind.unknown,
      capabilities: {'SPEED'},
    ),
    DeviceEndpoint(
      id: 'mode',
      name: 'Modo',
      kind: DeviceKind.unknown,
      capabilities: {'MODE'},
    ),
    DeviceEndpoint(
      id: 'blind',
      name: 'Persiana',
      kind: DeviceKind.unknown,
      capabilities: {'POSITION'},
    ),
  ],
);

const _commandFanCaps = PhysicalDevice(
  id: 'dev_fan_caps_01',
  name: 'Ventilador comandable',
  kind: DeviceKind.unknown,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'FAN-1',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'fan',
      name: 'Ventilador',
      kind: DeviceKind.unknown,
      semanticRole: 'fan',
      capabilities: {'SPEED'},
    ),
  ],
);

const _commandBlindCaps = PhysicalDevice(
  id: 'dev_blind_caps_01',
  name: 'Persiana comandable',
  kind: DeviceKind.unknown,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'BL-1',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'cover',
      name: 'Persiana',
      kind: DeviceKind.unknown,
      semanticRole: 'cover',
      capabilities: {'POSITION'},
      capabilityDetails: {
        'POSITION': DeviceCapability(
          name: 'POSITION',
          readable: true,
          writable: true,
          range: [0, 100],
        ),
      },
    ),
  ],
);

const _commandClimateCaps = PhysicalDevice(
  id: 'dev_climate_caps_01',
  name: 'Clima comandable',
  kind: DeviceKind.unknown,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'AC-1',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'sala',
  endpoints: [
    DeviceEndpoint(
      id: 'mode',
      name: 'Modo',
      kind: DeviceKind.unknown,
      semanticRole: 'climate',
      capabilities: {'MODE'},
      capabilityDetails: {
        'MODE': DeviceCapability(
          name: 'MODE',
          readable: true,
          writable: true,
          enumValues: ['eco', 'turbo'],
        ),
      },
      observedCapabilities: {
        'MODE': EndpointCapabilityObservation(
          value: 'turbo',
          quality: 'confirmed',
        ),
      },
    ),
  ],
);

class _DetailFakeRepo implements DeviceInventoryRepository {
  _DetailFakeRepo({
    required List<PhysicalDevice> devices,
    this.shouldFailAssign = false,
  }) : devices = List.of(devices);
  List<PhysicalDevice> devices;
  bool shouldFailAssign;

  /// When set, both rename methods throw it instead of returning a canonical
  /// device (honest-failure coverage).
  Object? renameError;
  final assignCalls = <(String, String?)>[];
  final endpointAreaCalls = <(String, String, String?)>[];
  final roleCalls = <(String, String, String?)>[];
  @override
  bool get supportsIdentify => false;
  @override
  bool get supportsSemanticRole => true;
  @override
  Future<DeviceInventorySnapshot> load() async => DeviceInventorySnapshot(
    areas: const [
      HomeArea(id: 'sala', name: 'Sala'),
      HomeArea(id: 'cocina', name: 'Cocina'),
      HomeArea(id: 'pasillo', name: 'Pasillo'),
    ],
    devices: List.unmodifiable(devices),
    gateways: const [
      GatewayInfo(
        id: 'gw_tuya_01',
        name: 'Gateway Zigbee principal',
        provider: 'Tuya',
        health: DeviceHealthState.online,
        childDeviceIds: [],
      ),
    ],
    lastDiscoveryLabel: '',
  );
  @override
  Future<DeviceInventorySnapshot> discover() async => load();
  @override
  Future<PhysicalDevice> assignPhysicalArea(
    String deviceId,
    String? areaId,
  ) async {
    assignCalls.add((deviceId, areaId));
    if (shouldFailAssign) throw StateError('assign failed');
    final idx = devices.indexWhere((d) => d.id == deviceId);
    final updated = devices[idx].copyWith(physicalAreaId: areaId);
    devices[idx] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) async {
    endpointAreaCalls.add((deviceId, endpointId, areaId));
    final idx = devices.indexWhere((d) => d.id == deviceId);
    final current = devices[idx];
    final updated = current.copyWith(
      endpoints: [
        for (final e in current.endpoints)
          if (e.id == endpointId) e.copyWith(controlledAreaId: areaId) else e,
      ],
    );
    devices[idx] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) async {
    roleCalls.add((deviceId, endpointId, role));
    final idx = devices.indexWhere((d) => d.id == deviceId);
    final current = devices[idx];
    final updated = current.copyWith(
      endpoints: [
        for (final e in current.endpoints)
          if (e.id == endpointId) e.copyWith(semanticRole: role) else e,
      ],
    );
    devices[idx] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) async {
    final error = renameError;
    if (error != null) throw error;
    final idx = devices.indexWhere((d) => d.id == deviceId);
    final updated = devices[idx].copyWith(userName: userName);
    devices[idx] = updated;
    return updated;
  }

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) async {
    final error = renameError;
    if (error != null) throw error;
    final idx = devices.indexWhere((d) => d.id == deviceId);
    final current = devices[idx];
    final updated = current.copyWith(
      endpoints: [
        for (final e in current.endpoints)
          if (e.id == endpointId) e.copyWith(userName: userName) else e,
      ],
    );
    devices[idx] = updated;
    return updated;
  }

  @override
  Future<List<HomeArea>> listAreas() async => const [
    HomeArea(id: 'sala', name: 'Sala'),
  ];
  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async => throw UnimplementedError();
  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteArea(String areaId) async => throw UnimplementedError();
  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}
