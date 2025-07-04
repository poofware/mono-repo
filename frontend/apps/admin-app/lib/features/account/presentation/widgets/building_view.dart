// NEW FILE
import 'package:flutter/material.dart';
import 'package:poof_admin/features/account/data/models/building_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/unit_list_view.dart';

class BuildingView extends StatelessWidget {
  final List<BuildingAdmin> buildings;
  const BuildingView({super.key, required this.buildings});

  @override
  Widget build(BuildContext context) {
    if (buildings.isEmpty) {
      return const Text('No buildings for this property.');
    }
    return Column(
      children: buildings.map((building) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            title: Text(building.buildingName),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: UnitListView(units: building.units),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}