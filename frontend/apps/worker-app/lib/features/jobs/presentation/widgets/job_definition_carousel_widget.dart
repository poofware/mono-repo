// worker-app/lib/features/jobs/presentation/widgets/apartment_carousel_widget.dart

import 'package:flutter/material.dart';
import '../../data/models/job_models.dart';
import 'carousel_definition_card_widget.dart';
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

    return SizedBox(
      height: 140,
      child: PageView.builder(
        controller: effectiveController,
        physics: const PageScrollPhysics(), // UPDATED to standard PageScrollPhysics
        itemCount: definitions.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: CarouselDefinitionCard(definition: definitions[index]),
          );
        },
      ),
    );
  }
}
