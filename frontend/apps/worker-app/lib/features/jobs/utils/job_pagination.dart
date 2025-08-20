import 'package:poof_worker/features/jobs/data/models/job_models.dart';

/// Iterates through pages from a paginated jobs endpoint using [fetchPage].
///
/// The [fetchPage] callback should request a specific page and page [size]
/// from the backend and return a [ListJobsResponse].
///
/// The [onPage] callback is invoked for each page of results as soon as it is
/// fetched, allowing callers to update state incrementally. The function stops
/// requesting new pages when the accumulated result count matches the
/// [ListJobsResponse.total] value from the API.
Future<void> fetchJobPages(
  Future<ListJobsResponse> Function(int page, int size) fetchPage, {
  required void Function(List<JobInstance> results) onPage,
  int pageSize = 50,
  int startPage = 1,
  int initialCount = 0,
}) async {
  var currentPage = startPage;
  var fetched = initialCount;

  while (true) {
    final resp = await fetchPage(currentPage, pageSize);
    fetched += resp.results.length;
    onPage(resp.results);
    if (fetched >= resp.total) {
      break;
    }
    currentPage++;
  }
}
