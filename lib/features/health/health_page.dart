import 'package:flutter/material.dart';

import '../../data/api_client.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.health();
      setState(() => _data = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estado')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _MessageView(message: _error!, onRetry: _fetch)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Row('status', _data!['status']),
                _Row('device_mode', _data!['device_mode']),
                _Row('writes_enabled', '${_data!['writes_enabled']}'),
                _Row('uptime_seconds', '${_data!['uptime_seconds']}'),
                _Row('active_modules', '${_data!['active_modules']}'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _fetch,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refrescar'),
                ),
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.key_, this.value);

  final String key_;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(key_),
      trailing: Text(value, style: const TextStyle(fontFamily: 'monospace')),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
