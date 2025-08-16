import 'dart:async';
import 'package:flutter/material.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';

/// Shared cache and warm-up utilities for displaying a JobMapPage in a popup
/// with identical behavior across sheets.
class JobMapCache {
  static final Map<String, JobMapPage> _mapPages = <String, JobMapPage>{};
  static final Map<String, OverlayEntry> _entries = <String, OverlayEntry>{};
  static final Map<String, Timer> _evictTimers = <String, Timer>{};
  static final Map<String, Completer<void>> _warmCompleters = <String, Completer<void>>{};

  static Future<JobMapPage> warmMap(BuildContext context, JobInstance job) async {
    final String id = job.instanceId;
    if (_mapPages.containsKey(id)) {
      final existingCompleter = _warmCompleters[id];
      if (existingCompleter != null) await existingCompleter.future;
      return _mapPages[id]!;
    }

    final completer = Completer<void>();
    _warmCompleters[id] = completer;

    final JobMapPage page = JobMapPage(
      key: GlobalObjectKey('map-$id'),
      job: job,
      isForWarmup: true,
      buildAsScaffold: false,
      onReady: () {
        if (!completer.isCompleted) completer.complete();
        _warmCompleters.remove(id);
      },
    );

    final entry = OverlayEntry(
      maintainState: true,
      builder: (_) => Offstage(child: page),
    );
    Overlay.of(context).insert(entry);

    await completer.future;
    _mapPages[id] = page;
    _entries[id] = entry;
    return page;
  }

  static Future<void> showMap(BuildContext context, JobInstance job) async {
    final String id = job.instanceId;
    final navigator = Navigator.of(context);
    final mapPage = await warmMap(context, job);

    final oldEntry = _entries[id];
    if (oldEntry != null && oldEntry.mounted) oldEntry.remove();
    _entries.remove(id);

    final popupRoute = CachedMapPopupRoute(mapPage: mapPage, instanceId: id);
    await navigator.push(popupRoute);
    await popupRoute.completed;
  }

  static void cancelEvict(String id) {
    _evictTimers[id]?.cancel();
    _evictTimers.remove(id);
  }

  static void scheduleEvict(String id) {
    _evictTimers[id]?.cancel();
    _evictTimers[id] = Timer(const Duration(seconds: 30), () {
      final entry = _entries[id];
      if (entry != null && entry.mounted) entry.remove();
      _mapPages.remove(id);
      _entries.remove(id);
      _evictTimers.remove(id);
      _warmCompleters.remove(id);
    });
  }

  static void detachOverlayFor(String id) {
    final oldMapEntry = _entries[id];
    if (oldMapEntry != null && oldMapEntry.mounted) {
      oldMapEntry.remove();
      _entries.remove(id);
    }
  }

  // Set or replace the cached overlay entry after reparenting from a route.
  static void setReparentedEntry(String id, OverlayEntry entry) {
    _entries[id] = entry;
  }
}

/// Route for viewing the warmed JobMapPage
class CachedMapPopupRoute extends PopupRoute<void> {
  final Widget mapPage;
  final String instanceId;
  CachedMapPopupRoute({required this.mapPage, required this.instanceId});

  final ValueNotifier<bool> _inRoute = ValueNotifier<bool>(true);
  bool _reparented = false;

  @override
  Color get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss map';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _inRoute,
            builder: (BuildContext context, bool show, Widget? child) =>
                show ? mapPage : const SizedBox.shrink(),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: FloatingActionButton(
                  mini: true,
                  onPressed: () => Navigator.of(context).pop(),
                  backgroundColor: Colors.white.withAlpha(230),
                  elevation: 2,
                  child: const Icon(Icons.arrow_back, color: Colors.black87),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    animation.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !_reparented) {
        _inRoute.value = false;
        final entry = OverlayEntry(
          maintainState: true,
          builder: (BuildContext context) => Offstage(child: mapPage),
        );
        Overlay.of(context).insert(entry);
        JobMapCache._entries[instanceId] = entry;
        _reparented = true;
      }
    });
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final tween = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero);
    return SlideTransition(position: tween.animate(curved), child: child);
  }
}
