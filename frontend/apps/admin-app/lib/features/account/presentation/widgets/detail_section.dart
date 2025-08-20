// NEW FILE
import 'package:flutter/material.dart';

class DetailSection extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;
  final Widget child;

  const DetailSection({
    super.key,
    required this.title,
    required this.onAdd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onAdd,
              tooltip: 'Add $title',
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}