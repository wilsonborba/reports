import 'package:web/web.dart' as web;

String? readCookie(String name) {
  final cookies = web.document.cookie;
  if (cookies.isEmpty) return null;
  for (final cookie in cookies.split(';')) {
    final parts = cookie.trim().split('=');
    if (parts.length >= 2 && parts[0] == name) return parts.sublist(1).join('=');
  }
  return null;
}

void deleteCookie(String name) {
  const expired = 'expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
  web.document.cookie = '$name=; $expired';
  final host = web.window.location.hostname;
  if (host.endsWith('asodya.com')) {
    web.document.cookie = '$name=; $expired; domain=.asodya.com';
  }
}

String currentOrigin() => web.window.location.origin;

void markEmbedReady() => web.document.documentElement?.setAttribute('data-reports-embed-ready', 'true');
