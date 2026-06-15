import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../providers/log_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/common.dart';
import '../widgets/quick_time_picker.dart';

/// Digits + at most one decimal point ("abcd" can't be typed).
final _decimalOnly = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        '.'.allMatches(newValue.text).length > 1 ? oldValue : newValue,
  ),
];

class FeedingScreen extends ConsumerWidget {
  const FeedingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(feedingLogsProvider);
    final notifier = ref.read(feedingLogsProvider.notifier);
    final unit = ref.watch(volumeUnitProvider);
    final running = logs.where((l) => l.inProgress).firstOrNull;
    final finished = logs.where((l) => !l.inProgress).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _FeedingTimerCard(running: running),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Add past feeding'),
          onPressed: () => _showManualEntry(context, ref),
        ),
        const SizedBox(height: 8),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        if (finished.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No feedings logged yet')),
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
              leading: Text(
                log.feedingType.emoji,
                style: const TextStyle(fontSize: 22),
              ),
              title: Text(_title(log, unit)),
              subtitle: Text(
                DateFormat.jm().format(log.startedAt) +
                    (log.feedingType != FeedingType.solids &&
                            log.duration.inMinutes > 0
                        ? ' · ${formatDuration(log.duration)}'
                        : ''),
              ),
              trailing: SyncDot(log.syncState),
              onTap: () => _showEditEntry(context, ref, log),
            ),
          ),
        ),
      ],
    );
  }

  String _title(FeedingLog log, VolumeUnit unit) => switch (log.feedingType) {
    FeedingType.bottle =>
      'Bottle${log.amountMl != null ? ' · ${formatVolume(log.amountMl!, unit)}' : ''}',
    FeedingType.breast => 'Breast',
    FeedingType.solids =>
      log.foods?.isNotEmpty == true ? log.foods!.join(', ') : 'Solids',
  };

  void _showEditEntry(BuildContext context, WidgetRef ref, FeedingLog log) {
    final notifier = ref.read(feedingLogsProvider.notifier);
    var type = log.feedingType;
    var time = log.startedAt;
    var unit = ref.read(volumeUnitProvider);
    final selectedFoods = <String>{...?log.foods};
    final amountController = TextEditingController(
      text: log.amountMl != null
          ? (unit == VolumeUnit.oz
                ? (log.amountMl! / 29.5735).toStringAsFixed(1)
                : log.amountMl!.round().toString())
          : '',
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.88,
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Edit feeding',
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<FeedingType>(
                              segments: [
                                for (final t in FeedingType.values)
                                  ButtonSegment(
                                    value: t,
                                    label: Text(t.label),
                                    icon: Text(t.emoji),
                                  ),
                              ],
                              selected: {type},
                              onSelectionChanged: (s) =>
                                  setState(() => type = s.first),
                            ),
                            const SizedBox(height: 16),
                            QuickTimePicker(
                              label: 'Time',
                              value: time,
                              onChanged: (v) => setState(() => time = v),
                            ),
                            if (type == FeedingType.bottle) ...[
                              const SizedBox(height: 16),
                              AmountField(
                                controller: amountController,
                                unit: unit,
                                onUnitChanged: (u) {
                                  setState(() => unit = u);
                                  ref.read(volumeUnitProvider.notifier).set(u);
                                },
                              ),
                            ],
                            if (type == FeedingType.solids) ...[
                              const SizedBox(height: 16),
                              FoodPicker(
                                selected: selectedFoods,
                                onChanged: () => setState(() {}),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (type == FeedingType.solids &&
                                  selectedFoods.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pick at least one food'),
                                  ),
                                );
                                return;
                              }
                              notifier.update(
                                log,
                                type: type,
                                start: time,
                                amountMl: type == FeedingType.bottle
                                    ? parseVolumeToMl(
                                        amountController.text,
                                        unit,
                                      )
                                    : null,
                                foods: type == FeedingType.solids
                                    ? selectedFoods.toList()
                                    : null,
                              );
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showManualEntry(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(feedingLogsProvider.notifier);
    var type = FeedingType.bottle;
    var time = DateTime.now();
    var unit = ref.read(volumeUnitProvider);
    final selectedFoods = <String>{};
    final amountController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.88,
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Add feeding',
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<FeedingType>(
                              segments: [
                                for (final t in FeedingType.values)
                                  ButtonSegment(
                                    value: t,
                                    label: Text(t.label),
                                    icon: Text(t.emoji),
                                  ),
                              ],
                              selected: {type},
                              onSelectionChanged: (s) =>
                                  setState(() => type = s.first),
                            ),
                            const SizedBox(height: 16),
                            QuickTimePicker(
                              label: 'Time',
                              value: time,
                              onChanged: (v) => setState(() => time = v),
                            ),
                            if (type == FeedingType.bottle) ...[
                              const SizedBox(height: 16),
                              AmountField(
                                controller: amountController,
                                unit: unit,
                                onUnitChanged: (u) {
                                  setState(() => unit = u);
                                  ref.read(volumeUnitProvider.notifier).set(u);
                                },
                              ),
                            ],
                            if (type == FeedingType.solids) ...[
                              const SizedBox(height: 16),
                              FoodPicker(
                                selected: selectedFoods,
                                onChanged: () => setState(() {}),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (type == FeedingType.solids &&
                                  selectedFoods.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pick at least one food'),
                                  ),
                                );
                                return;
                              }
                              notifier.addManual(
                                type: type,
                                start: time,
                                amountMl: type == FeedingType.bottle
                                    ? parseVolumeToMl(
                                        amountController.text,
                                        unit,
                                      )
                                    : null,
                                foods: type == FeedingType.solids
                                    ? selectedFoods.toList()
                                    : null,
                              );
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('Save meal'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-select food picker:
///  - search box that doubles as "add your own" when there's no match
///  - Frequent section computed from this child's past meals
///  - categorized catalog + custom "Your foods" section
///  - long-press a chip to remove it (blocked if it appears in past meals)
class FoodPicker extends ConsumerStatefulWidget {
  const FoodPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  ConsumerState<FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends ConsumerState<FoodPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customFoods = ref.watch(customFoodsProvider);
    final removed = ref.watch(removedFoodsProvider);
    final logs = ref.watch(feedingLogsProvider);

    // Frequency from this child's actual meals (most-used first).
    final counts = <String, int>{};
    for (final log in logs) {
      for (final food in log.foods ?? const <String>[]) {
        counts[food] = (counts[food] ?? 0) + 1;
      }
    }
    final frequent = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final frequentTop = frequent.take(8).toList();

    bool visible(String f) => !removed.contains(f);
    final sections = <(String, List<String>)>[
      if (frequentTop.isNotEmpty) ('Frequent', frequentTop),
      if (customFoods.where(visible).isNotEmpty)
        ('Your foods', customFoods.where(visible).toList()),
      for (final entry in foodCatalog.entries)
        (entry.key, entry.value.where(visible).toList()),
    ];

    final allFoods = <String>{
      ...customFoods,
      for (final foods in foodCatalog.values) ...foods,
    }.where(visible).toList();

    final searching = _query.trim().isNotEmpty;
    final matches = searching
        ? allFoods
              .where(
                (f) => f.toLowerCase().contains(_query.trim().toLowerCase()),
              )
              .toList()
        : const <String>[];
    final hasExactMatch = allFoods.any(
      (f) => f.toLowerCase() == _query.trim().toLowerCase(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What did they eat?',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Search or add a food',
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searching
                ? (hasExactMatch
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        )
                      : TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                          onPressed: _addCustom,
                        ))
                : null,
            helperText: 'Long-press a food to remove it from the list',
          ),
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (_) {
            if (searching && !hasExactMatch) _addCustom();
          },
        ),
        const SizedBox(height: 8),
        if (searching) ...[
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'No match — tap Add to create "${_query.trim()}"',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          _chips(matches, counts),
        ] else
          for (final (title, foods) in sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            _chips(foods, counts),
          ],
      ],
    );
  }

  Widget _chips(List<String> foods, Map<String, int> counts) => Wrap(
    spacing: 6,
    runSpacing: 0,
    children:
        [
          for (final food in foods)
            FilterChip(
              label: Text(food),
              selected: widget.selected.contains(food),
              visualDensity: VisualDensity.compact,
              onSelected: (on) {
                on ? widget.selected.add(food) : widget.selected.remove(food);
                widget.onChanged();
              },
              // Long-press to remove (only if never eaten).
              tooltip: 'Long-press to remove',
            ),
        ].map((chip) {
          final food = (chip.label as Text).data!;
          return GestureDetector(
            onLongPress: () => _tryRemove(food, counts),
            child: chip,
          );
        }).toList(),
  );

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _addCustom() {
    final name = _searchController.text.trim();
    if (name.isEmpty) return;
    ref.read(customFoodsProvider.notifier).add(name);
    widget.selected.add(name);
    _clearSearch();
    widget.onChanged();
  }

  Future<void> _tryRemove(String food, Map<String, int> counts) async {
    final messenger = ScaffoldMessenger.of(context);
    if ((counts[food] ?? 0) > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '"$food" can\'t be removed — it appears in past meals. '
            'Foods with logged history stay on the list.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "$food"?'),
        content: const Text('It will no longer appear in the food list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final customs = ref.read(customFoodsProvider);
    if (customs.contains(food)) {
      await ref.read(customFoodsProvider.notifier).remove(food);
    } else {
      await ref.read(removedFoodsProvider.notifier).add(food);
    }
    widget.selected.remove(food);
    widget.onChanged();
  }
}

/// Numeric amount input with an ml/oz unit toggle that persists the choice.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final VolumeUnit unit;
  final ValueChanged<VolumeUnit> onUnitChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _decimalOnly,
            decoration: InputDecoration(
              labelText: 'Amount',
              suffixText: unit.name,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<VolumeUnit>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(value: VolumeUnit.oz, label: Text('oz')),
            ButtonSegment(value: VolumeUnit.ml, label: Text('ml')),
          ],
          selected: {unit},
          onSelectionChanged: (s) => onUnitChanged(s.first),
        ),
      ],
    );
  }
}

class _FeedingTimerCard extends ConsumerWidget {
  const _FeedingTimerCard({required this.running});

  final FeedingLog? running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(feedingLogsProvider.notifier);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (running != null) ...[
              Text(
                running!.feedingType.emoji,
                style: const TextStyle(fontSize: 44),
              ),
              ElapsedText(
                since: running!.startedAt,
                style: theme.textTheme.displaySmall,
              ),
              Text(
                '${running!.feedingType == FeedingType.bottle ? 'Bottle' : 'Nursing'} '
                'since ${DateFormat.jm().format(running!.startedAt)}',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('End feeding'),
                onPressed: () => _stop(context, ref, notifier),
              ),
            ] else ...[
              // Same icon as the Feeding tab in the bottom nav — consistent.
              Icon(
                Icons.restaurant,
                size: 44,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final (type, onTap) in [
                    (
                      FeedingType.bottle,
                      () => notifier.startTimer(FeedingType.bottle),
                    ),
                    (
                      FeedingType.breast,
                      () => notifier.startTimer(FeedingType.breast),
                    ),
                    (FeedingType.solids, () => _logSolids(context, ref)),
                  ])
                    FilledButton.icon(
                      icon: Text(type.emoji),
                      label: Text(type.label),
                      onPressed: onTap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Solids is an instant log (no timer): pick foods + time, save.
  void _logSolids(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(feedingLogsProvider.notifier);
    final selectedFoods = <String>{};
    var time = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.88,
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Solids meal',
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            QuickTimePicker(
                              label: 'Time',
                              value: time,
                              onChanged: (v) => setState(() => time = v),
                            ),
                            const SizedBox(height: 16),
                            FoodPicker(
                              selected: selectedFoods,
                              onChanged: () => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (selectedFoods.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pick at least one food'),
                                  ),
                                );
                                return;
                              }
                              notifier.addManual(
                                type: FeedingType.solids,
                                start: time,
                                foods: selectedFoods.toList(),
                              );
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('Save meal'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _stop(
    BuildContext context,
    WidgetRef ref,
    FeedingLogsNotifier notifier,
  ) {
    if (running!.feedingType != FeedingType.bottle) {
      notifier.stopTimer(running!);
      return;
    }
    var unit = ref.read(volumeUnitProvider);
    final amountController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('How much?'),
          content: AmountField(
            controller: amountController,
            unit: unit,
            autofocus: true,
            onUnitChanged: (u) {
              setState(() => unit = u);
              ref.read(volumeUnitProvider.notifier).set(u);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                notifier.stopTimer(running!);
                Navigator.pop(dialogContext);
              },
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () {
                notifier.stopTimer(
                  running!,
                  amountMl: parseVolumeToMl(amountController.text, unit),
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
