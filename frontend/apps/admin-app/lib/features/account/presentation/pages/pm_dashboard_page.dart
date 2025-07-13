import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/debounce.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class PmsDashboardPage extends ConsumerStatefulWidget {
  const PmsDashboardPage({super.key});

  @override
  ConsumerState<PmsDashboardPage> createState() => _PmsDashboardPageState();
}

class _PmsDashboardPageState extends ConsumerState<PmsDashboardPage> {
  static const _pageSize = 20;
  final _searchController = TextEditingController();
  final _debouncer = Debouncer(milliseconds: 500);

  late final PagingController<int, PropertyManagerAdmin> _pagingController =
      PagingController(
    getNextPageKey: (state) => state.lastPageIsEmpty ? null : state.nextIntPageKey,
    fetchPage: _fetchPage,
  );

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _debouncer.run(() {
        if (mounted) {
          ref.read(pmsSearchQueryProvider.notifier).state =
              _searchController.text;
        }
      });
    });
  }

  Future<List<PropertyManagerAdmin>> _fetchPage(int pageKey) async {
    final repo = ref.read(pmsRepositoryProvider);
    final query = ref.read(pmsSearchQueryProvider);
    final requestBody = {
      'query': query,
      'page': pageKey,
      'page_size': _pageSize,
    };

    final newPage = await repo.searchPropertyManagers(requestBody);
    return newPage.items;
  }

  @override
  void dispose() {
    _pagingController.dispose();
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(pmsSearchQueryProvider, (_, __) {
      _pagingController.refresh();
    });
    ref.listen<int>(pmsListRefreshProvider, (_, __) => _pagingController.refresh());

    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Property Managers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Property Manager',
            onPressed: () => context.go('/dashboard/pms/new'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.sync(() => _pagingController.refresh()),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search by Business Name or Email',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: PagingListener(
                controller: _pagingController,
                builder: (context, state, fetchNextPage) =>
                    PagedListView<int, PropertyManagerAdmin>(
                  state: state,
                  fetchNextPage: fetchNextPage,
                  builderDelegate: PagedChildBuilderDelegate<PropertyManagerAdmin>(
                    itemBuilder: (context, item, index) => ListTile(
                      title: Text(item.businessName, style: textTheme.titleMedium),
                      subtitle: Text(item.email),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/dashboard/pms/${item.id}'),
                    ),
                    // CORRECTED: The builder signature is `Widget Function(BuildContext)`.
                    // The `state` and `fetchNextPage` variables are captured from the
                    // PagingListener's builder scope.
                    firstPageErrorIndicatorBuilder: (context) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Error loading managers: ${state.error}'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: fetchNextPage,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    noItemsFoundIndicatorBuilder: (context) => const Center(
                      child: Text('No property managers found.'),
                    ),
                    firstPageProgressIndicatorBuilder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                    newPageProgressIndicatorBuilder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}