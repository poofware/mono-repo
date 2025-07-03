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

  const DateCarousel({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.availableDates,
    this.isDayEnabled,
  });

  @override
  State<DateCarousel> createState() => _DateCarouselState();
}

class _DateCarouselState extends State<DateCarousel> {
  late final ScrollController _scrollController;

  static const double _cardWidth = 80.0;
  static const double _cardSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Scroll to the selected day if it's in the date list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedDay(widget.selectedDate, animate: false);
    });
  }

  @override
  void dispose() {
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

    offset = offset - (screenWidth / 2) + (_cardWidth / 2);

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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
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
