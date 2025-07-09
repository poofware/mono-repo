// NEW FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/dumpster_form_state.dart';

class DumpsterFormNotifier extends StateNotifier<DumpsterFormState> {
  final Ref _ref;

  DumpsterFormNotifier(this._ref) : super(const DumpsterFormState.initial());

  Future<bool> createDumpster(String pmId, Map<String, dynamic> data) async {
    state = const DumpsterFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.createDumpster(data);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const DumpsterFormState.success('Dumpster created successfully!');
      return true;
    } on ApiException catch (e) {
      state = DumpsterFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = DumpsterFormState.error(e.toString());
      return false;
    }
  }

  Future<bool> updateDumpster(
      String dumpsterId, String pmId, Map<String, dynamic> data) async {
    state = const DumpsterFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.updateDumpster(dumpsterId, data);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const DumpsterFormState.success('Dumpster updated successfully!');
      return true;
    } on ApiException catch (e) {
      state = DumpsterFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = DumpsterFormState.error(e.toString());
      return false;
    }
  }
}