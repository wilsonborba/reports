import 'address_bar_stub.dart'
    if (dart.library.js_interop) 'address_bar_web.dart' as impl;

/// Removes the query (for example a login token) from the browser address bar and
/// from the history entry, without a new page load.
void removeQueryFromAddressBar() => impl.removeQueryFromAddressBar();
