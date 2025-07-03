class AppStateData {
  final bool isLoggedIn;
  final bool isLoading;

  const AppStateData({
    this.isLoggedIn = false,
    this.isLoading = false,
  });

  /// If you need a copyWith method for easy updates:
  AppStateData copyWith({
    bool? isLoggedIn,
    bool? isLoading,
  }) {
    return AppStateData(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
