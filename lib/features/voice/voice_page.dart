import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../ui/app_colors.dart';

class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.api});

  final ApiClient api;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoiceLine {
  _VoiceLine(this.text, {required this.isUser});

  final String text;
  final bool isUser;
}

class _VoicePageState extends State<VoicePage> {
  final _lines = <_VoiceLine>[];
  StreamSubscription<Map<String, dynamic>>? _sub;
  String _state = 'idle';
  String? _message;
  String? _sessionId;
  bool _busy = false;
  bool _disposed = false;

  bool get _active =>
      _sessionId != null && _state != 'idle' && _state != 'error';

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await widget.api.voiceStatus();
      if (_disposed) return;
      setState(() {
        _state = s['state'] as String? ?? 'idle';
        _message = s['message'] as String?;
        _sessionId = s['session_id'] as String?;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _state = 'error';
        _message = '$e';
      });
    }
  }

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.activateVoice();
      if (_disposed) return;
      final sessionId = r['session_id'] as String?;
      setState(() {
        _busy = false;
        _state = r['state'] as String? ?? 'starting';
        _message = r['message'] as String?;
        _sessionId = sessionId;
      });
      if (sessionId != null) _listen(sessionId);
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _busy = false;
        _state = 'error';
        _message = '$e';
      });
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.stopVoice(sessionId: _sessionId);
      if (_disposed) return;
      setState(() {
        _busy = false;
        _state = r['state'] as String? ?? 'idle';
        _message = r['message'] as String?;
        _sessionId = null;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _busy = false;
        _message = '$e';
      });
    }
    _sub?.cancel();
    _sub = null;
  }

  void _listen(String sessionId) {
    _sub?.cancel();
    _sub = widget.api
        .voiceEvents(sessionId, isCancelled: () => _disposed || !_active)
        .listen(
          _onEvent,
          onError: (Object e) {
            if (_disposed) return;
            setState(() {
              _state = 'error';
              _message = '$e';
            });
          },
        );
  }

  void _onEvent(Map<String, dynamic> ev) {
    if (_disposed) return;
    final event = ev['event'] as String?;
    final inner = (ev['data'] as Map?)?['data'] as Map? ?? const {};

    switch (event) {
      case 'voice_state':
        setState(() {
          _state = inner['state'] as String? ?? _state;
          _message = inner['message'] as String?;
        });
      case 'voice_transcript':
        final text = inner['text'] as String?;
        if (text == null || text.isEmpty) return;
        setState(() => _lines.add(_VoiceLine(text, isUser: true)));
      case 'voice_speech_start':
      case 'voice_speech_delta':
      case 'voice_speech_end':
      // Lo hablado en directo llega también en voice_turn_completed.
      // Ignorar los deltas evita duplicar la respuesta.
      case 'voice_turn_completed':
        final speech = inner['speech'] as String?;
        if (speech != null && speech.isNotEmpty) {
          setState(() => _lines.add(_VoiceLine(speech, isUser: false)));
        }
      case 'voice_error':
        setState(() {
          _state = 'error';
          _message = inner['message'] as String?;
          _lines.add(
            _VoiceLine(
              inner['message'] as String? ?? 'Error de voz',
              isUser: false,
            ),
          );
        });
      case 'voice_finished':
        setState(() {
          _state = 'idle';
          _sessionId = null;
        });
        _sub?.cancel();
        _sub = null;
    }
  }

  (IconData, String) _stateLabel() {
    switch (_state) {
      case 'listening':
        return (Icons.mic, 'Te escucho…');
      case 'processing':
        return (Icons.hourglass_top, 'Procesando…');
      case 'speaking':
        return (Icons.volume_up, 'Hablando…');
      case 'error':
        return (Icons.error_outline, 'Error');
      case 'starting':
        return (Icons.mic_none, 'Iniciando…');
      default:
        return (Icons.mic_none, 'Inactivo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _stateLabel();
    return Scaffold(
      appBar: AppBar(title: const Text('Voz remota')),
      body: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: _active ? AppColors.green : null),
            title: Text(label),
            subtitle: Text(
              _message ??
                  (_active
                      ? 'El micrófono y el altavoz están en el equipo del backend.'
                      : ''),
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? const Center(
                    child: Text('Activa y habla. Aquí verás el transcript.'),
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
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : _active
                      ? _stop
                      : _activate,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_active ? Icons.stop : Icons.mic),
                  label: Text(_active ? 'Detener' : 'Activar escucha'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
