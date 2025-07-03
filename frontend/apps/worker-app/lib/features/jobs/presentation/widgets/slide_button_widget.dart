// press_to_slide_cancel.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

/// ----------------------------------------
/// SlideAction (from your original code)
/// ----------------------------------------
class SlideAction extends StatefulWidget {
  /// The size of the sliding icon
  final double sliderButtonIconSize;

  /// The padding of the sliding icon
  final double sliderButtonIconPadding;

  /// The offset on the y axis of the slider icon
  final double sliderButtonYOffset;

  /// If the slider icon rotates. MODIFIED: Default is now false.
  final bool sliderRotate;

  // Whether the user can interact with the slider
  final bool enabled;

  /// The child rendered instead of the default Text widget
  final Widget? child;

  /// The height of the component
  final double height;

  /// The color of the text. Defaults to primaryIconTheme color if null.
  final Color? textColor;

  /// The color of the inner circular button / tick icon.
  /// Defaults to Theme.of(context).primaryIconTheme.color if null.
  final Color? innerColor;

  /// The color of the external area and arrow icon.
  /// Defaults to Theme.of(context).colorScheme.secondary if null.
  final Color? outerColor;

  /// The text shown if [child] is null
  final String? text;

  /// The text style applied to the default Text widget
  final TextStyle? textStyle;

  /// The borderRadius of the sliding icon and background
  final double borderRadius;

  /// Callback called on submit
  /// If null, no “complete” animation is triggered
  final Future<void> Function()? onSubmit;

  /// Elevation of the component
  final double elevation;

  /// The widget to render instead of the default arrow icon
  final Widget? sliderButtonIcon;

  /// The widget to render instead of the default submitted icon (checkmark)
  // final Widget? submittedIcon; // No longer needed, spinner is used

  /// The duration of the animations
  final Duration animationDuration;

  /// If true the widget will be reversed (flip horizontally)
  final bool reversed;

  /// The alignment of the widget once it's submitted
  final Alignment alignment;

  /// The point where the onSubmit callback should be executed (0.1..1.0)
  final double trigger;

  /// NEW: If false, the default "shrink and check" animation is skipped.
  /// This is useful when the parent widget wants to show its own loading state.
  final bool showSubmittedAnimation;

  const SlideAction({
    super.key,
    this.sliderButtonIconSize = 24,
    this.sliderButtonIconPadding = 16,
    this.sliderButtonYOffset = 0,
    this.sliderRotate = false, // MODIFIED: Default changed to false
    this.enabled = true,
    this.height = 70,
    this.textColor,
    this.innerColor,
    this.outerColor,
    this.borderRadius = 52,
    this.elevation = 6,
    this.animationDuration = const Duration(milliseconds: 300),
    this.reversed = false,
    this.alignment = Alignment.center,
    // this.submittedIcon, // No longer needed
    this.onSubmit,
    this.child,
    this.text,
    this.textStyle,
    this.sliderButtonIcon,
    this.trigger = 0.8,
    this.showSubmittedAnimation = true, // NEW PROPERTY
  }) : assert(0.1 <= trigger && trigger <= 1.0);

  @override
  SlideActionState createState() => SlideActionState();
}

class SlideActionState extends State<SlideAction>
    with TickerProviderStateMixin {
  final GlobalKey _containerKey = GlobalKey();
  final GlobalKey _sliderKey = GlobalKey();

  double _dx = 0;
  double _maxDx = 0;
  double get _progress => _dx == 0 ? 0 : _dx / _maxDx;
  double _endDx = 0;
  double _dz = 1; // Used to scale the slider
  double? _initialContainerWidth, _containerWidth;
  // double _checkAnimationDx = 0; // No longer needed for checkmark animation
  bool submitted = false;

  // late AnimationController _checkAnimationController; // No longer needed
  late AnimationController _shrinkAnimationController;
  late AnimationController _resizeAnimationController;
  late AnimationController _cancelAnimationController;

  @override
  void initState() {
    super.initState();
    _cancelAnimationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    // _checkAnimationController = AnimationController( // No longer needed
    //   vsync: this,
    //   duration: widget.animationDuration,
    // );
    _shrinkAnimationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _resizeAnimationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? containerBox =
          _containerKey.currentContext?.findRenderObject() as RenderBox?;
      if (containerBox != null) {
        _containerWidth = containerBox.size.width;
        _initialContainerWidth = _containerWidth;

        final RenderBox? sliderBox =
            _sliderKey.currentContext?.findRenderObject() as RenderBox?;
        if (sliderBox != null) {
          final sliderWidth = sliderBox.size.width;
          _maxDx = _containerWidth! -
              (sliderWidth / 2) -
              40 -
              widget.sliderButtonYOffset;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(widget.reversed ? pi : 0),
        child: Container(
          key: _containerKey,
          height: widget.height,
          width: _containerWidth,
          constraints: _containerWidth != null
              ? null
              : BoxConstraints.expand(height: widget.height),
          child: Material(
            elevation: widget.elevation,
            color: widget.outerColor ?? Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: submitted
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(widget.reversed ? pi : 0),
                    child: Center(
                      child: SizedBox(
                        width: widget.height * 0.5, // Spinner size
                        height: widget.height * 0.5, // Spinner size
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.innerColor ??
                                Theme.of(context).primaryIconTheme.color!,
                          ),
                        ),
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // The text/child behind the slider
                      Opacity(
                        opacity: 1 - 1 * _progress,
                        child: Transform(
                          alignment: Alignment.center,
                          transform:
                              Matrix4.rotationY(widget.reversed ? pi : 0),
                          child: widget.child ??
                              Text(
                                widget.text ?? 'Slide to act',
                                textAlign: TextAlign.center,
                                style: widget.textStyle ??
                                    TextStyle(
                                      color: widget.textColor ??
                                          Theme.of(context)
                                              .primaryIconTheme
                                              .color,
                                      fontSize: 24,
                                    ),
                              ),
                        ),
                      ),

                      // The slider button
                      Positioned(
                        left: widget.sliderButtonYOffset,
                        child: Transform.scale(
                          scale: _dz,
                          origin: Offset(_dx, 0),
                          child: Transform.translate(
                            offset: Offset(_dx, 0),
                            child: Container(
                              key: _sliderKey,
                              child: GestureDetector(
                                onHorizontalDragUpdate: widget.enabled
                                    ? onHorizontalDragUpdate
                                    : null,
                                onHorizontalDragEnd: (details) async {
                                  _endDx = _dx;
                                  // If not far enough, just slide back
                                  if (_progress <= widget.trigger ||
                                      widget.onSubmit == null) {
                                    await _cancelAnimation();
                                  } else {
                                    if (widget.showSubmittedAnimation) {
                                      // 1) Shrink the bar down into a circle
                                      await _resizeAnimation(); // Makes the icon disappear
                                      await _shrinkAnimation(); // Shrinks the container
                                      // `submitted = true` is set inside _shrinkAnimation, so build() will
                                      // now show the spinner branch.
                                    }
                                    // 2) Run your callback while spinner shows
                                    await widget.onSubmit!();
                                    if (widget.showSubmittedAnimation) {
                                      // 3) Once done, reset everything back to the start
                                      await reset();
                                    }
                                  }
                                },
                                child: Padding(
                                  padding: EdgeInsets.all(
                                      widget.sliderButtonIconPadding),
                                  child: Material(
                                    borderRadius: BorderRadius.circular(
                                        widget.borderRadius),
                                    color: widget.innerColor ??
                                        Theme.of(context)
                                            .primaryIconTheme
                                            .color,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      child: Transform.rotate(
                                        angle: widget.sliderRotate
                                            ? -pi * _progress
                                            : 0,
                                        child: Center(
                                          child: widget.sliderButtonIcon ??
                                              Icon(
                                                Icons.arrow_forward,
                                                size:
                                                    widget.sliderButtonIconSize,
                                                color: widget.outerColor ??
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .secondary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    if (mounted) {
      setState(() {
        _dx = (_dx + details.delta.dx).clamp(0.0, _maxDx);
      });
    }
  }

  /// Resets the slide and all animations
  Future<void> reset() async {
    if (mounted) {
      // await _checkAnimationController.reverse(); // No longer needed
      submitted = false;
      await _shrinkAnimationController.reverse();
      await _resizeAnimationController.reverse();
      await _cancelAnimation();
    }
  }

  Future<void> _shrinkAnimation() async {
    _shrinkAnimationController.reset();

    // Guard against null _initialContainerWidth
    if (_initialContainerWidth == null) return;

    final diff = _initialContainerWidth! - widget.height;
    final animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _shrinkAnimationController,
      curve: Curves.easeOutCirc,
    ));

    animation.addListener(() {
      if (mounted) {
        setState(() {
          _containerWidth =
              _initialContainerWidth! - (diff * animation.value);
        });
      }
    });
    if (mounted) {
      setState(() {
        submitted = true;
      });
    }
    await _shrinkAnimationController.forward();
  }

  Future<void> _resizeAnimation() async {
    _resizeAnimationController.reset();
    final animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _resizeAnimationController,
      curve: Curves.easeInBack,
    ));

    animation.addListener(() {
      if (mounted) {
        setState(() {
          _dz = 1 - animation.value;
        });
      }
    });
    await _resizeAnimationController.forward();
  }

  Future<void> _cancelAnimation() async {
    _cancelAnimationController.reset();
    final animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _cancelAnimationController,
      curve: Curves.fastOutSlowIn,
    ));

    animation.addListener(() {
      if (mounted) {
        setState(() {
          _dx = (_endDx - (_endDx * animation.value));
        });
      }
    });
    await _cancelAnimationController.forward();
  }

  @override
  void dispose() {
    _cancelAnimationController.dispose();
    // _checkAnimationController.dispose(); // No longer needed
    _shrinkAnimationController.dispose();
    _resizeAnimationController.dispose();
    super.dispose();
  }
}

/// ------------------------------------------------------
/// PressToSlideCancel Widget (Press to expand -> Slide)
/// ------------------------------------------------------

class PressToSlideCancel extends StatefulWidget {
  final VoidCallback? onCancel;
  final VoidCallback? onStart;

  final double expandedHeight;
  final double collapsedHeight;
  final double expandedWidth;
  final double collapsedWidth;

  final Duration animationDuration;

  const PressToSlideCancel({
    super.key,
    this.onCancel,
    this.onStart,
    this.expandedHeight = 70,
    this.collapsedHeight = 50,
    this.expandedWidth = 300,
    this.collapsedWidth = 150,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  PressToSlideCancelState createState() => PressToSlideCancelState();
}

class PressToSlideCancelState extends State<PressToSlideCancel> {
  bool _isExpanded = false;

  Future<void> _handleSlideComplete() async {
    if (widget.onCancel != null) {
      widget.onCancel!();
    }
    if (mounted) {
      setState(() {
        _isExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    // Use a gentler spring-like curve when expanding
    final animationCurve = _isExpanded ? Curves.easeOutBack : Curves.easeInOut;

    return AnimatedContainer(
      duration: widget.animationDuration,
      curve: animationCurve,
      height: _isExpanded ? widget.expandedHeight : widget.collapsedHeight,
      width: _isExpanded ? widget.expandedWidth : widget.collapsedWidth,
      child: _isExpanded
          ? _buildExpanded(appLocalizations)
          : _buildCollapsed(appLocalizations),
    );
  }

  Widget _buildCollapsed(AppLocalizations appLocalizations) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      onPressed: () {
        if (mounted) {
          setState(() {
            _isExpanded = true;
          });
        }
        if (widget.onStart != null) {
          widget.onStart!();
        }
      },
      child: Text(appLocalizations.pressToSlideCancelStartButton),
    );
  }

  Widget _buildExpanded(AppLocalizations appLocalizations) {
    return SlideAction(
      reversed: false,
      text: appLocalizations.pressToSlideCancelSlideToCancel,
      onSubmit: () async {
        await _handleSlideComplete();
      },
      outerColor: Colors.redAccent,
      innerColor: Colors.white,
      textColor: Colors.white,
      sliderRotate: true, // Explicitly enable rotation for the arrow
      sliderButtonIcon: const Icon(
        Icons.arrow_forward,
        color: Colors.redAccent,
      ),
    );
  }
}

