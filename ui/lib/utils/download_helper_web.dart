import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void triggerBrowserDownload(String url, String filename) {
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.target = '_self';
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

void saveBytes(Uint8List bytes, String filename, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  triggerBrowserDownload(url, filename);
  // The browser reads the file before the address is freed.
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
