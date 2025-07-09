import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';

part 'pm_form_state.freezed.dart';

@freezed
class PmFormState with _$PmFormState {
  const factory PmFormState.initial() = _Initial;
  const factory PmFormState.loading() = _Loading;
  const factory PmFormState.success(String message) = _Success;
  const factory PmFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;
  const factory PmFormState.conflict(
    PropertyManagerAdmin latestEntity,
    String message,
  ) = _Conflict;
}