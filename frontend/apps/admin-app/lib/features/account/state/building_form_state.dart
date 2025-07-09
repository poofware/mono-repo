// NEW FILE
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'building_form_state.freezed.dart';

@freezed
class BuildingFormState with _$BuildingFormState {
  const factory BuildingFormState.initial() = _Initial;
  const factory BuildingFormState.loading() = _Loading;
  const factory BuildingFormState.success(String message) = _Success;
  const factory BuildingFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;
}