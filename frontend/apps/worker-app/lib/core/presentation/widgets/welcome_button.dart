import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poof_worker/core/theme/app_colors.dart';

/// A tactile, low-latency button with a press-down shrink, haptic feedback,
/// and a loading spinner that starts the moment the press bottoms out.
///
/// * **Press animation:** ~4 % scale shrink with 90 ms ease-out curve.
/// * **Haptics:** Light impact on first frame of touch-down.
/// * **Loading vs. disabled colors:**  
///   * Loading → faded primary (40 % opacity).  
///   * Disabled → neutral grey.
/// * Accepts either `void` or `Future<void>` callbacks via `FutureOr<void>`.
class WelcomeButton extends StatefulWidget {
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

  final String text;
  final FutureOr<void> Function()? onPressed;
  final bool isLoading;
  final bool showSpinner;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? textColor;
  final TextStyle? textStyle;

  @override
  State<WelcomeButton> createState() => _WelcomeButtonState();
}

class _WelcomeButtonState extends State<WelcomeButton> {
  static const _pressedScale = 0.96;
  static const _animDuration = Duration(milliseconds: 90);

  bool _pressed = false;
  bool _loading = false;

  @override
  void didUpdateWidget(covariant WelcomeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Allow external state (e.g., Bloc) to override local loading flag.
    if (widget.isLoading != _loading) {
      setState(() => _loading = widget.isLoading);
    }
  }

  Future<void> _handleTap() async {
    if (widget.onPressed == null || _loading) return;

    setState(() => _loading = true);

    final result = widget.onPressed!();
    if (result is Future) await result;

    if (mounted) setState(() => _loading = false);
  }

  void _animatePress(bool down) {
    setState(() => _pressed = down);
    if (down) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.elevatedButtonTheme.style ?? const ButtonStyle();

    // Base (active) colors.
    final Color activeBg =
        style.backgroundColor?.resolve({}) ?? theme.colorScheme.primary;
    final Color activeFg =
        style.foregroundColor?.resolve({}) ?? theme.colorScheme.onPrimary;

    // Derived colors for states.
    final Color loadingBg = activeBg.withValues(alpha: 0.4);           // faded primary
    final Color disabledBg = Colors.grey.shade300;
    final Color disabledFg = Colors.grey.shade600;

    return AnimatedScale(
      scale: _pressed ? _pressedScale : 1.0,
      duration: _animDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: Listener(
        onPointerDown: (_) => _animatePress(true),
        onPointerUp: (_) => _animatePress(false),
        onPointerCancel: (_) => _animatePress(false),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: activeBg,
              foregroundColor: activeFg,
              disabledBackgroundColor: _loading ? loadingBg : disabledBg,
              disabledForegroundColor: _loading ? activeFg : disabledFg,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: (_loading || widget.onPressed == null)
                  ? 0
                  : style.elevation?.resolve({}),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed:
                (_loading || widget.onPressed == null) ? null : _handleTap,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _loading && widget.showSpinner
                  ? const SizedBox(
                      key: ValueKey('spinner'),
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.poofColor,
                      ),
                    )
                  : Text(
                      widget.text,
                      key: const ValueKey('label'),
                      style: widget.textStyle ??
                          TextStyle(
                            fontSize: widget.fontSize ?? 16,
                            fontWeight: widget.fontWeight ?? FontWeight.bold,
                            color: widget.textColor,
                          ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

