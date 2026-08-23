// Probe del stream SSE real: se suscribe y muestra eventos hasta Ctrl+C.
// Uso: dart run tool/sse_probe.dart [baseUrl] (default 127.0.0.1:8420)

// print is the point of this diagnostic script.
// ignore_for_file: avoid_print
import 'package:gamma_app/data/api_client.dart';

Future<void> main(List<String> args) async {
  final api = ApiClient(baseUrl: args.isEmpty ? 'http://127.0.0.1:8420' : args.first);
  await api.events().forEach((event) => print('[${event['event']}] ${event['data']}'));
}
