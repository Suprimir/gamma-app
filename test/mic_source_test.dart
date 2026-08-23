import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamma_app/features/voice/mic_source.dart';

void main() {
  group('floatsToPcm16', () {
    test('mapea floats -1..1 a PCM16 LE', () {
      final out = floatsToPcm16([0.0, 1.0, -1.0, 0.5]);
      final view = ByteData.sublistView(out);
      expect(view.getInt16(0, Endian.little), 0);
      expect(view.getInt16(2, Endian.little), 32767);
      expect(view.getInt16(4, Endian.little), -32768);
      expect(view.getInt16(6, Endian.little), 16384);
    });

    test('clampa fuera de rango', () {
      final out = floatsToPcm16([2.0, -2.0]);
      final view = ByteData.sublistView(out);
      expect(view.getInt16(0, Endian.little), 32767);
      expect(view.getInt16(2, Endian.little), -32768);
    });
  });

  group('pcm16ToWav', () {
    test('genera cabecera RIFF valida', () {
      final wav = pcm16ToWav(Uint8List(3200));
      expect(wav.length, 44 + 3200);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final header = ByteData.sublistView(wav);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint16(34, Endian.little), 16);
    });
  });
}
