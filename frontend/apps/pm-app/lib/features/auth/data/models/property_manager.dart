class PropertyManager {
  final String email;
  final String? phoneNumber;
  final String businessName;
  final String businessAddress;
  final String city;
  final String state;
  final String zipCode;
  final String accountStatus;
  final String setupProgress;

  PropertyManager({
    required this.email,
    this.phoneNumber,
    required this.businessName,
    required this.businessAddress,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.accountStatus,
    required this.setupProgress,
  });

  factory PropertyManager.fromJson(Map<String, dynamic> json) {
    return PropertyManager(
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
      businessName: json['business_name'] as String? ?? '',
      businessAddress: json['business_address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zipCode: json['zip_code'] as String? ?? '',
      accountStatus: json['account_status'] as String? ?? '',
      setupProgress: json['setup_progress'] as String? ?? '',
    );
  }
}

