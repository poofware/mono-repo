// worker-app/lib/features/jobs/presentation/widgets/apartment_carousel_widget.dart

import 'package:flutter/material.dart';
import '../../data/models/job_models.dart';
import 'carousel_definition_card_widget.dart';
import 'job_accept_sheet.dart';
// import 'snappy_scroll_physics.dart'; // REMOVED SnappyScrollPhysics

/// A horizontally-scrolling page-style carousel of [DefinitionGroup] cards.
class JobDefinitionCarousel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final effectiveController =
        pageController ?? PageController(viewportFraction: viewportFraction);

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
        final vf = effectiveController.viewportFraction;
        final sideGutter = (1 - vf) * width / 2;

        return SizedBox(
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: effectiveController,
                physics: const PageScrollPhysics(),
                itemCount: definitions.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: CarouselDefinitionCard(
                      definition: definitions[index],
                      onTap: () => openSheetFor(definitions[index]),
                    ),
                  );
                },
              ),
              // Transparent tap overlay to allow single-tap during ballistic scrolls
              Builder(
                builder: (context) {
                  if (!effectiveController.hasClients) {
                    return const SizedBox.shrink();
                  }
                  return ValueListenableBuilder<bool>(
                    valueListenable: effectiveController.position.isScrollingNotifier,
                    builder: (context, isScrolling, _) {
                      return IgnorePointer(
                        ignoring: !isScrolling,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (details) {
                            if (definitions.isEmpty) return;
                            final dx = details.localPosition.dx;

                            final p = effectiveController.page ??
                                effectiveController.initialPage.toDouble();
                            int currentIndex =
                                p.round().clamp(0, definitions.length - 1);

                            int targetIndex = currentIndex;
                            if (dx <= sideGutter) {
                              targetIndex = (currentIndex - 1)
                                  .clamp(0, definitions.length - 1);
                            } else if (dx >= width - sideGutter) {
                              targetIndex = (currentIndex + 1)
                                  .clamp(0, definitions.length - 1);
                            }

                            // Snap the carousel to the tapped card for visual consistency
                            if (effectiveController.hasClients) {
                              try {
                                effectiveController.animateToPage(
                                  targetIndex,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                );
                              } catch (_) {
                                // Fallback if controller isn't ready
                                effectiveController.jumpToPage(targetIndex);
                              }
                            }

                            openSheetFor(definitions[targetIndex]);
                          },
                        ),
                      );
                    },
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
