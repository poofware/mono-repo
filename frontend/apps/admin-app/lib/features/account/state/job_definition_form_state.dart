// NEW FILE
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'job_definition_form_state.freezed.dart';

@freezed
class JobDefinitionFormState with _$JobDefinitionFormState {
  const factory JobDefinitionFormState.initial() = _Initial;
  const factory JobDefinitionFormState.loading() = _Loading;
  const factory JobDefinitionFormState.success(String message) = _Success;
  const factory JobDefinitionFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;
}