// worker-app/lib/features/auth/presentation/widgets/six_digit_field.dart
//
// Modern 6-digit verification input
// • One-tap clipboard paste button (opt-in)
// • Auto-submit when 6 digits entered
// • Typing auto-advances, backspace auto-reverses (soft & hardware)
// • No visible cursor / no selection handles
// • Bold, always-visible box outlines
// • Material-3 color roles (Flutter 3.27)
//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

class SixDigitField extends StatefulWidget {
  /// Fires every time the aggregated six-digit string changes.
  final ValueChanged<String>? onChanged;

  /// Fires **once** when the field reaches exactly six digits.
  /// The callback is *not* invoked again unless the user deletes a digit and
  /// re-enters a new full code.
  final ValueChanged<String>? onSubmitted;

  /// Whether the first box requests focus on mount.
  final bool autofocus;

  /// Size (width & height) of each digit box.
  final double boxSize;

  /// Horizontal gap between boxes.
  final double boxSpacing;

  /// Show a clipboard-paste button directly under the field.
  /// Defaults to `false` so nothing appears unless you opt-in.
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

class _SixDigitFieldState extends State<SixDigitField> {
  // ────────────────────────────────────────────────────────────
  // Single controller & focus (IME-friendly)
  // ────────────────────────────────────────────────────────────

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String get _currentCode => _controller.text;
  String? _lastSubmitted; // Prevents duplicate calls.

  // ────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _controller.addListener(_handleTextChange);

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        _moveCaretToEnd();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────
  // Text / paste handling
  // ────────────────────────────────────────────────────────────

  void _handleTextChange() {
    final raw = _controller.text;
    final numeric = raw.replaceAll(RegExp(r'\D'), '');
    final clamped = numeric.length > 6 ? numeric.substring(0, 6) : numeric;

    // Only mutate the controller if we actually changed the text.
    if (raw != clamped) {
      _controller.text = clamped;
      _moveCaretToEnd(); // Needed because we overwrote the text.
    }

    _notifyParent();
    _maybeSubmit();
  }

  void _moveCaretToEnd() {
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  /// Reads the system clipboard and pastes the first 6 digits found.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text ?? '';
    if (txt.isEmpty) return;

    final digits = txt.replaceAll(RegExp(r'\D'), '');
    _controller.text = digits.substring(0, math.min(6, digits.length));
    _moveCaretToEnd();
    _notifyParent();
    _maybeSubmit();
  }

  // ────────────────────────────────────────────────────────────
  // Change & submit utilities
  // ────────────────────────────────────────────────────────────

  void _notifyParent() => widget.onChanged?.call(_currentCode);

  void _maybeSubmit() {
    if (_currentCode.length == 6 && _currentCode != _lastSubmitted) {
      // Dismiss keyboard and clear focus.
      _focusNode.unfocus();
      _lastSubmitted = _currentCode;
      widget.onSubmitted?.call(_currentCode);
    } else if (_currentCode.length < 6) {
      // Reset guard so a fresh 6-digit entry can submit again later.
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
      width: 0,
      height: 0,
      child: EditableText(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(color: Colors.transparent),
        cursorColor: Colors.transparent,
        backgroundCursorColor: Colors.transparent,
        showCursor: false,
      ),
    );

    Widget boxes = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final hasFocus = _focusNode.hasFocus && _controller.selection.baseOffset == i;
        final digit = i < _controller.text.length ? _controller.text[i] : '';

        return GestureDetector(
          onTap: () {
            _focusNode.requestFocus();
            _controller.selection = TextSelection.collapsed(offset: i.clamp(0, _controller.text.length));
          },
          child: SizedBox(
            width: widget.boxSize,
            height: widget.boxSize,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.boxSpacing / 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: hasFocus ? 2 : 1.2,
                    color: hasFocus ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  digit,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ),
          ),
        );
      }),
    );

    Widget field = Stack(
      alignment: Alignment.center,
      children: [invisibleInput, boxes],
    );

    if (!widget.showPasteButton) return field;

    return Column(
      mainAxisSize: MainAxisSize.min,
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
          onPressed: _pasteFromClipboard,
        ),
      ],
    );
  }
}

