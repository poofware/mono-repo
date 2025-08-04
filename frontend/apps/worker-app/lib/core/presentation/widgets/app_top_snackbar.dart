// lib/core/utils/app_top_snackbar.dart
//
// Slim, top-of-screen SnackBar that matches the app’s SnackBarThemeData
// but now takes an arbitrary widget for its content and honours
// a `displayDuration:` parameter.

import 'package:flutter/material.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

/// Show a themed top SnackBar anywhere in the app.
///
/// ```dart
/// showAppSnackBar(
///   context,
///   SelectableText('DEBUG: $message'),
///   displayDuration: const Duration(seconds: 15),
/// );
/// ```
void showAppSnackBar(
  BuildContext context,
  Widget content, {
  Duration displayDuration = const Duration(seconds: 3),
  VoidCallback? onAction,
  String actionLabel = 'OK',
  VoidCallback? onTap, // fires before the bar animates off
}) {
  showTopSnackBar(
    Overlay.of(context),
    _AppSnackBar(
      content: content,
      onAction: onAction,
      actionLabel: actionLabel,
    ),
    // ── animation & lifecycle ───────────────────────────────────────────
    displayDuration: displayDuration,
    animationDuration: const Duration(milliseconds: 800),
    reverseAnimationDuration: const Duration(milliseconds: 400),
    curve: Curves.elasticOut, // playful bounce-in
    dismissType: DismissType.onTap, // tap anywhere to dismiss
    onTap: onTap,
    // ── layout adjustments ─────────────────────────────────────────────
    padding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8, // slimmer than default SnackBar
    ),
  );
}

/// Internal widget that mirrors your SnackBarThemeData but
/// accepts an arbitrary content widget.
class _AppSnackBar extends StatelessWidget {
  const _AppSnackBar({
    required this.content,
    this.onAction,
    required this.actionLabel,
  });

  final Widget content;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).snackBarTheme;

    return SafeArea(
      top: true, // keeps clear of the notch/status bar
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Material(
          color: theme.backgroundColor ?? Colors.grey[800],
          elevation: theme.elevation ?? 4,
          shape:
              theme.shape ??
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10, // tighter vertical space
                    horizontal: 16,
                  ),
                  child: DefaultTextStyle(
                    style:
                        theme.contentTextStyle ??
                        const TextStyle(color: Colors.white70),
                    child: content,
                  ),
                ),
              ),
              if (onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        theme.actionTextColor ?? Colors.cyan.shade300,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    actionLabel.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
