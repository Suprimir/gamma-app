import 'package:flutter_test/flutter_test.dart';
import 'package:gamma_app/data/device_inventory.dart';
import 'package:gamma_app/ui/app_colors.dart';
import 'package:gamma_app/ui/device_status.dart';

void main() {
  group('healthToLabel', () {
    test('online -> Encendido', () {
      expect(healthToLabel(DeviceHealthState.online), 'Encendido');
    });

    test('sleeping -> Apagado', () {
      expect(healthToLabel(DeviceHealthState.sleeping), 'Apagado');
    });

    test('offline -> Desconectado', () {
      expect(healthToLabel(DeviceHealthState.offline), 'Desconectado');
    });

    test('unknown -> Desconectado', () {
      expect(healthToLabel(DeviceHealthState.unknown), 'Desconectado');
    });

    test('unreachable -> Desconectado', () {
      expect(healthToLabel(DeviceHealthState.unreachable), 'Desconectado');
    });

    test('authError -> Desconectado', () {
      expect(healthToLabel(DeviceHealthState.authError), 'Desconectado');
    });
  });

  group('healthToColor', () {
    test('online -> 0xFF10B981', () {
      expect(
        healthToColor(DeviceHealthState.online).toARGB32(),
        AppColors.statusEncendido.toARGB32(),
      );
      expect(healthToColor(DeviceHealthState.online).toARGB32(), 0xFF10B981);
    });

    test('sleeping -> 0xFFEF4444', () {
      expect(
        healthToColor(DeviceHealthState.sleeping).toARGB32(),
        AppColors.statusApagado.toARGB32(),
      );
      expect(healthToColor(DeviceHealthState.sleeping).toARGB32(), 0xFFEF4444);
    });

    test('offline -> 0xFF9CA3AF', () {
      expect(healthToColor(DeviceHealthState.offline).toARGB32(), 0xFF9CA3AF);
    });

    test('unknown -> grey', () {
      expect(
        healthToColor(DeviceHealthState.unknown).toARGB32(),
        AppColors.statusDesconectado.toARGB32(),
      );
    });
  });

  group('kind helpers', () {
    test('light kind badge purple', () {
      expect(kindBadgeColor(DeviceKind.light).toARGB32(), 0xFF8B5CF6);
    });

    test('switchController -> cyan 06B6D4', () {
      expect(
        kindBadgeColor(DeviceKind.switchController).toARGB32(),
        0xFF06B6D4,
      );
    });

    test('sensor -> grey', () {
      expect(kindBadgeColor(DeviceKind.sensor).toARGB32(), 0xFF9CA3AF);
    });
  });
}
