class PropertySubset {
  final String propertyId;
  final String propertyName;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final double latitude;
  final double longitude;

  PropertySubset({
    required this.propertyId,
    required this.propertyName,
    required this.address,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.latitude,
    required this.longitude,
  });

  factory PropertySubset.fromJson(Map<String, dynamic> json) {
    return PropertySubset(
      propertyId: json['property_id'] as String? ?? '',
      propertyName: json['property_name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zipCode: json['zip_code'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}