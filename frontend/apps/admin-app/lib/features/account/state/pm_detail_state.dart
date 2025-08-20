// NEW FILE
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'pm_detail_state.freezed.dart';

@freezed
class PmDetailState with _$PmDetailState {
  const factory PmDetailState.initial() = _Initial;
  const factory PmDetailState.loading(String message) = _Loading;
  const factory PmDetailState.success(String message) = _Success;
  const factory PmDetailState.error(String error) = _Error;
}