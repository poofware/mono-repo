import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/data/models/agent_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/agent_form_state.dart';

class AgentFormNotifier extends StateNotifier<AgentFormState> {
  final Ref _ref;

  AgentFormNotifier(this._ref) : super(const AgentFormInitial());

  Future<bool> createAgent(Map<String, dynamic> data) async {
    state = const AgentFormLoading();
    try {
      final repo = _ref.read(adminAccountRepositoryProvider);
      await repo.createAgent(data);
      state = const AgentFormSuccess('Agent created successfully!');
      return true;
    } on ApiException catch (e) {
      state = AgentFormError(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = AgentFormError(e.toString());
      return false;
    }
  }

  Future<bool> updateAgent(Map<String, dynamic> data) async {
    state = const AgentFormLoading();
    try {
      await _ref.read(adminAccountRepositoryProvider).updateAgent(data);
      state = const AgentFormSuccess('Agent updated successfully!');
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.entity is AgentAdmin) {
        state = AgentFormConflict(
          e.entity as AgentAdmin,
          e.message,
        );
      } else if (e.statusCode == 409) {
        state = const AgentFormError(
          'Conflict: This record was updated by someone else. Please refresh and try again.',
        );
      } else {
        state = AgentFormError(e.message, e.fieldErrors);
      }
      return false;
    } catch (e) {
      state = AgentFormError(e.toString());
      return false;
    }
  }

  Future<bool> deleteAgent(String id) async {
    state = const AgentFormLoading();
    try {
      await _ref
          .read(adminAccountRepositoryProvider)
          .deleteAgent({'id': id});
      state = const AgentFormSuccess('Agent deleted successfully!');
      return true;
    } on ApiException catch (e) {
      state = AgentFormError(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = AgentFormError(e.toString());
      return false;
    }
  }
}
