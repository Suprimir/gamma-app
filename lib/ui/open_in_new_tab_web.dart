import 'package:web/web.dart' as web;

/// Web implementation of `openInNewTab`: opens [url] in a new browser tab.
void openInNewTab(String url) => web.window.open(url, '_blank');
