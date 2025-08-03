// worker-app/lib/features/auth/presentation/widgets/six_digit_field.dart
//
// Modern 6-digit verification input
// • One-tap clipboard paste button (opt-in)
// • Auto-submit when 6 digits entered
// • Typing auto-advances, backspace auto-reverses
// • No visible cursor / no selection handles (Enhanced with EmptyTextSelectionControls)
// • Bold, always-visible box outlines
// • Material-3 color roles (Flutter 3.27)
// • FIX: keyboard is automatically restored after app resume
// (see _SixDigitFieldState._restoreKeyboardIfNeeded)
// • Responsive resizing to prevent overflow on small screens

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Required for ValueListenable in EmptyTextSelectionControls

class SixDigitField extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// The preferred size of each box (width and height). The actual size might be smaller if space is limited.
  final double boxSize;

  /// The preferred spacing between boxes. The actual spacing might be smaller if space is limited.
  final double boxSpacing;
  final bool showPasteButton;

  const SixDigitField({
    super.key,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = true,
    this.boxSize = 56,
    this.boxSpacing = 8,
    this.showPasteButton = false,
  });

  @override
  State<SixDigitField> createState() => _SixDigitFieldState();
}

class _SixDigitFieldState extends State<SixDigitField>
    with WidgetsBindingObserver {
  // ────────────────────────────────────────────────────────────
  // Controller & focus
  // ────────────────────────────────────────────────────────────

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String get _currentCode => _controller.text;
  String? _lastSubmitted; // prevents duplicate submissions

  // ────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_handleTextChange);
    // Add listener to update focus visualization
    _focusNode.addListener(_handleFocusChange);

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          _moveCaretToEnd();
        }
      });
    }
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleTextChange);
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Toggle focus after resume so a fresh TextInputConnection is built.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreKeyboardIfNeeded();
    }
  }

  void _restoreKeyboardIfNeeded() {
    if (!mounted) return;
    if (!_focusNode.hasFocus) return; // user left page – nothing to do
    _focusNode.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    // Re-focus on the next frame so we don't race the engine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  // ────────────────────────────────────────────────────────────
  // Text / paste handling
  // ────────────────────────────────────────────────────────────

  void _handleTextChange() {
    if (!mounted) return;

    final raw = _controller.text;
    final numeric = raw.replaceAll(RegExp(r'\D'), '');
    final clamped = numeric.length > 6 ? numeric.substring(0, 6) : numeric;

    if (raw != clamped) {
      _controller.text = clamped;
      _moveCaretToEnd();
    }

    // Crucial: Update the visualization of the boxes (digits and cursor position).
    setState(() {});

    _notifyParent();
    _maybeSubmit();
  }

  void _moveCaretToEnd() {
    if (!mounted) return;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  /// Reads the system clipboard and pastes the first 6 digits found.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text ?? '';
    if (txt.isEmpty || !mounted) return;

    final digits = txt.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    _controller.text = digits.substring(0, math.min(6, digits.length));
    _moveCaretToEnd();
    // _handleTextChange listener will handle the rest (setState, notify, submit)
  }

  /// Delay clipboard read just enough for splash to render first.
  Future<void> _handlePasteTap() async {
    if (mounted) await _pasteFromClipboard();
  }

  // ────────────────────────────────────────────────────────────
  // Change & submit utilities
  // ────────────────────────────────────────────────────────────

  void _notifyParent() => widget.onChanged?.call(_currentCode);

  void _maybeSubmit() {
    if (!mounted) return;
    if (_currentCode.length == 6 && _currentCode != _lastSubmitted) {
      if (_focusNode.hasFocus) {
        _focusNode.unfocus();
      }
      _lastSubmitted = _currentCode;
      widget.onSubmitted?.call(_currentCode);
    } else if (_currentCode.length < 6) {
      _lastSubmitted = null;
    }
  }

  // ────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Hidden text field that actually owns the input.
    final Widget invisibleInput = SizedBox(
      width: 1, // keep >0 so some OEM keyboards stay open
      height: 1,
      child: EditableText(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(color: Colors.transparent),
        cursorColor: Colors.transparent,
        backgroundCursorColor: Colors.transparent,
        showCursor: false,
        // Ensure no selection handles or toolbar are shown
        selectionControls: EmptyTextSelectionControls(),
      ),
    );

    // Use LayoutBuilder to adapt to the available width and prevent overflow.
    Widget field = LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;

        // 1. Calculate the maximum size a single cell can take up if width is distributed evenly.
        final double maxCellSize = availableWidth / 6.0;

        // 2. Determine the actual cell size, capped by the preferred boxSize.
        // This ensures the widget scales down when needed, but never exceeds the preferred size.
        final double cellSize = math.min(widget.boxSize, maxCellSize);

        // 3. Calculate the scaling factor (0.0 to 1.0).
        final double scaleFactor = widget.boxSize > 0
            ? (cellSize / widget.boxSize).clamp(0.0, 1.0)
            : 1.0;

        // 4. Scale spacing, border radius, and font size proportionally.
        final double spacing = widget.boxSpacing * scaleFactor;
        // Assuming 12.0 is the default borderRadius for the default 56px boxSize
        final double borderRadius = 12.0 * scaleFactor;

        final TextStyle? baseTextStyle = theme.textTheme.headlineMedium;
        final double baseFontSize = baseTextStyle?.fontSize ?? 28.0;
        // Set a minimum font size for readability (e.g., 16.0).
        final double fontSize = math.max(16.0, baseFontSize * scaleFactor);

        Widget boxes = Row(
          // Center the boxes horizontally.
          mainAxisAlignment: MainAxisAlignment.center,
          // Use min size so the Row doesn't expand beyond the required width if availableWidth is large.
          mainAxisSize: MainAxisSize.min,
          children: List.generate(6, (i) {
            final hasFocus =
                _focusNode.hasFocus && _controller.selection.baseOffset == i;
            final digit = i < _controller.text.length
                ? _controller.text[i]
                : '';

            return GestureDetector(
              onTap: () {
                if (!mounted) return;
                if (!_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                } else {
                  // Ensure keyboard is visible if focus is already present
                  _restoreKeyboardIfNeeded();
                }
                // Move caret to the tapped position.
                _controller.selection = TextSelection.collapsed(
                  offset: i.clamp(0, _controller.text.length),
                );
                // Force update visualization if selection changed
                setState(() {});
              },
              child: SizedBox(
                // Use the dynamically calculated size
                width: cellSize,
                height: cellSize,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      // Use scaled border radius
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: Border.all(
                        width: hasFocus ? 2 : 1.2,
                        color: hasFocus
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      digit,
                      // Use scaled font size
                      style: baseTextStyle?.copyWith(fontSize: fontSize),
                    ),
                  ),
                ),
              ),
            );
          }),
        );

        // The stack centers the boxes Row within the LayoutBuilder's constraints
        return Stack(
          alignment: Alignment.center,
          children: [invisibleInput, boxes],
        );
      },
    );

    if (!widget.showPasteButton) return field;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        field,
        const SizedBox(height: 12),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
            textStyle: theme.textTheme.labelLarge,
          ),
          icon: const Icon(Icons.content_paste_go),
          label: const Text('Paste code'),
          onPressed: _handlePasteTap, // splash then paste
        ),
      ],
    );
  }
}

/// Utility class to hide selection handles and toolbar
class EmptyTextSelectionControls extends TextSelectionControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    return const SizedBox.shrink();
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return Offset.zero;
  }

  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    return const SizedBox.shrink();
  }

  @override
  Size getHandleSize(double textLineHeight) {
    return Size.zero;
  }
}
