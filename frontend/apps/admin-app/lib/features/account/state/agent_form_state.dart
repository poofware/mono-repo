import 'package:poof_admin/features/account/data/models/agent_admin.dart';

abstract class AgentFormState {
  const AgentFormState();
}

class AgentFormInitial extends AgentFormState {
  const AgentFormInitial();
}

class AgentFormLoading extends AgentFormState {
  const AgentFormLoading();
}

class AgentFormSuccess extends AgentFormState {
  final String message;
  const AgentFormSuccess(this.message);
}

class AgentFormError extends AgentFormState {
  final String message;
  final Map<String, String>? fieldErrors;
  const AgentFormError(this.message, [this.fieldErrors]);
}

class AgentFormConflict extends AgentFormState {
  final AgentAdmin latestEntity;
  final String message;
  const AgentFormConflict(this.latestEntity, this.message);
}
