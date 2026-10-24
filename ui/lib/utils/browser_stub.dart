/// Non-web targets (tests): no browser cookie jar.
String? readCookie(String name) => null;

void deleteCookie(String name) {}

/// Tests run from a file URL, which has no origin: the local dev server stands in.
String currentOrigin() => Uri.base.isScheme('http') || Uri.base.isScheme('https') ? Uri.base.origin : 'http://localhost:8110';
