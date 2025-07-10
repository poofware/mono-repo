import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:poof_admin/core/models/paginated_response.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:uuid/uuid.dart';

class MockAdminPmsApi {
  final _uuid = const Uuid();
  final _random = Random();
  final List<PmsSnapshot> _data = [];
  bool _initialized = false;
  int _updateConflictCounter = 0;

  MockAdminPmsApi() {
    _init();
  }

  void _init() {
    if (_initialized) return;

    // Seed with some initial data
    final pm1Id = _uuid.v4();
    final prop1Id = _uuid.v4();
    final prop2Id = _uuid.v4();
    final bldg1Id = _uuid.v4();
    final bldg2Id = _uuid.v4();

    _data.add(PmsSnapshot(
      propertyManager: PropertyManagerAdmin(
        id: pm1Id,
        email: 'john.doe@example.com',
        phone: '+15551234567',
        businessName: 'Doe Property Management',
        businessAddress: '123 Main St',
        city: 'Anytown',
        state: 'CA',
        zipCode: '12345',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        updatedAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      properties: [
        PropertyAdmin(
          id: prop1Id,
          managerId: pm1Id,
          propertyName: 'Oakwood Apartments',
          address: '456 Oak Ave',
          city: 'Anytown',
          state: 'CA',
          zipCode: '12345',
          timeZone: 'America/Los_Angeles',
          latitude: 34.0522,
          longitude: -118.2437,
          createdAt: DateTime.now().subtract(const Duration(days: 9)),
          updatedAt: DateTime.now().subtract(const Duration(days: 4)),
          buildings: [
            BuildingAdmin(
              id: bldg1Id,
              propertyId: prop1Id,
              buildingName: 'Building 1',
              units: [
                UnitAdmin(id: _uuid.v4(), propertyId: prop1Id, buildingId: bldg1Id, unitNumber: '101', tenantToken: _uuid.v4(), createdAt: DateTime.now(), updatedAt: DateTime.now()),
                UnitAdmin(id: _uuid.v4(), propertyId: prop1Id, buildingId: bldg1Id, unitNumber: '102', tenantToken: _uuid.v4(), createdAt: DateTime.now(), updatedAt: DateTime.now()),
              ],
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
             BuildingAdmin(
              id: bldg2Id,
              propertyId: prop1Id,
              buildingName: 'Building 2',
              units: [
                UnitAdmin(id: _uuid.v4(), propertyId: prop1Id, buildingId: bldg2Id, unitNumber: '201', tenantToken: _uuid.v4(), createdAt: DateTime.now(), updatedAt: DateTime.now()),
              ],
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          dumpsters: [
            DumpsterAdmin(id: _uuid.v4(), propertyId: prop1Id, dumpsterNumber: 'D-01', latitude: 34.0520, longitude: -118.2430, createdAt: DateTime.now(), updatedAt: DateTime.now()),
          ],
          jobDefinitions: [
                        JobDefinitionAdmin(
              id: _uuid.v4(),
              managerId: pm1Id,
              propertyId: prop1Id,
              title: 'Daily Trash Pickup',
              scheduleType: 'DAILY',
              jobWindowMinutes: 120,
              payRate: 25.50,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now()),
            ],
        ),
         PropertyAdmin(
          id: prop2Id,
          managerId: pm1Id,
          propertyName: 'Willow Creek Condos',
          address: '789 Willow Ln',
          city: 'Anytown',
          state: 'CA',
          zipCode: '12346',
          timeZone: 'America/Los_Angeles',
          latitude: 34.0533,
          longitude: -118.2448,
          createdAt: DateTime.now().subtract(const Duration(days: 8)),
          updatedAt: DateTime.now().subtract(const Duration(days: 3)),
          buildings: [],
          dumpsters: [],
          jobDefinitions: [],
        ),
      ],
    ));
    // Add more data for pagination testing
    for (var i = 2; i <= 50; i++) {
      _data.add(PmsSnapshot(
        propertyManager: PropertyManagerAdmin(
          id: _uuid.v4(),
          email: 'manager$i@corp.com',
          businessName: 'Global Real Estate #$i',
          businessAddress: '$i Business Park',
          city: 'Metropolis',
          state: 'NY',
          zipCode: '10001',
          createdAt: DateTime.now().subtract(Duration(days: i * 2)),
          updatedAt: DateTime.now().subtract(Duration(days: i)),
        ),
        properties: [],
      ));
    }
    _initialized = true;
    debugPrint('[MockAdminPmsApi] Initialized with seed data.');
  }

  // --- Search / Get ---

  Future<PaginatedResponse<PropertyManagerAdmin>> searchPropertyManagers(
      Map<String, dynamic> body) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));

    final query = (body['query'] as String? ?? '').toLowerCase();
    final page = body['page'] as int? ?? 1;
    final pageSize = body['page_size'] as int? ?? 20;

    final activePms = _data.where((s) => s.propertyManager.deletedAt == null);

    final filteredPms = query.isEmpty
        ? activePms.map((s) => s.propertyManager.copyWith()).toList()
        : activePms
            .where((s) =>
                s.propertyManager.businessName.toLowerCase().contains(query) ||
                s.propertyManager.email.toLowerCase().contains(query))
            .map((s) => s.propertyManager.copyWith())
            .toList();

    final totalCount = filteredPms.length;
    final startIndex = (page - 1) * pageSize;

    if (startIndex >= totalCount) {
      return PaginatedResponse(
          items: [], totalCount: totalCount, hasMore: false);
    }

    final endIndex = min(startIndex + pageSize, totalCount);
    final pageItems = filteredPms.sublist(startIndex, endIndex);
    final hasMore = endIndex < totalCount;

    return PaginatedResponse(
      items: pageItems,
      totalCount: totalCount,
      hasMore: hasMore,
    );
  }

  Future<PmsSnapshot> getSnapshot(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 400 + _random.nextInt(500)));
    final pmId = data['manager_id'] as String;
    final snapshot = _data.firstWhere((s) => s.propertyManager.id == pmId);

    // Filter out soft-deleted properties
    final activeProperties =
        snapshot.properties.where((p) => p.deletedAt == null);

    // Filter soft-deleted children within each property
    final propertiesWithFilteredChildren = activeProperties.map((prop) {
      final activeBuildings = prop.buildings.where((b) => b.deletedAt == null).map((building) {
        final activeUnits =
            building.units.where((u) => u.deletedAt == null).toList();
        // create a new BuildingAdmin with only active units
        return BuildingAdmin.fromJson(
            building.toJson()..['units'] = activeUnits.map((e) => e.toJson()).toList());
      }).toList();

      final activeDumpsters =
          prop.dumpsters.where((d) => d.deletedAt == null).toList();
      final activeJobDefs =
          prop.jobDefinitions.where((j) => j.deletedAt == null).toList();

      return prop.copyWith(
        buildings: activeBuildings,
        dumpsters: activeDumpsters,
        jobDefinitions: activeJobDefs,
      );
    }).toList();

    return snapshot.copyWith(properties: propertiesWithFilteredChildren);
  }

  // --- Create Methods ---

  Future<PropertyManagerAdmin> createPropertyManager(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 300 + _random.nextInt(400)));
    
    // Simulate validation error
    if ((data['email'] as String).contains('invalid')) {
      throw ApiException(422, 'Validation Failed', {'email': 'This email is not valid.'});
    }

    final newPm = PropertyManagerAdmin(
      id: _uuid.v4(),
      email: data['email'] as String,
      phone: data['phone'] as String?,
      businessName: data['business_name'] as String,
      businessAddress: data['business_address'] as String,
      city: data['city'] as String,
      state: data['state'] as String,
      zipCode: data['zip_code'] as String,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _data.add(PmsSnapshot(propertyManager: newPm, properties: []));
    return newPm;
  }

  Future<PropertyAdmin> createProperty(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 300 + _random.nextInt(400)));
    final pmId = data['manager_id'] as String;
    final newProp = PropertyAdmin.fromJson({
      ...data,
      'id': _uuid.v4(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'buildings': [],
      'dumpsters': [],
      'job_definitions': [],
    });

    final pmIndex = _data.indexWhere((s) => s.propertyManager.id == pmId);
    if (pmIndex != -1) {
      _data[pmIndex].properties.add(newProp);
    }
    return newProp;
  }

  Future<BuildingAdmin> createBuilding(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));
    final propertyId = data['property_id'] as String;
    final newBuilding = BuildingAdmin.fromJson({
      ...data,
      'id': _uuid.v4(),
      'units': [],
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    for (final snapshot in _data) {
      final propIndex = snapshot.properties.indexWhere((p) => p.id == propertyId);
      if (propIndex != -1) {
        snapshot.properties[propIndex].buildings.add(newBuilding);
        return newBuilding;
      }
    }
    throw ApiException(404, 'Property not found to add building to.');
  }

  Future<UnitAdmin> createUnit(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));
    final propertyId = data['property_id'] as String;
    final buildingId = data['building_id'] as String;

    final newUnit = UnitAdmin.fromJson({
      ...data,
      'id': _uuid.v4(),
      'tenant_token': _uuid.v4(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    for (final snapshot in _data) {
      try {
        final prop = snapshot.properties.firstWhere((p) => p.id == propertyId);
        final buildingIndex = prop.buildings.indexWhere((b) => b.id == buildingId);
        if (buildingIndex != -1) {
          prop.buildings[buildingIndex].units.add(newUnit);
          return newUnit;
        }
      } catch (e) {
        // Continue to next snapshot
      }
    }
    throw ApiException(404, 'Building or Property not found to add unit to.');
  }

  Future<DumpsterAdmin> createDumpster(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));
    final propertyId = data['property_id'] as String;
    final newDumpster = DumpsterAdmin.fromJson({
      ...data,
      'id': _uuid.v4(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    for (final snapshot in _data) {
      final propIndex = snapshot.properties.indexWhere((p) => p.id == propertyId);
      if (propIndex != -1) {
        snapshot.properties[propIndex].dumpsters.add(newDumpster);
        return newDumpster;
      }
    }
    throw ApiException(404, 'Property not found to add dumpster to.');
  }

  Future<JobDefinitionAdmin> createJobDefinition(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));
    final propertyId = data['property_id'] as String;
    final newJobDef = JobDefinitionAdmin.fromJson({
      ...data,
      'id': _uuid.v4(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'building_ids': data['building_ids'] ?? [],
      'dumpster_ids': data['dumpster_ids'] ?? [],
    });

    for (final snapshot in _data) {
      final propIndex = snapshot.properties.indexWhere((p) => p.id == propertyId);
      if (propIndex != -1) {
        snapshot.properties[propIndex].jobDefinitions.add(newJobDef);
        return newJobDef;
      }
    }
    throw ApiException(404, 'Property not found to add job definition to.');
  }


  // --- Update Methods (PATCH) ---

  Future<PropertyManagerAdmin> updatePropertyManager(
      Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    _updateConflictCounter++;

    final pmId = data['id'] as String;
    final pmIndex = _data.indexWhere((s) => s.propertyManager.id == pmId);
    if (pmIndex == -1) {
      throw ApiException(404, 'Property Manager not found');
    }
    final oldPm = _data[pmIndex].propertyManager;
    
    if (_updateConflictCounter % 3 == 0) {
      throw ApiException(409, 'Conflict detected. This record was updated by someone else.', null, oldPm);
    }
    
    final updatedPm = PropertyManagerAdmin.fromJson({
      ...oldPm.toJson(), // Start with old data
      ...data, // Overwrite with new data
      'id': pmId, // Ensure ID is preserved
      'updated_at': DateTime.now().toIso8601String(),
    });
    
    _data[pmIndex] = _data[pmIndex].copyWith(propertyManager: updatedPm);
    return updatedPm;
  }

  Future<PropertyAdmin> updateProperty(
      Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    final propertyId = data['id'] as String;
    for (final snapshot in _data) {
      final propIndex = snapshot.properties.indexWhere((p) => p.id == propertyId);
      if (propIndex != -1) {
        final oldProp = snapshot.properties[propIndex];
        final updatedProp = PropertyAdmin.fromJson({
          ...oldProp.toJson(),
          ...data,
          'id': propertyId,
          'updated_at': DateTime.now().toIso8601String(),
        });
        snapshot.properties[propIndex] = updatedProp;
        return updatedProp;
      }
    }
    throw ApiException(404, 'Property not found');
  }

  Future<BuildingAdmin> updateBuilding(
      Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    final buildingId = data['id'] as String;
    for (final snapshot in _data) {
      for (final prop in snapshot.properties) {
        final buildingIndex = prop.buildings.indexWhere((b) => b.id == buildingId);
        if (buildingIndex != -1) {
          final oldBuilding = prop.buildings[buildingIndex];
          final updatedBuilding = BuildingAdmin.fromJson({
            ...oldBuilding.toJson(),
            ...data,
            'id': buildingId,
            'updated_at': DateTime.now().toIso8601String(),
          });
          prop.buildings[buildingIndex] = updatedBuilding;
          return updatedBuilding;
        }
      }
    }
    throw ApiException(404, 'Building not found');
  }

  Future<UnitAdmin> updateUnit(Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    final unitId = data['id'] as String;
    for (final snapshot in _data) {
      for (final prop in snapshot.properties) {
        for (final building in prop.buildings) {
          final unitIndex = building.units.indexWhere((u) => u.id == unitId);
          if (unitIndex != -1) {
            final oldUnit = building.units[unitIndex];
            final updatedUnit = UnitAdmin.fromJson({
              ...oldUnit.toJson(),
              ...data,
              'id': unitId,
              'updated_at': DateTime.now().toIso8601String(),
            });
            building.units[unitIndex] = updatedUnit;
            return updatedUnit;
          }
        }
      }
    }
    throw ApiException(404, 'Unit not found');
  }

  Future<DumpsterAdmin> updateDumpster(
      Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    final dumpsterId = data['id'] as String;
    for (final snapshot in _data) {
      final propIndex =
          snapshot.properties.indexWhere((p) => p.dumpsters.any((d) => d.id == dumpsterId));
      if (propIndex != -1) {
        final prop = snapshot.properties[propIndex];
        final dumpsterIndex = prop.dumpsters.indexWhere((d) => d.id == dumpsterId);
        final oldDumpster = prop.dumpsters[dumpsterIndex];
        final updatedDumpster = DumpsterAdmin.fromJson({
          ...oldDumpster.toJson(),
          ...data,
          'id': dumpsterId,
          'updated_at': DateTime.now().toIso8601String(),
        });
        prop.dumpsters[dumpsterIndex] = updatedDumpster;
        return updatedDumpster;
      }
    }
    throw ApiException(404, 'Dumpster not found');
  }

  Future<JobDefinitionAdmin> updateJobDefinition(
      Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    final jobDefinitionId = data['id'] as String;
    for (final snapshot in _data) {
      final propIndex = snapshot.properties
          .indexWhere((p) => p.jobDefinitions.any((j) => j.id == jobDefinitionId));
      if (propIndex != -1) {
        final prop = snapshot.properties[propIndex];
        final jobDefIndex =
            prop.jobDefinitions.indexWhere((j) => j.id == jobDefinitionId);
        final oldJobDef = prop.jobDefinitions[jobDefIndex];
        final updatedJobDef = JobDefinitionAdmin.fromJson({
          ...oldJobDef.toJson(),
          ...data,
          'id': jobDefinitionId,
          'updated_at': DateTime.now().toIso8601String(),
        });
        snapshot.properties[propIndex].jobDefinitions[jobDefIndex] = updatedJobDef;
        return updatedJobDef;
      }
    }
    throw ApiException(404, 'Job Definition not found');
  }

  // --- Delete Methods (Soft Delete) ---

  Future<void> deletePropertyManager(Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final pmId = data['id'] as String;
    final pmIndex = _data.indexWhere((s) => s.propertyManager.id == pmId);
    if (pmIndex != -1) {
      final oldPm = _data[pmIndex].propertyManager;
      final deletedPm = oldPm.copyWith(deletedAt: DateTime.now());
      _data[pmIndex] = _data[pmIndex].copyWith(propertyManager: deletedPm);
    } else {
       throw ApiException(404, 'Property Manager not found');
    }
  }

  Future<void> deleteProperty(Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final propertyId = data['id'] as String;
    // Find the index of the snapshot containing the property
    final snapshotIndex = _data.indexWhere((s) => s.properties.any((p) => p.id == propertyId));

    if (snapshotIndex != -1) {
      final snapshot = _data[snapshotIndex];
      // Create a new list of properties, updating the one to be deleted
      final newProperties = snapshot.properties.map((p) {
        if (p.id == propertyId) {
          return p.copyWith(deletedAt: DateTime.now());
        }
        return p;
      }).toList();
      // Replace the old snapshot with the new one
      _data[snapshotIndex] = snapshot.copyWith(properties: newProperties);
    } else {
      throw ApiException(404, 'Property not found');
    }
  }

  Future<void> deleteBuilding(Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final buildingId = data['id'] as String;
    for (final snapshot in _data) {
      for (int i = 0; i < snapshot.properties.length; i++) {
        final prop = snapshot.properties[i];
        final buildingIndex = prop.buildings.indexWhere((b) => b.id == buildingId);
        if (buildingIndex != -1) {
          final oldBuilding = prop.buildings[buildingIndex];
          final newBuilding = oldBuilding.copyWith(deletedAt: DateTime.now());
          prop.buildings[buildingIndex] = newBuilding;
          return;
        }
      }
    }
    throw ApiException(404, 'Building not found');
  }

  Future<void> deleteUnit(Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final unitId = data['id'] as String;
    for (final snapshot in _data) {
      for (final prop in snapshot.properties) {
        for (int i = 0; i < prop.buildings.length; i++) {
          final building = prop.buildings[i];
          final unitIndex = building.units.indexWhere((u) => u.id == unitId);
          if (unitIndex != -1) {
            final oldUnit = building.units[unitIndex];
            final newUnit = oldUnit.copyWith(deletedAt: DateTime.now());
            building.units[unitIndex] = newUnit;
            return;
          }
        }
      }
    }
    throw ApiException(404, 'Unit not found');
  }

  Future<void> deleteDumpster(Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final dumpsterId = data['id'] as String;
    for (final snapshot in _data) {
      for (int i = 0; i < snapshot.properties.length; i++) {
        final prop = snapshot.properties[i];
        final dumpsterIndex = prop.dumpsters.indexWhere((d) => d.id == dumpsterId);
        if (dumpsterIndex != -1) {
          final oldDumpster = prop.dumpsters[dumpsterIndex];
          final newDumpster = oldDumpster.copyWith(deletedAt: DateTime.now());
          prop.dumpsters[dumpsterIndex] = newDumpster;
          return;
        }
      }
    }
    throw ApiException(404, 'Dumpster not found');
  }

  Future<void> deleteJobDefinition(Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final jobDefinitionId = data['id'] as String;
    for (final snapshot in _data) {
      for (int i = 0; i < snapshot.properties.length; i++) {
        final prop = snapshot.properties[i];
        final jobDefIndex =
            prop.jobDefinitions.indexWhere((j) => j.id == jobDefinitionId);
        if (jobDefIndex != -1) {
          final oldJobDef = prop.jobDefinitions[jobDefIndex];
          final newJobDef = oldJobDef.copyWith(deletedAt: DateTime.now());
          prop.jobDefinitions[jobDefIndex] = newJobDef;
          return;
        }
      }
    }
    throw ApiException(404, 'Job Definition not found');
  }

}