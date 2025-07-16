// worker-app/lib/features/jobs/presentation/widgets/tap_ripple_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/providers/tap_ripple_provider.dart';

class TapRippleOverlay extends ConsumerWidget {
  const TapRippleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ripples = ref.watch(tapRippleProvider);

    return IgnorePointer(
      child: Stack(
        children: [
          for (final r in ripples)
            _AnimatedRipple(
              key: ValueKey(r.id),
              offset: r.offset, 
              onDone: () =>
                  ref.read(tapRippleProvider.notifier).remove(r.id),
            ),
        ],
      ),
    );
  }
}

class _AnimatedRipple extends StatefulWidget {
  const _AnimatedRipple(
      {super.key, required this.offset, required this.onDone});

  final Offset offset; 
  final VoidCallback onDone;

  @override
  State<_AnimatedRipple> createState() => _AnimatedRippleState();
}

class _AnimatedRippleState extends State<_AnimatedRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Faster animation
    duration: const Duration(milliseconds: 250), 
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final v = _controller.value; 
        
        // Smaller diameter: initial 32, expands by 24
        final double initialDiameter = 32;
        final double expansionAmount = 16;
        final double currentDiameter = initialDiameter + (v * expansionAmount);
        final double currentRadius = currentDiameter / 2;

        return Positioned(
          left: widget.offset.dx - currentRadius,
          top: widget.offset.dy - currentRadius,
          child: Opacity(
            opacity: 0.8 * (1 - v), // More transparent (max 0.8 * (1-0) = 0.8, fades to 0)
            child: Container(
              width: currentDiameter,
              height: currentDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Even more transparent base color, or use the opacity property primarily
                color: Colors.black.withValues(alpha: 0.10), 
              ),
            ),
          ),
        );
      },
    );
  }
}
