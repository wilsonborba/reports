import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Without `withCredentials` the browser drops cookies on cross-origin fetch calls.
http.Client createCredentialsClient() => BrowserClient()..withCredentials = true;
