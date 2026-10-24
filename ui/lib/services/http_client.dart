import 'package:http/http.dart' as http;

import 'http_client_stub.dart' if (dart.library.js_interop) 'http_client_web.dart' as impl;

/// HTTP client that sends the browser cookies on cross-origin calls (the gateway session
/// `sid` lives on api.asodya.com). Same approach as cortex `createCredentialsClient`.
http.Client createCredentialsClient() => impl.createCredentialsClient();
