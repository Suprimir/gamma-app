import 'package:url_launcher/url_launcher.dart';

/// Abre una URL HTTP(S) en el navegador externo predeterminado del sistema.
Future<void> openExternalUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw ArgumentError.value(rawUrl, 'rawUrl', 'URL externa inválida');
  }

  final opened = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
  if (!opened) {
    throw StateError('No se pudo abrir el navegador.');
  }
}
