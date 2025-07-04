// NEW FILE
import 'package:flutter/material.dart';
import 'package:poof_admin/features/account/data/models/unit_admin.dart';

class UnitListView extends StatelessWidget {
  final List<UnitAdmin> units;
  const UnitListView({super.key, required this.units});

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) {
      return const Text('No units in this building.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: units
          .map((unit) => ListTile(
                dense: true,
                title: Text('Unit: ${unit.unitNumber}'),
                subtitle: Text('Token: ${unit.tenantToken}'),
              ))
          .toList(),
    );
  }
}