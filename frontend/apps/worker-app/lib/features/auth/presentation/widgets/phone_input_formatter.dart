// worker-app/lib/features/auth/presentation/widgets/phone_input_formatter.dart
//
// Formats a US / CA phone number:
//   5551234567        → (555) 123-4567
//   +1 555-123-4567   → (555) 123-4567   ← accepts autofill chip
//
// If the user enters the leading “1” plus 10 other digits, we silently
// strip the 1 before formatting.

import 'package:flutter/services.dart';

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Strip a single leading US/CA country code “1”
    if (digits.length == 11 && digits.startsWith('1')) {
      digits = digits.substring(1);
    }

    // Reject edits that still exceed 10 digits
    if (digits.length > 10) return oldValue;

    final buf = StringBuffer();
    int i = 0;

    if (digits.isNotEmpty) {
      buf.write('(');
      buf.write(digits.substring(i, ++i)); // first digit
    }
    while (i < 3 && i < digits.length) {
      buf.write(digits[i++]);
    }

    if (digits.length > 3) {
      buf.write(') ');
      while (i < 6 && i < digits.length) {
        buf.write(digits[i++]);
      }
    }

    if (digits.length > 6) {
      buf.write('-');
      while (i < 10 && i < digits.length) {
        buf.write(digits[i++]);
      }
    }

    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

