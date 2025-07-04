import '../api/account_api.dart';
import '../models/property_model.dart';

class PropertiesRepository {
  final PropertiesApi _propertiesApi;

  PropertiesRepository({required PropertiesApi propertiesApi})
      : _propertiesApi = propertiesApi;

  /// Fetches the list of properties for the currently authenticated manager.
  Future<List<Property>> fetchProperties() async {
    // For now, it just passes the call through.
    // Later, you could add caching logic here.
    return _propertiesApi.fetchProperties();
  }
}