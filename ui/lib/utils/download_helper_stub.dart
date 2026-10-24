import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

void triggerBrowserDownload(String url, String filename) {
  final uri = Uri.parse(url);
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// No browser: nothing to save (tests give their own save function).
void saveBytes(Uint8List bytes, String filename, String mime) {}
