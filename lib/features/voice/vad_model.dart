import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vad/vad.dart';

/// Precarga global del modelo Silero.
///
/// El shell destruye y recrea la dashboard al cambiar de pestaña; si la
/// precarga viviera en la página, cada visita a Inicio recargaría el ONNX
/// (~80ms en el main thread) y el primer toque del orbe lo pagaría. Este
/// singleton cachea el Future: el modelo se carga una sola vez en toda la
/// vida del proceso y todas las instancias de la dashboard lo reutilizan.
class VadModel {
  VadModel._();

  static final VadHandler vad = VadHandler.create(isDebug: kDebugMode);

  static Future<void>? _ready;

  /// Carga el modelo Silero en frío con un stream mudo y lo descarta.
  /// El VadHandler reutiliza el iterator cacheado en las escuchas reales.
  /// Si falla (p.ej. en tests sin ONNX nativo), la primera escucha real
  /// carga el modelo igual — la precarga es solo una optimización.
  static Future<void> ensureReady() {
    return _ready ??= _prewarm();
  }

  static Future<void> _prewarm() async {
    final ctrl = StreamController<Uint8List>();
    try {
      await vad.startListening(
        audioStream: ctrl.stream,
        // v5: frames de 512 muestras (32ms) — inferencia ~3ms en vez de
        // ~10ms del v4 (1536 muestras). Mismo clasificador neuronal, pero
        // el bloqueo del main thread por frame baja a imperceptible.
        model: 'v5',
        baseAssetPath: 'assets/',
      );
      await vad.stopListening();
    } catch (_) {
      // Silencioso: la escucha real reintentará la carga.
    } finally {
      await ctrl.close();
    }
  }
}
