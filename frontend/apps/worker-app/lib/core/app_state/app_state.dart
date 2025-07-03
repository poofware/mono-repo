// lib/core/app_state/app_state.dart

class AppStateData {
  final bool isLoggedIn;
  final bool isLoading;

  const AppStateData({
    this.isLoggedIn  = false,
    this.isLoading   = false,
  });

  AppStateData copyWith({
    bool? isLoggedIn,
    bool? isLoading,
  }) {
    return AppStateData(
      isLoggedIn  : isLoggedIn  ?? this.isLoggedIn,
      isLoading   : isLoading   ?? this.isLoading,
    );
  }
}

