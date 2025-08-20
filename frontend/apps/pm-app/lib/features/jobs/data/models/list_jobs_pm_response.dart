import 'job_instance_pm.dart';

class ListJobsPmResponse {
  final List<JobInstancePm> results;
  final int total;

  ListJobsPmResponse({
    required this.results,
    required this.total,
  });

  factory ListJobsPmResponse.fromJson(Map<String, dynamic> json) {
    var list = json['results'] as List? ?? [];
    List<JobInstancePm> resultsList =
        list.map((i) => JobInstancePm.fromJson(i)).toList();

    return ListJobsPmResponse(
      results: resultsList,
      total: json['total'] as int? ?? 0,
    );
  }
}