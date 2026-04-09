/// Conditional import entry point for web file download.
/// On web: uses dart:html Blob + AnchorElement download trick.
/// On other platforms: no-op (caller should fallback to clipboard).
export 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';
