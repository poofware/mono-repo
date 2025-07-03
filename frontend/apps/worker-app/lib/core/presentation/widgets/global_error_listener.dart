// worker-app/lib/core/presentation/widgets/global_error_listener.dart
// NEW FILE

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/features/earnings/state/earnings_state.dart';
import 'package:poof_worker/features/earnings/providers/providers.dart';
import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';

/// An invisible widget that sits at the top of the tree and listens for
/// errors in global notifiers. When an error is detected, it shows a
/// SnackBar and then clears the error from the state to prevent it from
/// being shown again on subsequent rebuilds.
class GlobalErrorListener extends ConsumerWidget {
  final Widget child;

  const GlobalErrorListener({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listener for Jobs-related errors (e.g., fetching open/accepted jobs)
    ref.listen<JobsState>(jobsNotifierProvider, (previous, next) {
      if (previous?.error == null && next.error != null) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        final message = userFacingMessageFromObject(context, next.error!);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
        // Important: Clear the error after displaying it.
        ref.read(jobsNotifierProvider.notifier).clearError();
      }
    });

    // Listener for Earnings-related errors
    ref.listen<EarningsState>(earningsNotifierProvider, (previous, next) {
      if (previous?.error == null && next.error != null) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        final message = userFacingMessageFromObject(context, next.error!);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
        // Important: Clear the error after displaying it.
        ref.read(earningsNotifierProvider.notifier).clearError();
      }
    });

    // This widget does not render anything itself, it just wraps the app's child.
    return child;
  }
}
