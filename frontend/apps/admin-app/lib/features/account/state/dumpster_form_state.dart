// NEW FILE
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'dumpster_form_state.freezed.dart';

@freezed
class DumpsterFormState with _$DumpsterFormState {
  const factory DumpsterFormState.initial() = _Initial;
  const factory DumpsterFormState.loading() = _Loading;
  const factory DumpsterFormState.success(String message) = _Success;
  const factory DumpsterFormState.error(
    String message, [
    Map<String, String>? fieldErrors,
  ]) = _Error;
}