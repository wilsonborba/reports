import 'dart:typed_data';
import 'download_helper_stub.dart'
    if (dart.library.js_interop) 'download_helper_web.dart' as impl;

void triggerBrowserDownload(String url, String filename) {
  impl.triggerBrowserDownload(url, filename);
}

/// Saves bytes built in the app as a browser download.
void saveBytes(Uint8List bytes, String filename, String mime) {
  impl.saveBytes(bytes, filename, mime);
}
