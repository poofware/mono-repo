class PropertyManagerAdmin {
  final String id;
  final String email;
  final String? phone;
  final String businessName;
  final String businessAddress;
  final String city;
  final String state;
  final String zipCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  PropertyManagerAdmin({
    required this.id,
    required this.email,
    this.phone,
    required this.businessName,
    required this.businessAddress,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  PropertyManagerAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        email = json['email'] as String,
        phone = json['phone'] as String?,
        businessName = json['business_name'] as String,
        businessAddress = json['business_address'] as String,
        city = json['city'] as String,
        state = json['state'] as String,
        zipCode = json['zip_code'] as String,
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

 PropertyManagerAdmin copyWith({DateTime? deletedAt}) =>
      PropertyManagerAdmin.fromJson({
        ...toJson(),
        if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
      });

            
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'phone': phone,
        'business_name': businessName,
        'business_address': businessAddress,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}