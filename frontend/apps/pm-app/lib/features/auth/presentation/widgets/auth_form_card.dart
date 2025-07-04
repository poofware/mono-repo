import 'package:flutter/material.dart';

/// A reusable card widget for authentication forms that provides a consistent
/// look and feel, including decoration, padding, and an optional styled footer.
///
/// This widget encapsulates the common `Container` with a `BoxDecoration`
/// (surface color, border, shadow) and handles the layout for a main `child`
/// content area and an optional `footer` with a distinct background.
class AuthFormCard extends StatelessWidget {
  const AuthFormCard({
    super.key,
    required this.child,
    this.footer,
    this.padding,
  });

  /// The main content of the card, placed within the padded area.
  /// Typically a `Column` containing form fields and buttons.
  final Widget child;

  /// An optional footer widget, displayed below the main content with a
  /// distinct background color. Used for links like "Create account" or "Sign in".
  final Widget? footer;

  /// The padding for the main content area. Defaults to a standard value if null.
  /// This can be overridden for pages with different layout needs (e.g., info pages).
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              // Adjust bottom padding if a footer is present to maintain consistent spacing.
              padding: padding ??
                  EdgeInsets.fromLTRB(32, 32, 32, footer == null ? 32 : 24),
              child: child,
            ),
            if (footer != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}