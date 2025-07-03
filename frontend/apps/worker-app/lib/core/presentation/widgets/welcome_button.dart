import 'package:flutter/material.dart';
import 'package:poof_worker/core/theme/app_colors.dart';

class WelcomeButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool showSpinner;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? textColor;
  final TextStyle? textStyle;

  const WelcomeButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.showSpinner = true,
    this.fontSize,
    this.fontWeight,
    this.textColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.elevatedButtonTheme.style;

    // Define base colors from the theme for consistency.
    final Color activeBackgroundColor =
        style?.backgroundColor?.resolve({}) ?? theme.colorScheme.primary;
    final Color activeForegroundColor =
        style?.foregroundColor?.resolve({}) ?? theme.colorScheme.onPrimary;

    // Define colors for specific disabled states.
    final Color loadingBackgroundColor = activeBackgroundColor.withValues(alpha: 0.4);
    final Color disabledBackgroundColor = Colors.grey.shade300;
    final Color disabledForegroundColor = Colors.grey.shade600;

    // Create a base style using the convenient `styleFrom`
    final ButtonStyle baseStyle = ElevatedButton.styleFrom(
      backgroundColor: activeBackgroundColor,
      foregroundColor: activeForegroundColor,
      disabledBackgroundColor:
          isLoading ? loadingBackgroundColor : disabledBackgroundColor,
      disabledForegroundColor:
          isLoading ? activeForegroundColor : disabledForegroundColor,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: (onPressed == null && !isLoading)
          ? 0
          : style?.elevation?.resolve({}),
    );

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        // Use `copyWith` to merge the base style with the state-dependent overlayColor.
        style: baseStyle.copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) {
                return loadingBackgroundColor;
              }
              return null; // Use the default splash for other states
            },
          ),
        ),
        // The button is disabled if it's loading OR if the original callback is null.
        onPressed: isLoading ? null : onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: (isLoading && showSpinner)
              ? Center(
                  key: const ValueKey('loading'),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.0,
                      color: AppColors.poofColor,
                    ),
                  ),
                )
                            : Text(
                  text,
                  key: ValueKey(text),
                  style: textStyle ?? TextStyle(
                    fontSize: fontSize ?? 16,
                    fontWeight: fontWeight ?? FontWeight.bold,
                    color: textColor,
                  ),
                ),
        ),
      ),
    );
  }
}
