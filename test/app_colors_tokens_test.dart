import 'package:flutter_test/flutter_test.dart';
import 'package:gamma_app/ui/app_colors.dart';

void main() {
  test('gammaIndigo token is 0xFF4F46E5', () {
    expect(AppColors.gammaIndigo.toARGB32(), 0xFF4F46E5);
  });

  test('gammaIndigoLight token is 0xFFEEF2FF', () {
    expect(AppColors.gammaIndigoLight.toARGB32(), 0xFFEEF2FF);
  });

  test('status Encendido is 0xFF10B981', () {
    expect(AppColors.statusEncendido.toARGB32(), 0xFF10B981);
  });

  test('status Apagado is 0xFFEF4444', () {
    expect(AppColors.statusApagado.toARGB32(), 0xFFEF4444);
  });

  test('status Desconectado is 0xFF9CA3AF', () {
    expect(AppColors.statusDesconectado.toARGB32(), 0xFF9CA3AF);
  });

  test('toastDark is 0xFF1F2937', () {
    expect(AppColors.toastDark.toARGB32(), 0xFF1F2937);
  });

  test('kind tints for row badges', () {
    expect(AppColors.kindLight.toARGB32(), 0xFF8B5CF6);
    expect(AppColors.kindBlinds.toARGB32(), 0xFF06B6D4);
    expect(AppColors.kindFan.toARGB32(), 0xFF34D399);
  });
}
