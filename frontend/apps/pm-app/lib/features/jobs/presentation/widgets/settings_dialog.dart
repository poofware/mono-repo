// lib/features/dashboard/presentation/widgets/settings_dialog.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A modal dialog that displays app settings, such as the sign-out option.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      // Use ClipRRect to apply border radius to the content area
      contentPadding: EdgeInsets.zero, // Remove default padding to use our own
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        child: SizedBox(
          width: 300, // Constrain width for a better dialog appearance
          child: Column(
            mainAxisSize: MainAxisSize.min, // Shrink-wrap the content
            children: [
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign Out'),
                onTap: () {
                  // First, pop the dialog from the navigation stack.
                  Navigator.of(context).pop();
                  // Then, navigate to the dedicated signing out page.
                  context.go('/signing_out');
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Simply pop the dialog to close it.
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}