// worker-app/lib/features/jobs/presentation/widgets/job_carousel_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/core/theme/app_colors.dart';

/// Compare only date (ignoring time).
bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// A horizontal list of days. We highlight the selected day,
/// and optionally disable days that are not valid for acceptance.
/// The list of dates to display is provided by the parent widget.
class DateCarousel extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final List<DateTime> availableDates;

  /// If provided, only days for which `isDayEnabled(day)==true` can be tapped.
  final bool Function(DateTime)? isDayEnabled;

  /// Optional left padding to offset the first card from the edge.
  /// Defaults to 0 so other screens can choose their own spacing.
  final double leftPadding;

  const DateCarousel({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.availableDates,
    this.isDayEnabled,
    this.leftPadding = 0.0,
  });

  @override
  State<DateCarousel> createState() => _DateCarouselState();
}

class _DateCarouselState extends State<DateCarousel> {
  late final ScrollController _scrollController;
  bool _isScrolling = false;
  VoidCallback? _scrollingListener;

  static const double _cardWidth = 80.0;
  static const double _cardSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Bind notifier and then perform initial scroll in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindScrollNotifier();
      _scrollToSelectedDay(widget.selectedDate, animate: false);
    });
  }

  @override
  void dispose() {
    if (_scrollingListener != null && _scrollController.hasClients) {
      _scrollController.position.isScrollingNotifier
          .removeListener(_scrollingListener!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DateCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDate(oldWidget.selectedDate, widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedDay(widget.selectedDate, animate: true);
      });
    }
  }

  void _scrollToSelectedDay(DateTime day, {bool animate = true}) {
    if (!_scrollController.hasClients) return;

    final idx = widget.availableDates.indexWhere((d) => _isSameDate(d, day));
    if (idx == -1) return; // not in range

    final itemWidth = _cardWidth + _cardSpacing;
    double offset = idx * itemWidth;
    final screenWidth = MediaQuery.of(context).size.width;

    // Center the selected card within the visible content width, accounting for left padding
    final visibleWidth = screenWidth - widget.leftPadding;
    offset = offset - (visibleWidth / 2) + (_cardWidth / 2);

    if (offset < 0) offset = 0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (offset > maxScroll) offset = maxScroll;

    if (animate) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(offset);
    }
  }

  void _bindScrollNotifier() {
    if (!_scrollController.hasClients) return;
    if (_scrollingListener != null) {
      _scrollController.position.isScrollingNotifier
          .removeListener(_scrollingListener!);
    }
    _scrollingListener = () {
      final current = _scrollController.position.isScrollingNotifier.value;
      // Defer state change to post-frame to avoid mid-layout builds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isScrolling = current);
      });
    };
    _scrollController.position.isScrollingNotifier
        .addListener(_scrollingListener!);
    _isScrolling = _scrollController.position.isScrollingNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(left: widget.leftPadding),
            itemCount: widget.availableDates.length,
            itemBuilder: (context, index) {
              final day = widget.availableDates[index];
              final isSelected = _isSameDate(day, widget.selectedDate);
              final isEnabled = widget.isDayEnabled?.call(day) ?? true;
              return Padding(
                padding: const EdgeInsets.only(right: _cardSpacing),
                child: _buildDayCard(day, isSelected, isEnabled),
              );
            },
          ),
          // Tap overlay to allow selecting a card even during inertial scroll
          Builder(
            builder: (context) {
              if (!_scrollController.hasClients) {
                return const SizedBox.shrink();
              }
              return IgnorePointer(
                ignoring: !_isScrolling,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    if (!_scrollController.hasClients) return;
                    // Stop the ongoing ballistic scroll for a crisp selection
                    try {
                      _scrollController.jumpTo(_scrollController.offset);
                    } catch (_) {}

                    final tapX = details.localPosition.dx;
                    final absoluteX = _scrollController.offset + tapX - widget.leftPadding;
                    final double itemWidth = _cardWidth + _cardSpacing;
                    int tappedIndex = (absoluteX / itemWidth).floor();
                    tappedIndex = tappedIndex.clamp(0, widget.availableDates.length - 1);
                    final tappedDay = widget.availableDates[tappedIndex];
                    final isEnabled = widget.isDayEnabled?.call(tappedDay) ?? true;
                    if (!isEnabled) return;
                    widget.onDateSelected(tappedDay);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(DateTime day, bool isSelected, bool isEnabled) {
    final theme = Theme.of(context);
    final dayName = DateFormat('EEE').format(day);
    final dateStr = DateFormat('d MMM').format(day);
    final defaultTextColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
    final selectedTextColor = Colors.white;
    final disabledColor = Colors.grey.shade400;

    final cardBackground = isSelected ? AppColors.poofColor : theme.cardColor;

    final textColor = !isEnabled
        ? disabledColor
        : (isSelected ? selectedTextColor : defaultTextColor);

    return GestureDetector(
      onTap: () {
        if (!isEnabled) return;
        widget.onDateSelected(day);
      },
      child: Card(
        color: cardBackground,
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: _cardWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isEnabled ? textColor : disabledColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 14,
                  color: isEnabled ? textColor : disabledColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
