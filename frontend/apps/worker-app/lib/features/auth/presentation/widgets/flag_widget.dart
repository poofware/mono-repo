// worker-app/lib/features/auth/presentation/widgets/flag_widget.dart
//
// Renders a high-quality vector flag for an ISO-3166 alpha-2 code.
// Falls back to a grey placeholder when the code isn’t recognised.

import 'package:flutter/material.dart';
import 'package:world_flags/world_flags.dart';

class FlagWidget extends StatelessWidget {
  final String countryCode;
  final double width;
  final double height;
  final BoxFit fit;

  const FlagWidget.fromCode(
    this.countryCode, {
    super.key,
    this.width = 28,
    this.height = 21,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final code = countryCode.toUpperCase();
    final WorldCountry? country = WorldCountry.maybeFromCodeShort(code);

    if (country != null) {
      return CountryFlag.simplified(
        country,
        height: height,
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    // Placeholder for unknown codes
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        color: Colors.grey.shade100,
      ),
      alignment: Alignment.center,
      child: Text(
        code,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

