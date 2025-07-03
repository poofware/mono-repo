import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus { online, offline }

class NetworkStatusNotifier extends StateNotifier<NetworkStatus> {
  NetworkStatusNotifier() : super(NetworkStatus.online) {
    _connectivity.onConnectivityChanged.listen((results) => _update(results));
    _update(null);
  }

  final Connectivity _connectivity = Connectivity();

  Future<void> _update(List<ConnectivityResult>? results) async {
    final res = results?.first ??
        (await _connectivity.checkConnectivity());
    state = (res == ConnectivityResult.none)
        ? NetworkStatus.offline
        : NetworkStatus.online;
  }
}

final networkStatusProvider =
    StateNotifierProvider<NetworkStatusNotifier, NetworkStatus>(
  (_) => NetworkStatusNotifier(),
);

