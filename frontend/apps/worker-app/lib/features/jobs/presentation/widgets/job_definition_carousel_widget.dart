// worker-app/lib/features/jobs/presentation/widgets/apartment_carousel_widget.dart

import 'package:flutter/material.dart';
import '../../data/models/job_models.dart';
import 'carousel_definition_card_widget.dart';
import 'job_accept_sheet.dart';
// import 'snappy_scroll_physics.dart'; // REMOVED SnappyScrollPhysics

/// A horizontally-scrolling page-style carousel of [DefinitionGroup] cards.
class JobDefinitionCarousel extends StatefulWidget {
  final List<DefinitionGroup> definitions;
  final ValueChanged<int>? onPageChanged;
  final PageController? pageController;
  final double viewportFraction;

  const JobDefinitionCarousel({
    super.key,
    required this.definitions,
    this.onPageChanged,
    this.pageController,
    this.viewportFraction = 0.85,
  });

  @override
  State<JobDefinitionCarousel> createState() => _JobDefinitionCarouselState();
}

class _JobDefinitionCarouselState extends State<JobDefinitionCarousel> {
  late final PageController _controller;
  late final bool _ownsController;
  bool _isScrolling = false;
  VoidCallback? _scrollingListener;

  @override
  void initState() {
    super.initState();
    if (widget.pageController != null) {
      _controller = widget.pageController!;
      _ownsController = false;
    } else {
      _controller = PageController(viewportFraction: widget.viewportFraction);
      _ownsController = true;
    }
    // Bind after first layout so position is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindScrollNotifier());
  }

  void _bindScrollNotifier() {
    if (!_controller.hasClients) return;
    if (_scrollingListener != null) {
      _controller.position.isScrollingNotifier
          .removeListener(_scrollingListener!);
    }
    _scrollingListener = () {
      final current = _controller.position.isScrollingNotifier.value;
      // Buffer updates to next frame to avoid scheduling builds mid-layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isScrolling = current);
      });
    };
    _controller.position.isScrollingNotifier.addListener(_scrollingListener!);
    // Seed local state without forcing an immediate rebuild.
    _isScrolling = _controller.position.isScrollingNotifier.value;
  }

  @override
  void dispose() {
    if (_scrollingListener != null && _controller.hasClients) {
      _controller.position.isScrollingNotifier
          .removeListener(_scrollingListener!);
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    void openSheetFor(DefinitionGroup def) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.0),
        builder: (BuildContext context) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: JobAcceptSheet(definition: def),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final vf = _controller.viewportFraction;
        final sideGutter = (1 - vf) * width / 2;

        return SizedBox(
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.custom(
                controller: _controller,
                physics: const PageScrollPhysics(),
                onPageChanged: (index) {
                  // Only propagate page changes that occur due to user scroll.
                  if (_isScrolling) {
                    widget.onPageChanged?.call(index);
                  }
                },
                childrenDelegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final def = widget.definitions[index];
                    return Padding(
                      key: ValueKey(def.definitionId),
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: CarouselDefinitionCard(
                        definition: def,
                        onTap: () => openSheetFor(def),
                      ),
                    );
                  },
                  childCount: widget.definitions.length,
                  findChildIndexCallback: (Key key) {
                    final value = key is ValueKey ? key.value : null;
                    if (value is String) {
                      final i = widget.definitions
                          .indexWhere((d) => d.definitionId == value);
                      return i == -1 ? null : i;
                    }
                    return null;
                  },
                ),
              ),
              // Transparent tap overlay to allow single-tap during ballistic scrolls
              Builder(
                builder: (context) {
                  if (!_controller.hasClients) {
                    return const SizedBox.shrink();
                  }
                  return IgnorePointer(
                    ignoring: !_isScrolling,
                    child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (details) {
                            if (widget.definitions.isEmpty) return;
                            final dx = details.localPosition.dx;

                            final p = _controller.page ??
                                _controller.initialPage.toDouble();
                            int currentIndex =
                                p.round().clamp(0, widget.definitions.length - 1);

                            int targetIndex = currentIndex;
                            if (dx <= sideGutter) {
                              targetIndex = (currentIndex - 1)
                                  .clamp(0, widget.definitions.length - 1);
                            } else if (dx >= width - sideGutter) {
                              targetIndex = (currentIndex + 1)
                                  .clamp(0, widget.definitions.length - 1);
                            }

                            // Snap the carousel to the tapped card for visual consistency
                            if (_controller.hasClients) {
                              try {
                                _controller.animateToPage(
                                  targetIndex,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                );
                              } catch (_) {
                                // Fallback if controller isn't ready
                                _controller.jumpToPage(targetIndex);
                              }
                            }

                            openSheetFor(widget.definitions[targetIndex]);
                          },
                        ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
