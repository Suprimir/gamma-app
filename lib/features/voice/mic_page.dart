import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:record/record.dart';

import '../../data/api_client.dart';

class MicPage extends StatefulWidget {
  const MicPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<MicPage> createState() => _MicPageState();
}

class _MicLine {
  _MicLine(this.text, {required this.isUser});

  final String text;
  final bool isUser;
}

class _MicPageState extends State<MicPage> {
  final _lines = <_MicLine>[];
  final _recorder = AudioRecorder();
  final _player = Player();
  bool _recording = false;
  bool _busy = false;
  bool _speaking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _speaking = playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (kIsWeb) {
      setState(
        () => _error = 'La voz no está disponible en la versión web todavía.',
      );
      return;
    }
    if (_recording) {
      try {
        final path = await _recorder.stop();
        if (path != null && path.isNotEmpty) {
          await _upload(File(path));
        }
      } catch (e) {
        setState(() => _error = 'Error al grabar: $e');
      }
      if (mounted) setState(() => _recording = false);
    } else {
      if (await _recorder.hasPermission() != true) {
        setState(() => _error = 'Permiso de micrófono denegado.');
        return;
      }
      try {
        final dir = await Directory.systemTemp.createTemp('gamma_mic');
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: '${dir.path}/grabacion.wav',
        );
        setState(() {
          _recording = true;
          _error = null;
        });
      } catch (e) {
        setState(() => _error = 'Error al iniciar la grabación: $e');
      }
    }
  }

  Future<void> _upload(File file) async {
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final result = await widget.api.audioTurn(bytes);
      if (!mounted) return;
      final transcript = result['transcript'] as String? ?? '';
      final speech = result['speech'] as String?;
      final audioB64 = result['audio'] as String?;
      setState(() {
        if (transcript.isNotEmpty) {
          _lines.add(_MicLine(transcript, isUser: true));
        }
        if (speech != null && speech.isNotEmpty) {
          _lines.add(_MicLine(speech, isUser: false));
        }
        if (transcript.isEmpty && (speech == null || speech.isEmpty)) {
          _lines.add(_MicLine('(sin respuesta)', isUser: false));
        }
      });
      if (audioB64 != null && audioB64.isNotEmpty) {
        await _playResponse(audioB64);
      }
    } catch (e) {
      setState(() => _error = 'Error al enviar el audio: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playResponse(String audioB64) async {
    if (kIsWeb) {
      setState(
        () => _error =
            'La reproducción de voz no está disponible en la versión web todavía.',
      );
      return;
    }
    final bytes = base64Decode(audioB64);
    final file = File(
      '${Directory.systemTemp.path}/gamma_respuesta_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(bytes);
    try {
      await _player.open(Media(file.path), play: true);
    } catch (e) {
      setState(() => _error = 'Error al reproducir la respuesta: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Micrófono remoto')),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _lines.isEmpty
                ? const Center(
                    child: Text(
                      'Mantén el micrófono cerca y pulsa el botón.\n'
                      'El audio se envía al backend para transcribirlo.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _lines.length,
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      return Align(
                        alignment: line.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Text(line.text),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_speaking)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up, size: 20),
                          SizedBox(width: 8),
                          Text('GAMMA habla…'),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _toggleRecord,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_recording ? Icons.stop : Icons.mic),
                      label: Text(_recording ? 'Detener y enviar' : 'Grabar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
