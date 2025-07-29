// integration_test/api/api_test.dart
//
// Aggregates every API integration test so that `flutter drive`
// sees ONE concrete Dart file.
//
// Usage example:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/api/api_test.dart \
//     -d chrome
//
// When you add more tests, just import them below and
// call <prefix>.main() in the same way.

import 'package:integration_test/integration_test.dart';

// ── Individual test files ───────────────────────────────────────
import 'jobs_integration_test.dart' as jobs;
import 'pm_auth_integration_test.dart' as pm_auth;
// import 'new_test.dart'           as newTest;   // add more here

void main() {
  // Required once per integration_test run
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run each test suite
  pm_auth.main();
  //jobs.main();
  // newTest.main();                               // add more here
}

