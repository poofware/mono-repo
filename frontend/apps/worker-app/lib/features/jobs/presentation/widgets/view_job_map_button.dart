import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'job_map_cache.dart';

/// Shared "View Job Map" button with identical behavior across sheets.
class ViewJobMapButton extends ConsumerStatefulWidget {
  final JobInstance? job; // If null, the button is disabled
  final EdgeInsetsGeometry? padding;
  final bool fullWidth;

  const ViewJobMapButton({
    super.key,
    required this.job,
    this.padding,
    this.fullWidth = true,
  });

  @override
  ConsumerState<ViewJobMapButton> createState() => _ViewJobMapButtonState();
}

class _ViewJobMapButtonState extends ConsumerState<ViewJobMapButton> {
  bool _isWarming = false;

  Future<void> _handleTap(BuildContext context) async {
    if (_isWarming || widget.job == null) return;
    setState(() => _isWarming = true);
    try {
      // Warm + push without awaiting route so we can reset button immediately.
      await JobMapCache.warmMap(context, widget.job!);
      if (!mounted) return;
      setState(() => _isWarming = false);
      await JobMapCache.showMapInstant(context, widget.job!);
      return;
    } finally {
      if (mounted) setState(() => _isWarming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final label = _isWarming
        ? 'Preparing map…'
        : appLocalizations.acceptedJobsBottomSheetViewJobMap;

    final button = OutlinedButton.icon(
      onPressed: widget.job == null || _isWarming ? null : () => _handleTap(context),
      icon: const Icon(Icons.map_outlined),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.primaryColor,
        side: BorderSide(color: theme.primaryColor.withAlpha(127)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    final wrapped = widget.padding != null
        ? Padding(padding: widget.padding!, child: button)
        : button;

    if (!widget.fullWidth) return wrapped;

    return SizedBox(width: double.infinity, child: wrapped);
  }
}
