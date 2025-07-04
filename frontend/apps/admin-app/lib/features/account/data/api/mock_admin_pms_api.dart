import 'dart:math';

import 'package:flutter/foundation.dart';
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
            JobDefinitionAdmin(id: _uuid.v4(), managerId: pm1Id, propertyId: prop1Id, title: 'Daily Trash Pickup', frequency: 'DAILY', createdAt: DateTime.now(), updatedAt: DateTime.now()),
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
    _initialized = true;
    debugPrint('[MockAdminPmsApi] Initialized with seed data.');
  }

  // --- Search / Get ---

  Future<List<PropertyManagerAdmin>> searchPropertyManagers(String query) async {
    await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));
    final lowerQuery = query.toLowerCase();

    final activePms = _data.where((s) => s.propertyManager.deletedAt == null);

    if (query.isEmpty) {
      return activePms.map((s) => s.propertyManager.copyWith()).toList();
    }
    return activePms
        .where((s) =>
            s.propertyManager.businessName.toLowerCase().contains(lowerQuery) ||
            s.propertyManager.email.toLowerCase().contains(lowerQuery))
        .map((s) => s.propertyManager.copyWith())
        .toList();
  }

  Future<PmsSnapshot> getSnapshot(String pmId) async {
    await Future.delayed(Duration(milliseconds: 400 + _random.nextInt(500)));
    final snapshot = _data.firstWhere((s) => s.propertyManager.id == pmId);
    
    // Filter out soft-deleted properties before returning
    final activeProperties = snapshot.properties.where((p) => p.deletedAt == null).toList();
    return snapshot.copyWith(properties: activeProperties);
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

  // --- Update Methods (PATCH) ---

  Future<PropertyManagerAdmin> updatePropertyManager(
      String pmId, Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
    _updateConflictCounter++;
    if (_updateConflictCounter % 3 == 0) {
      throw ApiException(409, 'Conflict detected. Please refresh and try again.');
    }

    final pmIndex = _data.indexWhere((s) => s.propertyManager.id == pmId);
    if (pmIndex == -1) {
      throw ApiException(404, 'Property Manager not found');
    }

    final oldPm = _data[pmIndex].propertyManager;
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
      String propertyId, Map<String, dynamic> data) async {
    await Future.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
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

  // --- Delete Methods (Soft Delete) ---

  Future<void> deletePropertyManager(String pmId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final pmIndex = _data.indexWhere((s) => s.propertyManager.id == pmId);
    if (pmIndex != -1) {
      final oldPm = _data[pmIndex].propertyManager;
      final deletedPm = oldPm.copyWith(deletedAt: DateTime.now());
      _data[pmIndex] = _data[pmIndex].copyWith(propertyManager: deletedPm);
    } else {
       throw ApiException(404, 'Property Manager not found');
    }
  }

  Future<void> deleteProperty(String propertyId) async {
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

  // TODO: Implement create/update/delete for Building, Unit, Dumpster, JobDefinition
}
}