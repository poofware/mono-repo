// worker-app/lib/features/jobs/providers/tap_ripple_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _TapRipple {
  _TapRipple(this.id, this.offset);
  final int id;
  final Offset offset;          // logical pixels (MediaQuery global coordinates)
}

class TapRippleNotifier extends StateNotifier<List<_TapRipple>> {
  TapRippleNotifier() : super([]);
  int _id = 0;

  void add(Offset offset) => state = [...state, _TapRipple(_id++, offset)];

  void remove(int id) => state = state.where((r) => r.id != id).toList();
}

final tapRippleProvider =
    StateNotifierProvider<TapRippleNotifier, List<_TapRipple>>(
        (_) => TapRippleNotifier());
