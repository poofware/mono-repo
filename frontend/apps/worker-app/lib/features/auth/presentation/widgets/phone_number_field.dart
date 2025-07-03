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
  final String isoCode;   // “US”
  final String dialCode;  // “+1”

  const CountryData({
    required this.countryNameKey,
    required this.isoCode,
    required this.dialCode,
  });

  String get flagEmoji => countryCodeToFlagEmoji(isoCode);

  String localizedName(AppLocalizations localizations) {
    // This is a simplified lookup. A more robust system might use a map or switch.
    switch (countryNameKey) {
      case 'countryNameUS':
        return localizations.countryNameUS;
      case 'countryNameGB':
        return localizations.countryNameGB;
      case 'countryNameCA':
        return localizations.countryNameCA;
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
    required this.labelText, // Made required, should be localized by caller
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
    CountryData(countryNameKey: 'countryNameGB', isoCode: 'GB', dialCode: '+44'),
    CountryData(countryNameKey: 'countryNameCA', isoCode: 'CA', dialCode: '+1'),
    // Extend as needed...
  ];

  late CountryData _selectedCountry;
  late final TextEditingController _localCtl;

  @override
  void initState() {
    super.initState();
    _selectedCountry = _countries.firstWhere(
      (c) => c.dialCode == widget.initialDialCode,
      orElse: () => _countries.first,
    );

    // FIX 1: Format the initial number before setting it on the controller.
    final formatter = PhoneInputFormatter();
    final initialFormattedValue = formatter.formatEditUpdate(
      TextEditingValue.empty, // oldValue is not needed for initial formatting
      TextEditingValue(text: widget.initialLocalNumber),
    );

    _localCtl = TextEditingController(text: initialFormattedValue.text)
      ..addListener(_notifyChange);

    // FIX 2: Call _notifyChange after the first frame to ensure the parent
    // widget receives the initial validity state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notifyChange();
      }
    });
  }

  @override
  void dispose() {
    _localCtl.removeListener(_notifyChange);
    _localCtl.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final rawDigits = _localCtl.text.replaceAll(RegExp(r'\D'), '');
    final fullNumber = '${_selectedCountry.dialCode}$rawDigits';

    // For now, assume US/CA validation. A more complex system could use a map of regexes per isoCode.
    final bool isValid = rawDigits.length == 10;

    widget.onChanged?.call(fullNumber, isValid);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return TextField(
      focusNode: widget.focusNode,
      controller: _localCtl,
      keyboardType: TextInputType.phone,
      autofocus: widget.autofocus,
      inputFormatters: [PhoneInputFormatter()],
      decoration: InputDecoration(
        labelText: widget.labelText, // Caller provides localized labelText
        filled: true,
        fillColor: theme.colorScheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.poofColor, width: 2),
        ),
        prefixIcon: PopupMenuButton<CountryData>(
          tooltip: appLocalizations.phoneNumberFieldTooltip,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
                    Text(c.localizedName(appLocalizations)),
                    const SizedBox(width: 8),
                    Text(c.dialCode, style: TextStyle(color: Colors.grey.shade600)),
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
        ),
      ),
    );
  }
}
