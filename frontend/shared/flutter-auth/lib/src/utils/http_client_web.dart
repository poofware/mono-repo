// lib/src/utils/http_client_web.dart
//
// Browser client with CORS cookies enabled.

import 'package:http/browser_client.dart';

BrowserClient createHttpClient() => BrowserClient()..withCredentials = true;

