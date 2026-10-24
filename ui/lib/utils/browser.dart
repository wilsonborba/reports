import 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart' as impl;

/// Reads a readable browser cookie. The `sid` session cookie is httpOnly and never
/// visible here; the gateway sets the readable `csrf` cookie next to it, so its presence
/// tells whether this browser has an Asodya session (the same check as cortex).
String? readCookie(String name) => impl.readCookie(name);

/// Expires a readable cookie for this host and for the parent `.asodya.com` domain.
void deleteCookie(String name) => impl.deleteCookie(name);

/// Origin of the running app, for example `https://reports.asodya.com`.
String currentOrigin() => impl.currentOrigin();
