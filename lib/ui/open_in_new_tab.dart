// Conditional export: on web this resolves to the browser-tab helper; on IO
// platforms it resolves to a stub that throws if ever called. Call sites gate
// on `kIsWeb` first, so a single import works everywhere.
export 'open_in_new_tab_io.dart'
    if (dart.library.js_interop) 'open_in_new_tab_web.dart';
