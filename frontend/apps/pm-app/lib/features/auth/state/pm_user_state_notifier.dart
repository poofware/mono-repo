import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/property_manager.dart';

/// Holds the current [PropertyManager] (if any) in memory after a successful login.
/// Clear it on logout.
class PmUserState {
  final PropertyManager? pmUser;

  const PmUserState({this.pmUser});
}

class PmUserStateNotifier extends StateNotifier<PmUserState> {
  PmUserStateNotifier() : super(const PmUserState());

  PropertyManager? get user => state.pmUser;

  void setPmUser(PropertyManager pm) {
    state = PmUserState(pmUser: pm);
  }

  void clearPmUser() {
    state = const PmUserState(pmUser: null);
  }
}

