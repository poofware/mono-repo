import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:poof_admin/features/account/data/models/agent_admin.dart';

import 'test_context.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;

  AgentAdmin? createdAgent;

  group('Agents API Flow', () {
    testWidgets('Create Agent', (tester) async {
      final repo = TestContext.accountRepo;
      expect(repo, isNotNull, reason: 'Account repository must be initialized by prior auth test.');

      final payload = {
        'name': 'Integration Agent',
        'email': 'agent-int-test@example.com',
        'phone_number': '+15555550123',
        'address': '1 Agent Way',
        'city': 'Testville',
        'state': 'CA',
        'zip_code': '90210',
        'latitude': 34.0,
        'longitude': -118.0,
      };

      createdAgent = await repo!.createAgent(payload);
      expect(createdAgent, isNotNull);
      expect(createdAgent!.name, equals('Integration Agent'));
    });

    testWidgets('Update Agent', (tester) async {
      final repo = TestContext.accountRepo;
      expect(createdAgent, isNotNull, reason: 'Agent must be created first.');

      final updated = await repo!.updateAgent({
        'id': createdAgent!.id,
        'name': 'Integration Agent (Updated)'
      });
      expect(updated.name, equals('Integration Agent (Updated)'));
      createdAgent = updated;
    });

    testWidgets('Delete Agent', (tester) async {
      final repo = TestContext.accountRepo;
      expect(createdAgent, isNotNull, reason: 'Agent must be created first.');

      await repo!.deleteAgent({'id': createdAgent!.id});
    });
  });
}
