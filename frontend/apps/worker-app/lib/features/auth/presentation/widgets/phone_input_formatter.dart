// worker-app/lib/features/auth/presentation/widgets/phone_input_formatter.dart
import 'package:flutter/services.dart';

/// Formats the input to a US-style phone number: `(###) ###-####`.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    final newDigits = newText.replaceAll(RegExp(r'\D'), '');

    if (newDigits.length > 10) {
      return oldValue; // Don't allow more than 10 digits
    }

    final StringBuffer buffer = StringBuffer();
    int digitIndex = 0;

    if (newDigits.isNotEmpty) {
      buffer.write('(');
      if (newDigits.length > digitIndex) {
        buffer.write(newDigits.substring(digitIndex, digitIndex + 1));
        digitIndex++;
      }
    }
    while (digitIndex < 3 && digitIndex < newDigits.length) {
      buffer.write(newDigits.substring(digitIndex, digitIndex + 1));
      digitIndex++;
    }

    if (newDigits.length > 3) {
      buffer.write(') ');
      while (digitIndex < 6 && digitIndex < newDigits.length) {
        buffer.write(newDigits.substring(digitIndex, digitIndex + 1));
        digitIndex++;
      }
    }

    if (newDigits.length > 6) {
      buffer.write('-');
      while (digitIndex < 10 && digitIndex < newDigits.length) {
        buffer.write(newDigits.substring(digitIndex, digitIndex + 1));
        digitIndex++;
      }
    }

    final formattedText = buffer.toString();
    
    // Adjust cursor position
    int selectionIndex = formattedText.length;

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}
