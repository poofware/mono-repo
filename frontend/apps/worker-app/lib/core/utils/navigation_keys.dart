import 'package:flutter/widgets.dart';

/// Global key for accessing the root Navigator. This allows widgets that are
/// above the [Navigator] in the widget tree to still obtain a context tied to
/// the navigator's overlay (e.g. for showing snackbars).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
