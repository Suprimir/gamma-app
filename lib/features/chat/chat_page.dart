import 'package:flutter/material.dart';

import '../../data/api_client.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _messages = <(String, bool)>[];
  bool _busy = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add((text, true));
      _busy = true;
    });
    _controller.clear();
    try {
      final result = await widget.api.turn(text);
      final speech = result['speech'] as String?;
      final deviceResults = result['device_results'] as List?;
      final reply = StringBuffer();
      if (speech != null && speech.isNotEmpty) reply.write(speech);
      if (deviceResults != null && deviceResults.isNotEmpty) {
        for (final d in deviceResults) {
          final m = d is Map ? d['message'] : null;
          if (m != null && m.isNotEmpty) reply.write('\n • $m');
        }
      }
      if (reply.isEmpty) reply.write('(sin respuesta)');
      setState(() => _messages.add((reply.toString(), false)));
    } catch (e) {
      setState(() => _messages.add(('Error: $e', false)));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final (text, mine) = _messages[i];
                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Text(text),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Orden al asistente…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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
