// NEW FILE
import 'package:flutter/material.dart';

class DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const DetailItem({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(value, style: textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}