import 'package:flutter/material.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

enum TimeUnit { days, hours, minutes }

class DurationPickerFormField extends FormField<Duration> {
  DurationPickerFormField({
    super.key,
    Duration? initialValue,
    super.onSaved,
    super.validator,
    ValueChanged<Duration>? onChanged, // Added for real-time updates
    super.enabled,
  }) : super(
          initialValue: initialValue ?? const Duration(hours: 1),
          builder: (field) {
            final state = field as DurationPickerFormFieldState;
            state._onChanged = onChanged; // Pass callback to state
            final appLocalizations = AppLocalizations.of(field.context); // Get localizations here
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: TextFormField(
                        controller: state._textController,
                        keyboardType: TextInputType.number,
                        onChanged: state._handleValueChanged,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '',
                        ),
                        enabled: enabled,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<TimeUnit>(
                      value: state._timeUnit,
                      items: [
                        DropdownMenuItem(value: TimeUnit.days, child: Text(appLocalizations.timeUnitDays)),
                        DropdownMenuItem(value: TimeUnit.hours, child: Text(appLocalizations.timeUnitHours)),
                        DropdownMenuItem(value: TimeUnit.minutes, child: Text(appLocalizations.timeUnitMinutes)),
                      ],
                      onChanged: enabled ? state._handleUnitChanged : null,
                    ),
                  ],
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      field.errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            );
          },
        );


  @override
  DurationPickerFormFieldState createState() => DurationPickerFormFieldState();
}

class DurationPickerFormFieldState extends FormFieldState<Duration> {
  final _textController = TextEditingController();
  TimeUnit _timeUnit = TimeUnit.hours;
  ValueChanged<Duration>? _onChanged;

  @override
  void initState() {
    super.initState();
    _initFromInitialValue();
  }

  void _initFromInitialValue() {
    final d = widget.initialValue ?? const Duration(hours: 1);
    if (d.inDays >= 1 && d.inHours % 24 == 0) {
      _timeUnit = TimeUnit.days;
      _textController.text = '${d.inDays}';
    } else if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
      _timeUnit = TimeUnit.hours;
      _textController.text = '${d.inHours}';
    } else {
      _timeUnit = TimeUnit.minutes;
      _textController.text = '${d.inMinutes}';
    }
  }

  void _handleValueChanged(String val) {
    final duration = _computeDuration(val);
    didChange(duration);
    _onChanged?.call(duration); // Notify parent of change
  }

  void _handleUnitChanged(TimeUnit? unit) {
    if (unit == null) return;
    setState(() => _timeUnit = unit);
    final duration = _computeDuration(_textController.text);
    didChange(duration);
    _onChanged?.call(duration); // Notify parent of change
  }

  Duration _computeDuration(String val) {
    final parsed = int.tryParse(val) ?? 0;
    switch (_timeUnit) {
      case TimeUnit.days:
        return Duration(days: parsed);
      case TimeUnit.hours:
        return Duration(hours: parsed);
      case TimeUnit.minutes:
        return Duration(minutes: parsed);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

