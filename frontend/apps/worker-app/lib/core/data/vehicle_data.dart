import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class VehicleData {
  VehicleData._();

  static Map<String, List<String>>? _modelsByMake;
  static List<String>? _makes;

  static String _titleCase(String s) {
    return s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Loads the bundled vehicle data json if it hasn't been loaded yet.
  static Future<void> ensureLoaded() async {
    if (_modelsByMake != null) return;
    final jsonStr =
        await rootBundle.loadString('assets/jsons/vehicle_data.json');
    final Map<String, dynamic> data = jsonDecode(jsonStr);
    _makes = (data['makes'] as List).cast<String>();
    final map = data['modelsByMake'] as Map<String, dynamic>;
    _modelsByMake = {
      for (final entry in map.entries)
        entry.key.toUpperCase(): (entry.value as List).cast<String>(),
    };
  }

  static Future<List<String>> searchMakes(String query) async {
    await ensureLoaded();
    final q = query.toUpperCase();
    return _makes!
        .where((m) => m.toUpperCase().contains(q))
        .take(10)
        .map(_titleCase)
        .toList();
  }

  static Future<List<String>> searchModels(String make, String query) async {
    await ensureLoaded();
    final models = _modelsByMake![make.toUpperCase()];
    if (models == null) return [];
    final q = query.toUpperCase();
    return models
        .where((m) => m.toUpperCase().contains(q))
        .take(15)
        .map(_titleCase)
        .toList();
  }
}
