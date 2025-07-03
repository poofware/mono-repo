// worker-app/lib/core/providers/localization_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Default to English if no locale is set
final currentLocaleProvider = StateProvider<Locale>((ref) => const Locale('en'));
