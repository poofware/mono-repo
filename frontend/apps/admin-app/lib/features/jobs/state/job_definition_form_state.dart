// frontend/apps/admin-app/lib/features/jobs/state/job_definition_form_state.dart
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'job_definition_form_state.freezed.dart';

@freezed
class JobDefinitionFormState with _$JobDefinitionFormState {
  // Add private constructor to allow custom getters
  const JobDefinitionFormState._();

  const factory JobDefinitionFormState.initial() = _Initial;
  const factory JobDefinitionFormState.loading() = _Loading;
  const factory JobDefinitionFormState.success(String message) = _Success;
  const factory JobDefinitionFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;

  // Add a getter for loading state
  bool get isLoading => maybeWhen(
        loading: () => true,
        orElse: () => false,
      );
}