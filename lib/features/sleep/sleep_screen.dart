import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../providers/log_providers.dart';
import '../widgets/common.dart';
import '../widgets/quick_time_picker.dart';

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(sleepLogsProvider);
    final notifier = ref.read(sleepLogsProvider.notifier);
    final running = logs.where((l) => l.inProgress).firstOrNull;
    final finished = logs.where((l) => !l.inProgress).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TimerCard(running: running, notifier: notifier),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Add past sleep'),
          onPressed: () => _showManualEntry(context, notifier),
        ),
        const SizedBox(height: 8),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        if (finished.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No sleep logged yet')),
          ),
        ...groupedByDay(
          context: context,
          items: finished,
          dateOf: (log) => log.startedAt,
          rowBuilder: (log) => Dismissible(
            key: ValueKey(log.clientId),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => notifier.remove(log),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bedtime),
              title: Text(
                '${DateFormat.jm().format(log.startedAt)} – '
                '${DateFormat.jm().format(log.endedAt!)}',
              ),
              subtitle: Text(
                formatDuration(log.duration) +
                    (log.note?.isNotEmpty == true ? ' · ${log.note}' : ''),
              ),
              trailing: SyncDot(log.syncState),
              onTap: () => _showEditEntry(context, notifier, log),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditEntry(
    BuildContext context,
    SleepLogsNotifier notifier,
    SleepLog log,
  ) {
    var start = log.startedAt;
    var end = log.endedAt!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit sleep',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              QuickTimePicker(
                label: 'Fell asleep',
                value: start,
                onChanged: (v) => setState(() => start = v),
              ),
              const SizedBox(height: 12),
              QuickTimePicker(
                label: 'Woke up',
                value: end,
                onChanged: (v) => setState(() => end = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (!end.isAfter(start)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Wake time must be after sleep time')));
                    return;
                  }
                  notifier.update(log, start: start, end: end);
                  Navigator.pop(sheetContext);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualEntry(BuildContext context, SleepLogsNotifier notifier) {
    var start = DateTime.now().subtract(const Duration(hours: 1));
    var end = DateTime.now();
    var stillSleeping = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add sleep', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              QuickTimePicker(
                label: 'Fell asleep',
                value: start,
                onChanged: (v) => setState(() => start = v),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Still sleeping'),
                subtitle: const Text('Starts the timer from that time'),
                value: stillSleeping,
                onChanged: (v) => setState(() => stillSleeping = v),
              ),
              if (!stillSleeping) ...[
                const SizedBox(height: 4),
                QuickTimePicker(
                  label: 'Woke up',
                  value: end,
                  onChanged: (v) => setState(() => end = v),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (stillSleeping) {
                    if (start.isAfter(DateTime.now())) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Start time is in the future')));
                      return;
                    }
                    notifier.startTimer(at: start);
                  } else {
                    if (!end.isAfter(start)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Wake time must be after sleep time')));
                      return;
                    }
                    notifier.addManual(start: start, end: end);
                  }
                  Navigator.pop(sheetContext);
                },
                child: Text(stillSleeping ? 'Start timer' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.running, required this.notifier});

  final SleepLog? running;
  final SleepLogsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              running != null ? Icons.bedtime : Icons.bedtime_outlined,
              size: 48,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 8),
            if (running != null) ...[
              ElapsedText(
                since: running!.startedAt,
                style: theme.textTheme.displaySmall,
              ),
              // Tappable: adjust the start retroactively while running.
              ActionChip(
                avatar: const Icon(Icons.edit, size: 16),
                label: Text(
                    'Sleeping since ${DateFormat.jm().format(running!.startedAt)}'),
                onPressed: () => _editStart(context),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('End sleep'),
                onPressed: () => notifier.stopTimer(running!),
              ),
            ] else ...[
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start sleep'),
                onPressed: () => notifier.startTimer(),
              ),
              TextButton(
                onPressed: () => _startEarlier(context),
                child: const Text('Fell asleep earlier…'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startEarlier(BuildContext context) {
    var start = DateTime.now().subtract(const Duration(minutes: 15));
    _timeSheet(
      context,
      title: 'When did sleep start?',
      initial: start,
      confirmLabel: 'Start timer',
      onConfirm: (v) => notifier.startTimer(at: v),
    );
  }

  void _editStart(BuildContext context) {
    _timeSheet(
      context,
      title: 'Adjust start time',
      initial: running!.startedAt,
      confirmLabel: 'Update',
      onConfirm: (v) => notifier.updateStart(running!, v),
    );
  }

  void _timeSheet(
    BuildContext context, {
    required String title,
    required DateTime initial,
    required String confirmLabel,
    required ValueChanged<DateTime> onConfirm,
  }) {
    var value = initial;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              QuickTimePicker(
                label: 'Fell asleep',
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (value.isAfter(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Start time is in the future')));
                    return;
                  }
                  onConfirm(value);
                  Navigator.pop(sheetContext);
                },
                child: Text(confirmLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
