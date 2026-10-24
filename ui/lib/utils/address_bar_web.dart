import 'package:web/web.dart' as web;

void removeQueryFromAddressBar() {
  final location = web.window.location;
  if (location.search.isEmpty) return;
  // Keep the history state of the Flutter router; change only the URL.
  web.window.history.replaceState(web.window.history.state, '', location.pathname);
}
