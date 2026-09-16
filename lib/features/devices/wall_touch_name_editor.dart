import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:vad/vad.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';
import '../voice/mic_source.dart';
import '../voice/vad_model.dart';
import '../voice/voice_session.dart';
import '../wall_home/wall_activity_bus.dart';

/// Touch-first name editor for the wall panel: the user never depends on an
/// OS keyboard. One sheet combines three ways to set the name:
///
/// 1. Tapping a suggestion (type + room based, zero typing).
/// 2. The built-in finger keyboard (always available, >= 60dp keys).
/// 3. Dictating with the mic key (reuses the backend transcription behind
///    [ApiClient.audioTurn]).
///
/// Returns the confirmed text, or null when the user cancels.
Future<String?> showWallNameEditor({
  required BuildContext context,
  required ApiClient api,
  required String initialText,
  required String typeLabel,
  required String? areaName,
}) {
  return _showWallSheet(
    context: context,
    sheet: _WallNameSheet(
      api: api,
      initialText: initialText,
      typeLabel: typeLabel,
      areaName: areaName,
    ),
  );
}

/// Touch-first search entry for the wall panel: the same built-in finger
/// keyboard + voice dictation as [showWallNameEditor], but with no
/// suggestions (a search has no device type to suggest from). Confirming
/// empty is allowed so the user can clear the filter.
///
/// [title]/[subtitle]/[confirmLabel] allow reusing the sheet for other
/// free-text entries (e.g. area names); defaults keep the device search.
Future<String?> showWallSearchEditor({
  required BuildContext context,
  required ApiClient api,
  required String initialText,
  String title = 'Buscar dispositivos',
  String subtitle = 'Escríbelo o díctalo',
  String confirmLabel = 'Buscar',
}) {
  return _showWallSheet(
    context: context,
    sheet: _WallNameSheet(
      api: api,
      initialText: initialText,
      typeLabel: '',
      areaName: null,
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      showSuggestions: false,
      allowEmpty: true,
    ),
  );
}

Future<String?> _showWallSheet({
  required BuildContext context,
  required _WallNameSheet sheet,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: sheet,
    ),
  );
}

/// Suggested names from the already chosen type + room. Tapping one fills
/// the field; the keyboard/voice remain for special cases.
///
/// Each call shuffles a wider pool and returns up to 4, so reopening the
/// sheet rotates the visible suggestions instead of always showing the same.
List<String> wallNameSuggestions(String typeLabel, String? areaName) {
  final type = typeLabel.trim().isEmpty ? 'Dispositivo' : typeLabel.trim();
  final area = areaName?.trim() ?? '';
  final pool = <String>[];
  if (area.isEmpty) {
    pool.addAll([
      '$type techo',
      '$type pared',
      '$type principal',
      '$type ambiente',
      '$type central',
      '$type auxiliar',
      '$type entrada',
      '$type noche',
      '$type 1',
      '$type 2',
      '$type 3',
    ]);
  } else {
    pool.addAll([
      '$type $area',
      '$type techo $area',
      '$type principal $area',
      '$type ambiente $area',
      '$type central $area',
      '$type entrada $area',
      '$type $area 1',
      '$type $area 2',
      '$type $area 3',
    ]);
  }
  pool.shuffle(Random());
  return pool.take(4).toList();
}

class _WallNameSheet extends StatefulWidget {
  const _WallNameSheet({
    required this.api,
    required this.initialText,
    required this.typeLabel,
    required this.areaName,
    this.title = 'Nombre del dispositivo',
    this.subtitle = 'Escríbelo, elige una sugerencia o díctalo',
    this.confirmLabel = 'Listo',
    this.showSuggestions = true,
    this.allowEmpty = false,
  });

  final ApiClient api;
  final String initialText;
  final String typeLabel;
  final String? areaName;

  /// Sheet chrome variants (name entry vs. search entry). Defaults keep
  /// the [showWallNameEditor] behavior unchanged.
  final String title;
  final String subtitle;
  final String confirmLabel;
  final bool showSuggestions;
  final bool allowEmpty;

  @override
  State<_WallNameSheet> createState() => _WallNameSheetState();
}

class _WallNameSheetState extends State<_WallNameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final _recorder = AudioRecorder();
  late final List<String> _suggestions = wallNameSuggestions(
    widget.typeLabel,
    widget.areaName,
  );

  bool _recording = false;
  bool _transcribing = false;
  String? _error;

  /// True once the VAD detected voice in this take: drives the
  /// "Habla ahora…" → "Te escucho…" label switch.
  bool _heardSpeech = false;

  /// Guards the race between VAD auto-stop and tap-to-stop: only the first
  /// speech-end wins and transcribes.
  bool _speechEnded = false;

  /// Hands-free hold on the wall sleep countdown while dictating: talking
  /// produces no touches, so without this the panel could sleep mid-speech.
  bool _held = false;

  void _setHeld(bool value) {
    if (_held == value) return;
    _held = value;
    if (value) {
      WallActivityBus.hold();
    } else {
      WallActivityBus.release();
    }
  }

  MicStream? _mic;
  StreamSubscription<List<double>>? _speechSub;
  StreamSubscription<void>? _realSpeechSub;
  StreamSubscription<void>? _misfireSub;
  StreamSubscription<String>? _vadErrorSub;
  Timer? _listenTimer;

  /// VAD tuning for short device names (v5 frames are 512
  /// samples = 32ms each):
  /// - redemptionFrames 20 (~640ms of silence ends the take): tolerates
  ///   natural pauses between words instead of cutting mid-sentence, while
  ///   still ending faster than the 24-frame (~770ms) default.
  /// - minSpeechFrames 4 (~130ms of voice validates): short names like
  ///   "Luz 1" stop being discarded as misfires.
  /// - positiveSpeechThreshold 0.4: picks up quieter/farther speech from
  ///   the wall panel mic instead of staying stuck on "Habla ahora…".
  static const _vadPositiveThreshold = 0.4;
  static const _vadNegativeThreshold = 0.35;
  static const _vadRedemptionFrames = 20;
  static const _vadMinSpeechFrames = 4;
  static const _vadPreSpeechPadFrames = 3;
  static const _vadEndSpeechPadFrames = 3;

  /// Max time a take may stay open without VAD auto-stop before we settle
  /// it ourselves instead of leaving "Te escucho…" hanging forever.
  static const _maxListenTime = Duration(seconds: 12);

  /// Dedicated VAD handler owned by this sheet. It must NOT be the shared
  /// [VadModel.vad]: the wall home page holds a permanent subscription on
  /// that one, so routing dictation through it would make the assistant
  /// answer the dictated name. Each feature owns its listener here.
  late final VadHandler _vad = VadHandler.create();

  @override
  void initState() {
    super.initState();
    // Pre-warms our own Silero iterator so the first mic tap listens
    // immediately. Failures are silent: the real listen retries the load.
    unawaited(_prewarm().catchError((_) {}));
  }

  Future<void> _prewarm() async {
    final ctrl = StreamController<Uint8List>();
    try {
      // Same params as the real listen: otherwise the first mic tap pays
      // an iterator rebuild (model reload latency) right when the user
      // starts talking.
      await _vad.startListening(
        audioStream: ctrl.stream,
        model: 'v5',
        baseAssetPath: VadModel.baseAssetPath,
        positiveSpeechThreshold: _vadPositiveThreshold,
        negativeSpeechThreshold: _vadNegativeThreshold,
        redemptionFrames: _vadRedemptionFrames,
        minSpeechFrames: _vadMinSpeechFrames,
        preSpeechPadFrames: _vadPreSpeechPadFrames,
        endSpeechPadFrames: _vadEndSpeechPadFrames,
      );
      await _vad.stopListening();
    } finally {
      await ctrl.close();
    }
  }

  @override
  void dispose() {
    _listenTimer?.cancel();
    _setHeld(false);
    unawaited(_speechSub?.cancel());
    unawaited(_realSpeechSub?.cancel());
    unawaited(_misfireSub?.cancel());
    unawaited(_vadErrorSub?.cancel());
    try {
      unawaited(_vad.stopListening());
    } catch (_) {}
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        mic.cancel();
      } catch (_) {}
    }
    try {
      unawaited(_vad.dispose());
    } catch (_) {}
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _insert(String char) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, char);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + char.length),
    );
    setState(() => _error = null);
  }

  void _backspace() {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;
    if (selection.isValid && selection.start != selection.end) {
      final next = text.replaceRange(selection.start, selection.end, '');
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: selection.start),
      );
      return;
    }
    final offset = selection.isValid ? selection.start : text.length;
    if (offset <= 0) return;
    final next = text.replaceRange(offset - 1, offset, '');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset - 1),
    );
  }

  /// Mic key with VAD auto-stop: while listening, the Silero detector cuts
  /// the take itself once the user goes quiet (~640ms, tolerates pauses
  /// between words) and the transcription runs automatically — no need to tap stop. Tapping again
  /// forces the end and transcribes what was said instead of discarding it.
  /// Only speech samples (no long silences) reach the backend, which is what
  /// most improves recognition. Transcripts in a non-Latin script (e.g. a
  /// misdetected language) are rejected with a retry message instead of
  /// landing in the name field.
  Future<void> _toggleMic() async {
    if (_transcribing) return;
    if (_recording) {
      // Tap-to-stop = force the end so the spoken name is transcribed.
      // stopListening triggers forceEndSpeech internally
      // (submitUserSpeechOnPause) while our onSpeechEnd subscription is
      // still alive; if no speech was in course, settle with a retry hint.
      try {
        await _vad.stopListening();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted || _speechEnded || _transcribing) return;
        await _stopHardware();
        _listenTimer?.cancel();
        _listenTimer = null;
        _setHeld(false);
        if (mounted) {
          setState(() {
            _recording = false;
            _error = 'No se escuchó nada, probá de nuevo.';
          });
        }
      } catch (_) {
        await _stopHardware();
        _setHeld(false);
        if (mounted) setState(() => _recording = false);
      }
      return;
    }
    if (await _recorder.hasPermission() != true) {
      setState(() => _error = 'Permiso de micrófono denegado.');
      return;
    }
    try {
      final mic = await micPcm16Stream(_recorder);
      _mic = mic;
      if (!mounted) {
        await mic.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _heardSpeech = false;
        _error = null;
      });
      _speechEnded = false;
      _setHeld(true);
      _speechSub = _vad.onSpeechEnd.listen(_onSpeechEnd);
      // First detection frame (not the validated real-start): the
      // "Te escucho…" feedback must appear the instant anything
      // voice-like arrives, otherwise the user thinks the mic is dead
      // and keeps waiting on "Habla ahora…".
      _realSpeechSub = _vad.onSpeechStart.listen((_) {
        if (mounted && _recording && !_heardSpeech) {
          setState(() => _heardSpeech = true);
        }
      });
      _misfireSub = _vad.onVADMisfire.listen((_) {
        // Short noise burst, not valid speech: keep listening so the user
        // can just keep talking instead of restarting the take.
      });
      _vadErrorSub = _vad.onError.listen((message) {
        if (mounted && _recording && !_transcribing) {
          setState(() => _error = 'Error del VAD: $message');
        }
      });
      _listenTimer?.cancel();
      _listenTimer = Timer(_maxListenTime, _onListenTimeout);
      await _vad.startListening(
        audioStream: mic.pcm,
        model: 'v5',
        baseAssetPath: VadModel.baseAssetPath,
        positiveSpeechThreshold: _vadPositiveThreshold,
        negativeSpeechThreshold: _vadNegativeThreshold,
        redemptionFrames: _vadRedemptionFrames,
        minSpeechFrames: _vadMinSpeechFrames,
        preSpeechPadFrames: _vadPreSpeechPadFrames,
        endSpeechPadFrames: _vadEndSpeechPadFrames,
        submitUserSpeechOnPause: true,
      );
    } catch (e) {
      await _stopHardware();
      _listenTimer?.cancel();
      _listenTimer = null;
      _setHeld(false);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = 'Error al escuchar: $e';
      });
    }
  }

  /// Safety net: the take stayed open too long without VAD auto-stop
  /// (constant background noise, threshold miss). Force the end so speech
  /// in course still transcribes; otherwise close with a retry hint.
  Future<void> _onListenTimeout() async {
    if (!_recording || _transcribing || !mounted) return;
    try {
      await _vad.stopListening();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || _speechEnded || _transcribing) return;
      await _stopHardware();
      _setHeld(false);
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'Tardaste mucho, probá de nuevo.';
        });
      }
    } catch (_) {
      await _stopHardware();
      _setHeld(false);
      if (mounted) setState(() => _recording = false);
    }
  }

  /// VAD entry point: speech ended (pause detected) → build a WAV from the
  /// speech samples only and transcribe it automatically.
  Future<void> _onSpeechEnd(List<double> samples) async {
    if (_speechEnded || samples.isEmpty || !mounted) return;
    _speechEnded = true;
    _listenTimer?.cancel();
    _listenTimer = null;
    final Uint8List wav = pcm16ToWav(floatsToPcm16(samples));
    await _stopHardware();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _transcribing = true;
      _error = null;
    });
    try {
      final sessionId = await getOrCreateVoiceSessionId();
      final result = await widget.api.audioTurn(wav, sessionId: sessionId);
      if (!mounted) {
        _setHeld(false);
        return;
      }
      final transcript = (result['transcript'] as String? ?? '').trim();
      setState(() {
        _transcribing = false;
        if (transcript.isEmpty) {
          _error = 'No se escuchó nada, probá de nuevo.';
        } else if (_hasForeignScript(transcript)) {
          _error = 'No se entendió (vino en otro idioma), probá de nuevo.';
        } else {
          _controller.text = transcript;
          _controller.selection = TextSelection.collapsed(
            offset: transcript.length,
          );
        }
      });
      _setHeld(false);
    } catch (e) {
      _setHeld(false);
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _error = 'No se pudo transcribir: $e';
      });
    }
  }

  Future<void> _stopHardware() async {
    _listenTimer?.cancel();
    _listenTimer = null;
    await _speechSub?.cancel();
    _speechSub = null;
    await _realSpeechSub?.cancel();
    _realSpeechSub = null;
    await _misfireSub?.cancel();
    _misfireSub = null;
    await _vadErrorSub?.cancel();
    _vadErrorSub = null;
    try {
      await _vad.stopListening();
    } catch (_) {}
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        await mic.cancel();
      } catch (_) {}
    }
    if (!kIsWeb && !Platform.isAndroid) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
  }

  /// True when the transcript carries a non-Latin script (Cyrillic, Arabic,
  /// CJK, …): the backend misdetected the language. Names are Latin-script,
  /// so this is always a recognition failure worth retrying.
  static bool _hasForeignScript(String text) {
    const scripts = [
      'Cyrillic',
      'Arabic',
      'Han',
      'Hiragana',
      'Katakana',
      'Hangul',
      'Thai',
      'Devanagari',
      'Hebrew',
      'Armenian',
      'Georgian',
    ];
    // Short name-length strings only; Unicode script properties need the
    // unicode flag to work.
    final pattern = scripts.map((s) => '\\p{Script=$s}').join('|');
    return RegExp(pattern, unicode: true).hasMatch(text);
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      // Search entry: confirming empty clears the filter.
      if (widget.allowEmpty) {
        Navigator.of(context).pop(text);
        return;
      }
      setState(() => _error = 'El nombre no puede estar vacío.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _controller.text.trim();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim, fontSize: 15),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preview.isEmpty ? 'Sin nombre' : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: preview.isEmpty
                            ? AppColors.textFaint
                            : AppColors.text,
                      ),
                    ),
                  ),
                  if (preview.isNotEmpty)
                    IconButton(
                      tooltip: 'Borrar nombre',
                      constraints: const BoxConstraints.tightFor(
                        width: 56,
                        height: 56,
                      ),
                      onPressed: () => setState(_controller.clear),
                      icon: const Icon(
                        Icons.backspace_outlined,
                        color: AppColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.showSuggestions) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final suggestion in _suggestions)
                    _WallSuggestionChip(
                      label: suggestion,
                      selected:
                          _controller.text.trim().toLowerCase() ==
                          suggestion.toLowerCase(),
                      onTap: () => setState(() {
                        _controller.text = suggestion;
                        _controller.selection = TextSelection.collapsed(
                          offset: suggestion.length,
                        );
                        _error = null;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _WallTouchKeyboard(
              onInsert: _insert,
              onBackspace: _backspace,
              onSubmitted: _confirm,
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red, fontSize: 15),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _toggleMic,
                    icon: _transcribing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Icon(
                            _recording ? Icons.stop : Icons.mic,
                            size: 26,
                            color: _recording
                                ? AppColors.red
                                : AppColors.accent,
                          ),
                    label: Text(
                      _transcribing
                          ? 'Transcribiendo…'
                          : _recording
                          ? (_heardSpeech
                                ? 'Te escucho… tocá para terminar'
                                : 'Habla ahora…')
                          : 'Dictar por voz',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _recording
                          ? AppColors.red
                          : AppColors.accentStrong,
                      minimumSize: const Size.fromHeight(64),
                      side: BorderSide(
                        color: _recording
                            ? AppColors.red
                            : AppColors.accentTintActive,
                        width: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check, size: 24),
                  label: Text(widget.confirmLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(160, 64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WallSuggestionChip extends StatelessWidget {
  const _WallSuggestionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: selected ? AppColors.accentStrong : AppColors.text,
      ),
      selectedColor: AppColors.accentTint,
      backgroundColor: AppColors.surfaceRaised,
      side: BorderSide(
        color: selected ? AppColors.accent : Colors.transparent,
        width: selected ? 2 : 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

/// Built-in finger keyboard (Spanish layout with Ñ). Every key is >= 60dp
/// tall, so typing on the wall panel never depends on the OS.
class _WallTouchKeyboard extends StatefulWidget {
  const _WallTouchKeyboard({
    required this.onInsert,
    required this.onBackspace,
    required this.onSubmitted,
  });

  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onSubmitted;

  @override
  State<_WallTouchKeyboard> createState() => _WallTouchKeyboardState();
}

class _WallTouchKeyboardState extends State<_WallTouchKeyboard> {
  bool _upper = true;

  static const _rowDigits = '1234567890';
  static const _rowTop = 'QWERTYUIOP';
  static const _rowMid = 'ASDFGHJKLÑ';
  static const _rowBottom = 'ZXCVBNM';

  void _press(String char) {
    widget.onInsert(_upper ? char.toUpperCase() : char.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KeyRow(
          chars: _rowDigits.split(''),
          upper: false,
          onPress: _press,
          small: true,
        ),
        const SizedBox(height: 8),
        _KeyRow(chars: _rowTop.split(''), upper: _upper, onPress: _press),
        const SizedBox(height: 8),
        _KeyRow(chars: _rowMid.split(''), upper: _upper, onPress: _press),
        const SizedBox(height: 8),
        Row(
          children: [
            _WallKey(
              flex: 15,
              label: _upper ? 'ABC' : 'abc',
              active: _upper,
              icon: _upper ? Icons.keyboard_capslock : null,
              onTap: () => setState(() => _upper = !_upper),
            ),
            const SizedBox(width: 6),
            for (final char in _rowBottom.split('')) ...[
              _WallKey(
                flex: 10,
                label: _upper ? char : char.toLowerCase(),
                onTap: () => _press(char),
              ),
              const SizedBox(width: 6),
            ],
            _WallKey(
              flex: 15,
              icon: Icons.backspace_outlined,
              onTap: widget.onBackspace,
              onLongPress: widget.onBackspace,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _WallKey(
              flex: 20,
              label: 'espacio',
              dim: true,
              onTap: () => widget.onInsert(' '),
            ),
            const SizedBox(width: 6),
            _WallKey(flex: 10, label: '.', onTap: () => _press('.')),
            const SizedBox(width: 6),
            _WallKey(flex: 10, label: ',', onTap: () => widget.onInsert(',')),
            const SizedBox(width: 6),
            _WallKey(
              flex: 18,
              label: 'intro',
              primary: true,
              icon: Icons.keyboard_return,
              onTap: widget.onSubmitted,
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.chars,
    required this.upper,
    required this.onPress,
    this.small = false,
  });

  final List<String> chars;
  final bool upper;
  final ValueChanged<String> onPress;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < chars.length; i++) ...[
          _WallKey(
            flex: 10,
            label: small
                ? chars[i]
                : (upper ? chars[i] : chars[i].toLowerCase()),
            small: small,
            onTap: () => onPress(chars[i]),
          ),
          if (i != chars.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _WallKey extends StatelessWidget {
  const _WallKey({
    required this.flex,
    this.label,
    this.icon,
    this.small = false,
    this.dim = false,
    this.active = false,
    this.primary = false,
    this.onTap,
    this.onLongPress,
  });

  final int flex;
  final String? label;
  final IconData? icon;
  final bool small;
  final bool dim;
  final bool active;
  final bool primary;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Material(
        color: primary
            ? AppColors.accent
            : active
            ? AppColors.accentTint
            : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: icon != null && label == null
                ? Icon(
                    icon,
                    size: 26,
                    color: primary ? Colors.white : AppColors.text,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null)
                        Icon(
                          icon,
                          size: 22,
                          color: primary ? Colors.white : AppColors.text,
                        ),
                      if (icon != null && label != null)
                        const SizedBox(width: 6),
                      if (label != null)
                        Text(
                          label!,
                          style: TextStyle(
                            fontSize: small ? 18 : 21,
                            fontWeight: FontWeight.w600,
                            color: primary
                                ? Colors.white
                                : dim
                                ? AppColors.textDim
                                : AppColors.text,
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
