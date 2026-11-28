typedef BrowserLauncher = Future<bool> Function(Uri uri);

/// Opens only the active engine loopback URL. LAN/cast URLs and arbitrary
/// user-provided links are deliberately rejected.
Future<bool> openStreamInBrowser({
  required String? streamUrl,
  required BrowserLauncher launcher,
}) async {
  if (streamUrl == null) return false;
  final uri = Uri.tryParse(streamUrl);
  if (uri == null || uri.scheme != 'http' || uri.host != '127.0.0.1') {
    return false;
  }
  final opened = await launcher(uri);
  if (!opened) throw StateError('browser launch returned false');
  return true;
}
