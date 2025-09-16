import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AgentsDashboardPage extends StatelessWidget {
  const AgentsDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Create Agent',
            onPressed: () => context.go('/dashboard/agents/new'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: const Center(
        child: Text('Agents list coming soon.'),
      ),
    );
  }
}
