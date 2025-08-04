// worker-app/lib/core/presentation/widgets/global_debug_listener.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/providers/ui_messaging_provider.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

/// An invisible widget that listens for debug messages and shows them in a
/// long-duration SnackBar without interrupting any app flow. [cite: 27]
class GlobalDebugListener extends ConsumerWidget {
  final Widget child;

  const GlobalDebugListener({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<List<String>>(snackbarDebugProvider, (previous, next) {
      if (next.isNotEmpty) {
        // Loop through all new messages and show a SnackBar for each.
        for (final message in next) {
          showAppSnackBar(
            context,
            SelectableText('DEBUG: $message'),
            displayDuration: const Duration(seconds: 15),
          );
        }

        // Clear the state by resetting to an empty list.
        ref.read(snackbarDebugProvider.notifier).state = [];
      }
    });

    return child;
  }
}
