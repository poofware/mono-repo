import 'package:poof_flutter_auth/poof_flutter_auth.dart';

class ListJobsPmRequest implements JsonSerializable {
  final String propertyId;

  const ListJobsPmRequest({required this.propertyId});

  @override
  Map<String, dynamic> toJson() => {
        'property_id': propertyId,
      };
}