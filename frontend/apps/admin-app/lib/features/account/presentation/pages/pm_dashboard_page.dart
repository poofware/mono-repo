import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/presentation/widgets/debounce.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class PmsDashboardPage extends ConsumerStatefulWidget {
  const PmsDashboardPage({super.key});

  @override
  ConsumerState<PmsDashboardPage> createState() => _PmsDashboardPageState();
}

class _PmsDashboardPageState extends ConsumerState<PmsDashboardPage> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer(milliseconds: 500);

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

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pmListAsync = ref.watch(pmsListProvider);
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
      body: Column(
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
            child: pmListAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (pms) {
                if (pms.isEmpty) {
                  return const Center(child: Text('No property managers found.'));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(pmsListProvider.future),
                  child: ListView.builder(
                    itemCount: pms.length,
                    itemBuilder: (context, index) {
                      final pm = pms[index];
                      return ListTile(
                        title: Text(pm.businessName, style: textTheme.titleMedium),
                        subtitle: Text(pm.email),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/dashboard/pms/${pm.id}'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}