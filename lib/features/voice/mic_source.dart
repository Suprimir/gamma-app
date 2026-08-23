import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:record/record.dart';

// ponytail: 16 kHz mono PCM16 microphone contract via record (Android, iOS,
// Linux, macOS, web, Windows). No audio_streamer: su stop bloqueaba el hilo
// de plataforma en Android (~400ms, el microcongelamiento original).

/// A microphone stream with explicit cancellation.
///
/// Closing the bridge cuts VAD input immediately while the physical recorder
/// finishes stopping in the background.
class MicStream {
  MicStream(this._stream, this._cancel);

  final Stream<Uint8List> _stream;
  final Future<void> Function() _cancel;

  Stream<Uint8List> get pcm => _stream;

  Future<void> cancel() => _cancel();
}

Future<MicStream> micPcm16Stream(AudioRecorder recorder) async {
  final source = await recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ),
  );
  return _bridge(
    Platform.isAndroid || Platform.isIOS ? _rechunk(source) : source,
    onCancel: Platform.isAndroid || Platform.isIOS ? recorder.stop : null,
  );
}

/// Expone el stream a través de un controller que la dashboard puede cerrar
/// en cualquier momento (corta el flujo al VAD sin esperar su stop).
Future<MicStream> _bridge(
  Stream<Uint8List> source, {
  Future<void> Function()? onCancel,
}) async {
  final controller = StreamController<Uint8List>();
  final sub = source.listen(
    controller.add,
    onError: controller.addError,
    onDone: controller.close,
  );
  return MicStream(controller.stream, () async {
    // Neither operation is awaited: stream cancellation may wait for an
    // async generator, while record stops on its recording thread. Closing
    // the controller below cuts VAD input immediately.
    // ignore: unawaited_futures - background cancellation.
    sub.cancel();
    // ignore: unawaited_futures - background recorder stop.
    onCancel?.call();
    if (!controller.isClosed) {
      // ignore: unawaited_futures - background close.
      controller.close();
    }
  });
}

/// Re-chunkea el PCM en pedazos de un frame de Silero v5 (512 muestras) y
/// cede el event loop entre pedazos.
///
/// Providers may deliver chunks larger than a Silero frame. Yielding one frame
/// per event lets the UI paint between synchronous ONNX inferences.
Stream<Uint8List> _rechunk(Stream<Uint8List> source) async* {
  // 512 muestras x 2 bytes (frame del modelo Silero v5).
  const frameBytes = 512 * 2;
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in source) {
    buffer.add(chunk);
    final bytes = buffer.takeBytes();
    var offset = 0;
    while (bytes.length - offset >= frameBytes) {
      yield Uint8List.sublistView(bytes, offset, offset + frameBytes);
      offset += frameBytes;
      // Yield the event loop so the UI can paint between inferences.
      await Future<void>.delayed(Duration.zero);
    }
    if (offset < bytes.length) buffer.add(bytes.sublist(offset));
  }
}

/// Floats normalizados (-1..1) a PCM16 LE, como el resto del pipeline espera.
Uint8List floatsToPcm16(List<double> samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.view(out.buffer);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * 32768).clamp(-32768.0, 32767.0).round();
    view.setInt16(i * 2, v, Endian.little);
  }
  return out;
}

/// Envuelve PCM16 LE en una cabecera WAV estándar (44 bytes).
Uint8List pcm16ToWav(Uint8List pcm, {int sampleRate = 16000}) {
  final header = ByteData(44);
  void str(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  str(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);

  final out = Uint8List(44 + pcm.length);
  out.setRange(0, 44, header.buffer.asUint8List());
  out.setRange(44, 44 + pcm.length, pcm);
  return out;
}
