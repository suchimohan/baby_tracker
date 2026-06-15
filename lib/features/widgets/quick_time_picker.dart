import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Hybrid time picker designed for one-handed 3am use.
///
/// Shows a date chip ("Today" / "Mon Jun 8") and a time chip side by side.
/// Quick-offset chips (Now / -5 / -15 / -30) always resolve to the current
/// wall-clock time and reset the date to today.
class QuickTimePicker extends StatelessWidget {
  const QuickTimePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  bool get _isToday {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const Spacer(),
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                _isToday ? 'Today' : DateFormat('EEE, MMM d').format(value),
              ),
              onPressed: () => _pickDate(context),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.schedule, size: 16),
              label: Text(DateFormat.jm().format(value)),
              onPressed: () => _pickTime(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _chip(context, 'Now', () => onChanged(DateTime.now())),
            for (final mins in const [5, 15, 30])
              _chip(
                context,
                '-$mins min',
                () => onChanged(
                  DateTime.now().subtract(Duration(minutes: mins)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String text, VoidCallback onTap) =>
      ActionChip(label: Text(text), onPressed: onTap);

  Future<void> _pickDate(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: today.subtract(const Duration(days: 365 * 2)),
      lastDate: today,
    );
    if (picked == null) return;
    onChanged(
      DateTime(picked.year, picked.month, picked.day, value.hour, value.minute),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null) return;
    var picked = DateTime(
      value.year, value.month, value.day, time.hour, time.minute,
    );
    // On today only: a selected future time means "yesterday" (e.g. logging
    // a midnight feed at 12:30 AM).
    if (_isToday && picked.isAfter(DateTime.now())) {
      picked = picked.subtract(const Duration(days: 1));
    }
    onChanged(picked);
  }
}
