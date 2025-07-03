// worker-app/lib/features/auth/presentation/widgets/flag_widget.dart
import 'package:flutter/material.dart';
import 'package:world_flags/world_flags.dart';

/// Renders a high-quality vector flag for an ISO-3166 alpha-2 code (e.g. “US”).
/// Falls back to the grey placeholder when the code isn’t recognised.
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
    // Sanitise input once
    final code = countryCode.toUpperCase();

    // `maybeFromCodeShort` returns null if the code is not valid
    final WorldCountry? country = WorldCountry.maybeFromCodeShort(code);

    if (country != null) {
      // Draw the flag with a tiny border-radius to match your UI
      return CountryFlag.simplified(
        country,
        height: height,
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    // Graceful fallback – identical to your old placeholder
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

