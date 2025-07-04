import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'property_form_state.freezed.dart';

@freezed
class PropertyFormState with _$PropertyFormState {
  const factory PropertyFormState.initial() = _Initial;
  const factory PropertyFormState.loading() = _Loading;
  const factory PropertyFormState.success(String message) = _Success;
  const factory PropertyFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;
}