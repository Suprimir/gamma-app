/// IO stub of `openInNewTab`: every call site guards with `kIsWeb` first, so
/// this is never reached on Android, iOS, or desktop. Throwing keeps the
/// contract honest if a future call site forgets the guard.
void openInNewTab(String url) {
  throw UnsupportedError('openInNewTab solo aplica en web');
}
