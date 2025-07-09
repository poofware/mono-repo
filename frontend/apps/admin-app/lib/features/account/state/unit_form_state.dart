// NEW FILE
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'unit_form_state.freezed.dart';

@freezed
class UnitFormState with _$UnitFormState {
  const factory UnitFormState.initial() = _Initial;
  const factory UnitFormState.loading() = _Loading;
  const factory UnitFormState.success(String message) = _Success;
  const factory UnitFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;
}