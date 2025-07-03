// worker-app/lib/core/providers/ui_messaging_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A simple provider to hold a list of error objects that occurred during
/// the initial login or boot sequence.
///
/// The HomePage will listen to this provider, display a SnackBar for each
/// error, and then clear the list. This provides a clean, decoupled way to
/// communicate post-login fetch failures to the main UI.
final postBootErrorProvider = StateProvider<List<Object>>((ref) => []);

/// A provider to hold a temporary debug message for a SnackBar.
final snackbarDebugProvider = StateProvider<List<String>>((ref) => []);
