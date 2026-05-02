import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Triggers a browser download of [content] as a Markdown file named [fileName].
void triggerMarkdownDownload(String content, String fileName) {
  final bytes = utf8.encode(content);
  final jsBytes = bytes.toJS;
  final parts = [jsBytes].toJS;
  final options = web.BlobPropertyBag(type: 'text/markdown');
  final blob = web.Blob(parts, options);
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(
      const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}

/// Triggers a browser download of [content] as a CSV file named [fileName].
void triggerCsvDownload(String content, String fileName) {
  final bytes = utf8.encode(content);
  final jsBytes = bytes.toJS;
  final parts = [jsBytes].toJS;
  final options = web.BlobPropertyBag(type: 'text/csv');
  final blob = web.Blob(parts, options);
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(
      const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}
