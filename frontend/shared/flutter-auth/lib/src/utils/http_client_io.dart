// lib/src/utils/http_client_io.dart
//
// Non-web platforms → normal `http.Client`.

import 'package:http/http.dart' as http;

http.Client createHttpClient() => http.Client();

