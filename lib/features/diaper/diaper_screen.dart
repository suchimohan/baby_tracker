import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../providers/log_providers.dart';
import '../widgets/common.dart';
import '../widgets/quick_time_picker.dart';

void _showEdit(
  BuildContext context,
  DiaperLogsNotifier notifier,
  DiaperLog log,
) {
  var type = log.diaperType;
  var time = log.changedAt;
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
                    'Edit diaper change',
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in DiaperType.values)
                  ChoiceChip(
                    avatar: Text(t.emoji),
                    label: Text(t.label),
                    selected: type == t,
                    onSelected: (_) => setState(() => type = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            QuickTimePicker(
              label: 'Time',
              value: time,
              onChanged: (v) => setState(() => time = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                notifier.update(log, type: type, at: time);
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

class DiaperScreen extends ConsumerWidget {
  const DiaperScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(diaperLogsProvider);
    final notifier = ref.read(diaperLogsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Quick-tap grid: one tap logs "now" (REQUIREMENTS v1).
        // Styled like the Sleep/Feeding timer cards: colored container,
        // bottom-nav icon on top, actions below.
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.baby_changing_station,
                  size: 44,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final type in DiaperType.values)
                      FilledButton.icon(
                        icon: Text(type.emoji),
                        label: Text(type.label),
                        onPressed: () {
                          notifier.add(type);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${type.emoji} ${type.label} diaper logged',
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No changes logged yet')),
          ),
        ...groupedByDay(
          context: context,
          items: logs,
          dateOf: (log) => log.changedAt,
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
              leading: Text(
                log.diaperType.emoji,
                style: const TextStyle(fontSize: 22),
              ),
              title: Text(log.diaperType.label),
              subtitle: Text(DateFormat.jm().format(log.changedAt)),
              trailing: SyncDot(log.syncState),
              onTap: () => _showEdit(context, notifier, log),
            ),
          ),
        ),
      ],
    );
  }
}
