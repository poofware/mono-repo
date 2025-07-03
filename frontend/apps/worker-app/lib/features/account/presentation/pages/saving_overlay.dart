import 'package:flutter/material.dart';

/// A full-screen veil that blocks touch and shows a spinner while
/// an operation is in progress.
class SavingOverlay extends StatelessWidget {
  const SavingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: Container(
        color: Colors.black45,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

