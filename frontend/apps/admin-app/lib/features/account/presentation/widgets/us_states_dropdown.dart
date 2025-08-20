// NEW FILE
import 'package:flutter/material.dart';

const List<String> kUsStateAbbreviations = [
  'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID',
  'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS',
  'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK',
  'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV',
  'WI', 'WY'
];

class StateDropdown extends StatelessWidget {
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  const StateDropdown({
    super.key,
    required this.selectedValue,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: selectedValue,
        decoration: InputDecoration(
          labelText: 'State',
          border: const OutlineInputBorder(),
          errorText: errorText,
        ),
        items: kUsStateAbbreviations
            .map((state) => DropdownMenuItem(value: state, child: Text(state)))
            .toList(),
        onChanged: onChanged,
        validator: (value) =>
            value == null || value.isEmpty ? 'State is required.' : null,
      ),
    );
  }
}