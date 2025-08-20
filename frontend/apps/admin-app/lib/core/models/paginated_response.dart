// NEW FILE
class PaginatedResponse<T> {
  final List<T> items;
  final int totalCount;
  final bool hasMore;

  PaginatedResponse({
    required this.items,
    required this.totalCount,
    required this.hasMore,
  });
}