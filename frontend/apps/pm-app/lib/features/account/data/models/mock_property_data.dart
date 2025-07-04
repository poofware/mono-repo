// lib/features/account/data/models/mock_property_data.dart
import 'property_model.dart';

/// A class that provides static mock data for properties.
/// This is used in `testMode` to avoid making real API calls.
class MockPropertyData {
  static final List<Property> properties = [
    Property(
      id: 'prop_mock_1',
      name: 'The Grand Residences',
      address: '123 Grand Ave, Anytown, USA',
    ),
    Property(
      id: 'prop_mock_2',
      name: 'Willow Creek Flats',
      address: '456 Willow Creek Rd, Anytown, USA',
    ),
    Property(
      id: 'prop_mock_3',
      name: 'Oak Ridge Lofts',
      address: '789 Oak Ridge Ln, Anytown, USA',
    ),
  ];
}