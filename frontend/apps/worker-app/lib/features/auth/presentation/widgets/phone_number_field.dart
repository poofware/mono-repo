// worker-app/lib/features/auth/presentation/widgets/phone_number_field.dart
//
// Phone input with country picker and OS autofill support
// • Curated country list common for US-based users
// • Detects dial-code in pasted / autofilled numbers and switches flag
// • Formats US/CA numbers & validates length
// • Material-3 styling

import 'package:flutter/material.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/theme/app_colors.dart';

import 'phone_input_formatter.dart';
import 'flag_widget.dart';

String countryCodeToFlagEmoji(String countryCode) {
  if (countryCode.length != 2) return countryCode;
  final upper = countryCode.toUpperCase();
  return String.fromCharCodes([
    upper.codeUnitAt(0) + 0x1F1E6 - 0x41,
    upper.codeUnitAt(1) + 0x1F1E6 - 0x41,
  ]);
}

class CountryData {
  final String countryNameKey; // ARB key for country name
  final String isoCode;        // “US”
  final String dialCode;       // “+1”

  const CountryData({
    required this.countryNameKey,
    required this.isoCode,
    required this.dialCode,
  });

  String get flagEmoji => countryCodeToFlagEmoji(isoCode);

  String localizedName(AppLocalizations l) {
    switch (countryNameKey) {
      case 'countryNameUS':
        return l.countryNameUS;
      case 'countryNameCA':
        return l.countryNameCA;
      case 'countryNameMX':
        return l.countryNameMX;
      case 'countryNameGB':
        return l.countryNameGB;
      case 'countryNameAU':
        return l.countryNameAU;
      case 'countryNameDE':
        return l.countryNameDE;
      default:
        return isoCode; // Fallback
    }
  }
}

/// Phone-number input with country picker.
class PhoneNumberField extends StatefulWidget {
  final void Function(String fullNumber, bool isValid)? onChanged;
  final String labelText;
  final String initialLocalNumber;
  final String initialDialCode;
  final bool autofocus;
  final FocusNode? focusNode;

  const PhoneNumberField({
    super.key,
    this.onChanged,
    required this.labelText,
    this.initialLocalNumber = '',
    this.initialDialCode = '+1',
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  static const _countries = <CountryData>[
    CountryData(countryNameKey: 'countryNameUS', isoCode: 'US', dialCode: '+1'),
    CountryData(countryNameKey: 'countryNameCA', isoCode: 'CA', dialCode: '+1'),
    CountryData(countryNameKey: 'countryNameMX', isoCode: 'MX', dialCode: '+52'),
    CountryData(countryNameKey: 'countryNameGB', isoCode: 'GB', dialCode: '+44'),
    CountryData(countryNameKey: 'countryNameAU', isoCode: 'AU', dialCode: '+61'),
    CountryData(countryNameKey: 'countryNameDE', isoCode: 'DE', dialCode: '+49'),
  ];

  late CountryData _selectedCountry;
  late final TextEditingController _localCtl;
  bool _selfEdit = false; // prevent recursion

  @override
  void initState() {
    super.initState();

    _selectedCountry = _countries.firstWhere(
      (c) => c.dialCode == widget.initialDialCode,
      orElse: () => _countries.first,
    );

    final formatter = PhoneInputFormatter();
    final initValue = formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: widget.initialLocalNumber),
    );

    _localCtl = TextEditingController(text: initValue.text)
      ..addListener(_notifyChange);

    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyChange());
  }

  @override
  void dispose() {
    _localCtl.removeListener(_notifyChange);
    _localCtl.dispose();
    super.dispose();
  }

  /// Detect dial-code prefixes, switch flag, re-format, and emit changes.
  void _notifyChange() {
    if (_selfEdit) return;

    // Extract digits
    var raw = _localCtl.text.replaceAll(RegExp(r'\D'), '');

    // Detect a dial code at the front
    CountryData? detected;
    for (final c in _countries) {
      final codeDigits = c.dialCode.substring(1); // “+1” → “1”
      if (raw.startsWith(codeDigits) && raw.length > codeDigits.length) {
        detected = c;
        raw = raw.substring(codeDigits.length);   // strip the dial code
        break;
      }
    }

    // selector if necessary
    if (detected != null && detected != _selectedCountry) {
      setState(() => _selectedCountry = detected!);
    }

    // Re-format local part after stripping
    if (detected != null) {
      _selfEdit = true;
      final formatted = PhoneInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(text: raw),
      );
      _localCtl.value = formatted;
      _selfEdit = false;
    }

    // Emit full E.164 and simple length validity
    final fullE164 = '${_selectedCountry.dialCode}$raw';
    widget.onChanged?.call(fullE164, raw.length == 10);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AutofillGroup(
      child: TextField(
        focusNode: widget.focusNode,
        controller: _localCtl,
        keyboardType: TextInputType.phone,
        autofocus: widget.autofocus,
        autofillHints: const [
          AutofillHints.telephoneNumber,
          AutofillHints.telephoneNumberDevice,
          AutofillHints.telephoneNumberNational,
        ],
        inputFormatters: [PhoneInputFormatter()],
        decoration: InputDecoration(
          labelText: widget.labelText,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.poofColor, width: 2),
          ),
          prefixIcon: _countryPicker(l),
        ),
      ),
    );
  }

  Widget _countryPicker(AppLocalizations l) => PopupMenuButton<CountryData>(
        tooltip: l.phoneNumberFieldTooltip,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (c) {
          setState(() => _selectedCountry = c);
          _notifyChange();
        },
        itemBuilder: (context) => [
          for (final c in _countries)
            PopupMenuItem(
              value: c,
              child: Row(
                children: [
                  FlagWidget.fromCode(c.isoCode),
                  const SizedBox(width: 12),
                  Text(c.localizedName(l)),
                  const SizedBox(width: 8),
                  Text(
                    c.dialCode,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlagWidget.fromCode(_selectedCountry.isoCode),
              const SizedBox(width: 8),
              Text(
                _selectedCountry.dialCode,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 24),
            ],
          ),
        ),
      );
}

