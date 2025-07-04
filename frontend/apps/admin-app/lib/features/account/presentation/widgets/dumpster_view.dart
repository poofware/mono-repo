// NEW FILE
import 'package:flutter/material.dart';
import 'package:poof_admin/features/account/data/models/dumpster_admin.dart';

class DumpsterView extends StatelessWidget {
  final List<DumpsterAdmin> dumpsters;
  const DumpsterView({super.key, required this.dumpsters});

  @override
  Widget build(BuildContext context) {
    if (dumpsters.isEmpty) {
      return const Text('No dumpsters for this property.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: dumpsters
          .map((d) => ListTile(
                dense: true,
                title: Text('Dumpster #${d.dumpsterNumber}'),
                subtitle: Text('Coords: ${d.latitude}, ${d.longitude}'),
              ))
          .toList(),
    );
  }
}