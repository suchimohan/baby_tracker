import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../providers/auth_providers.dart';
import '../../providers/child_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/log_providers.dart';
import '../../providers/settings_providers.dart';
import '../auth/create_child_screen.dart';
import '../diaper/diaper_screen.dart';
import '../feeding/feeding_screen.dart';
import '../sleep/sleep_screen.dart';
import '../widgets/common.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  static const _titles = ['Today', 'Sleep', 'Feeding', 'Diapers'];

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final children = ref.watch(childrenProvider).value ?? const <Child>[];
    return Scaffold(
      appBar: AppBar(
        // Child switcher: works for any number of kids; "Add child…" lives here.
        title: child == null
            ? Text(_titles[_tab])
            : PopupMenuButton<Object>(
                tooltip: 'Switch child',
                onSelected: (v) async {
                  if (v is Child) {
                    await ref.read(selectedChildProvider.notifier).select(v);
                  } else if (v == 'add') {
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateChildScreen(),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  for (final c in children)
                    PopupMenuItem<Object>(
                      value: c,
                      child: Row(
                        children: [
                          Icon(
                            c.id == child.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text('${c.name} · ${c.ageLabel}'),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<Object>(
                    value: 'add',
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt, size: 18),
                        SizedBox(width: 8),
                        Text('Add child…'),
                      ],
                    ),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${child.name} · ${child.ageLabel}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
        actions: [
          const SyncBadge(),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'invite') _showInviteDialog(context);
              if (v == 'delete_child') await _showDeleteChildDialog(context);
              if (v == 'signout') {
                await ref.read(authControllerProvider).signOut();
                await ref.read(demoModeProvider.notifier).disable();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'invite',
                child: Text('Invite caregiver'),
              ),
              if (child != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete_child',
                  child: Text(
                    'Delete current child…',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: switch (_tab) {
        1 => const SleepScreen(),
        2 => const FeedingScreen(),
        3 => const DiaperScreen(),
        _ => _DashboardTab(onNavigate: (i) => setState(() => _tab = i)),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined),
            label: 'Sleep',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            label: 'Feeding',
          ),
          NavigationDestination(
            icon: Icon(Icons.baby_changing_station),
            label: 'Diapers',
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteChildDialog(BuildContext context) async {
    final child = ref.read(selectedChildProvider);
    if (child == null) return;

    final deletedName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteChildDialog(
        child: child,
        sleepCount: ref.read(sleepLogsProvider).length,
        feedingCount: ref.read(feedingLogsProvider).length,
        diaperCount: ref.read(diaperLogsProvider).length,
      ),
    );
    if (deletedName != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted $deletedName.')));
    }
  }

  void _showInviteDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite caregiver'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Their email',
            helperText: 'They get read+write access to all tracking data.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final child = ref.read(selectedChildProvider);
              if (child == null) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext);
              try {
                await ref
                    .read(childRepositoryProvider)
                    .invite(childId: child.id, email: controller.text);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Invite created — valid for 7 days'),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Invite failed: $e')),
                );
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }
}

class _DeleteChildDialog extends ConsumerStatefulWidget {
  const _DeleteChildDialog({
    required this.child,
    required this.sleepCount,
    required this.feedingCount,
    required this.diaperCount,
  });

  final Child child;
  final int sleepCount;
  final int feedingCount;
  final int diaperCount;

  @override
  ConsumerState<_DeleteChildDialog> createState() => _DeleteChildDialogState();
}

class _DeleteChildDialogState extends ConsumerState<_DeleteChildDialog> {
  late final TextEditingController _controller;
  late final String _confirmationText;
  bool _understood = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _confirmationText = 'DELETE ${widget.child.name}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDelete =
        !_busy && _understood && _controller.text.trim() == _confirmationText;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: const Text('Permanently delete child?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will delete ${widget.child.name} and all associated '
              'sleep, feeding, and diaper records.',
            ),
            const SizedBox(height: 12),
            Text(
              'Current local records: ${widget.sleepCount} sleep, '
              '${widget.feedingCount} feeding, ${widget.diaperCount} diaper.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'This cannot be undone.',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _understood,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _understood = value ?? false),
              title: const Text(
                'I understand this permanently deletes this child.',
              ),
            ),
            const SizedBox(height: 8),
            Text('Type exactly: $_confirmationText'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Confirmation',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: canDelete ? _deleteChild : null,
          child: Text(_busy ? 'Deleting…' : 'Delete permanently'),
        ),
      ],
    );
  }

  Future<void> _deleteChild() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(childrenProvider.notifier).deleteChild(widget.child);
      if (mounted) Navigator.pop(context, widget.child.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Delete failed: $e';
      });
    }
  }
}

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  /// 0 = today, 1 = yesterday, … — paged with the arrows in the header.
  int _daysBack = 0;

  ValueChanged<int> get onNavigate => widget.onNavigate;

  @override
  Widget build(BuildContext context) {
    final sleepLogs = ref.watch(sleepLogsProvider);
    final feedingLogs = ref.watch(feedingLogsProvider);
    final diaperLogs = ref.watch(diaperLogsProvider);

    final now = DateTime.now();
    final dayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: _daysBack));
    final dayEnd = dayStart.add(const Duration(days: 1));
    final isToday = _daysBack == 0;
    bool inDay(DateTime t) => !t.isBefore(dayStart) && t.isBefore(dayEnd);

    final unit = ref.watch(volumeUnitProvider);
    final sleepingNow = sleepLogs.where((l) => l.inProgress).firstOrNull;
    final feedingNow = feedingLogs.where((l) => l.inProgress).firstOrNull;

    // Merged chronological timeline of the selected day (newest first).
    final timeline = <_TimelineEvent>[
      for (final l in sleepLogs.where(
        (l) => !l.inProgress && inDay(l.endedAt!),
      ))
        _TimelineEvent(
          time: l.endedAt!,
          emoji: '🌙',
          title: 'Slept ${formatDuration(l.duration)}',
          detail:
              '${DateFormat.jm().format(l.startedAt)} – ${DateFormat.jm().format(l.endedAt!)}',
          tab: 1,
        ),
      for (final l in feedingLogs.where(
        (l) => !l.inProgress && inDay(l.startedAt),
      ))
        _TimelineEvent(
          time: l.startedAt,
          emoji: l.feedingType.emoji,
          title: switch (l.feedingType) {
            FeedingType.bottle =>
              'Bottle${l.amountMl != null ? ' · ${formatVolume(l.amountMl!, unit)}' : ''}',
            FeedingType.breast => 'Breastfed ${formatDuration(l.duration)}',
            FeedingType.solids =>
              l.foods?.isNotEmpty == true ? l.foods!.join(', ') : 'Solids',
          },
          tab: 2,
        ),
      for (final l in diaperLogs.where((l) => inDay(l.changedAt)))
        _TimelineEvent(
          time: l.changedAt,
          emoji: l.diaperType.emoji,
          title: '${l.diaperType.label} diaper',
          tab: 3,
        ),
    ]..sort((a, b) => b.time.compareTo(a.time));

    // Day stats (filtered to the viewed day).
    final todaySleep = sleepLogs
        .where((l) => !l.inProgress && inDay(l.endedAt!))
        .fold(Duration.zero, (sum, l) => sum + l.duration);
    final dayFeedings =
        feedingLogs.where((l) => !l.inProgress && inDay(l.startedAt)).toList();
    final bottleFeedings =
        dayFeedings.where((l) => l.feedingType == FeedingType.bottle).toList();
    final breastCount =
        dayFeedings.where((l) => l.feedingType == FeedingType.breast).length;
    final solidsCount =
        dayFeedings.where((l) => l.feedingType == FeedingType.solids).length;
    final bottleTotalMl =
        bottleFeedings.fold(0.0, (sum, l) => sum + (l.amountMl ?? 0));
    final diaperCounts = <DiaperType, int>{};
    for (final l in diaperLogs.where((l) => inDay(l.changedAt))) {
      diaperCounts[l.diaperType] = (diaperCounts[l.diaperType] ?? 0) + 1;
    }

    // Last-event times from full history (not filtered by day).
    final lastSleepTime =
        sleepLogs.where((l) => !l.inProgress).firstOrNull?.endedAt;
    final lastBottleTime = feedingLogs
        .where(
          (l) => !l.inProgress && l.feedingType == FeedingType.bottle,
        )
        .firstOrNull
        ?.startedAt;
    final lastBreastTime = feedingLogs
        .where(
          (l) => !l.inProgress && l.feedingType == FeedingType.breast,
        )
        .firstOrNull
        ?.startedAt;
    final lastSolidsTime = feedingLogs
        .where(
          (l) => !l.inProgress && l.feedingType == FeedingType.solids,
        )
        .firstOrNull
        ?.startedAt;
    final lastDiaperTime = diaperLogs.firstOrNull?.changedAt;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isToday && sleepingNow != null)
          _LiveBanner(
            icon: Icons.bedtime,
            text: 'Sleeping',
            since: sleepingNow.startedAt,
            onTap: () => onNavigate(1),
          ),
        if (isToday && feedingNow != null)
          _LiveBanner(
            icon: Icons.restaurant,
            text: feedingNow.feedingType == FeedingType.bottle
                ? 'Bottle feeding'
                : 'Nursing',
            since: feedingNow.startedAt,
            onTap: () => onNavigate(2),
          ),
        // Day pager: ◀ Today / Yesterday / Mon, Jun 8 ▶
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _daysBack++),
            ),
            Expanded(
              // Tap the date to jump straight to any day.
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final today = DateTime(now.year, now.month, now.day);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dayStart,
                    firstDate: today.subtract(const Duration(days: 365 * 6)),
                    lastDate: today,
                  );
                  if (picked != null) {
                    setState(() => _daysBack = today.difference(picked).inDays);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayLabel(dayStart),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.calendar_today, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: isToday ? null : () => setState(() => _daysBack--),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              _SummaryRow(
                emoji: '🌙',
                label: 'Sleep',
                value: todaySleep > Duration.zero ? formatDuration(todaySleep) : '–',
                lastTime: lastSleepTime,
                onTap: () => onNavigate(1),
              ),
              _SummaryRow(
                emoji: '🍼',
                label: 'Bottle',
                value: bottleFeedings.isEmpty
                    ? '–'
                    : '${bottleFeedings.length}'
                      '${bottleTotalMl > 0 ? ' · ${formatVolume(bottleTotalMl, unit)}' : ''}',
                lastTime: lastBottleTime,
                onTap: () => onNavigate(2),
              ),
              _SummaryRow(
                emoji: '🤱',
                label: 'Nursing',
                value: breastCount > 0 ? '$breastCount' : '–',
                lastTime: lastBreastTime,
                onTap: () => onNavigate(2),
              ),
              _SummaryRow(
                emoji: '🥣',
                label: 'Solids',
                value: solidsCount > 0 ? '$solidsCount' : '–',
                lastTime: lastSolidsTime,
                onTap: () => onNavigate(2),
              ),
              _SummaryRow(
                emoji: '🚽',
                label: 'Diapers',
                value: diaperCounts.isEmpty
                    ? '–'
                    : [
                        for (final t in DiaperType.values)
                          if ((diaperCounts[t] ?? 0) > 0) '${t.emoji} ${diaperCounts[t]}',
                      ].join('  '),
                lastTime: lastDiaperTime,
                onTap: () => onNavigate(3),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (timeline.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                isToday
                    ? 'Nothing logged today yet'
                    : 'Nothing logged this day',
              ),
            ),
          ),
        for (final event in timeline)
          InkWell(
            onTap: () => onNavigate(event.tab),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      DateFormat.jm().format(event.time),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(event.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (event.detail != null)
                          Text(
                            event.detail!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    formatTimeAgo(event.time),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (isToday) ...[
          Text('Quick log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.bedtime, size: 18),
                label: Text(sleepingNow == null ? 'Start sleep' : 'End sleep'),
                onPressed: () => sleepingNow == null
                    ? ref.read(sleepLogsProvider.notifier).startTimer()
                    : ref
                          .read(sleepLogsProvider.notifier)
                          .stopTimer(sleepingNow),
              ),
              ActionChip(
                avatar: Text(DiaperType.wet.emoji),
                label: Text('${DiaperType.wet.label} diaper'),
                onPressed: () =>
                    ref.read(diaperLogsProvider.notifier).add(DiaperType.wet),
              ),
              ActionChip(
                avatar: Text(DiaperType.dirty.emoji),
                label: Text('${DiaperType.dirty.label} diaper'),
                onPressed: () =>
                    ref.read(diaperLogsProvider.notifier).add(DiaperType.dirty),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.time,
    required this.emoji,
    required this.title,
    required this.tab,
    this.detail,
  });

  final DateTime time;
  final String emoji;
  final String title;
  final String? detail;
  final int tab;
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner({
    required this.icon,
    required this.text,
    required this.since,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final DateTime since;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        title: Text('$text now'),
        trailing: ElapsedText(since: since, style: theme.textTheme.titleMedium),
        onTap: onTap,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.emoji,
    required this.label,
    required this.value,
    this.lastTime,
    this.onTap,
    this.isLast = false,
  });

  final String emoji;
  final String label;
  final String value;
  final DateTime? lastTime;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final isEmpty = value == '–';
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Text(label, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isEmpty ? FontWeight.normal : FontWeight.w600,
                        color: isEmpty ? muted : null,
                      ),
                    ),
                    if (lastTime != null)
                      Text(
                        'Last ${formatTimeAgo(lastTime!)}',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: muted),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 48),
      ],
    );
  }
}
