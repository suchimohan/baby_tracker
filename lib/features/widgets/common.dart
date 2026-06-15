import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../providers/core_providers.dart';

/// UI display for diaper types. DB values stay wet/dirty/mixed/dry —
/// "Poop" is the parent-facing label for `dirty`.
extension DiaperTypeDisplay on DiaperType {
  String get label => switch (this) {
        DiaperType.wet => 'Wet',
        DiaperType.dirty => 'Poop',
        DiaperType.mixed => 'Mixed',
        DiaperType.dry => 'Dry',
      };

  String get emoji => switch (this) {
        DiaperType.wet => '💧',
        DiaperType.dirty => '💩',
        DiaperType.mixed => '💧💩',
        DiaperType.dry => '🌵',
      };
}

extension FeedingTypeDisplay on FeedingType {
  String get label => switch (this) {
        FeedingType.bottle => 'Bottle',
        FeedingType.breast => 'Nursing',
        FeedingType.solids => 'Solids',
      };

  String get emoji => switch (this) {
        FeedingType.bottle => '🍼',
        FeedingType.breast => '🤱',
        FeedingType.solids => '🥣',
      };
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m}m';
}

/// "Today" / "Yesterday" / "Mon, Jun 8" — history section headers.
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat.MMMEd().format(t);
}

/// Interleaves [items] (sorted newest-first) with day headers whenever the
/// calendar day changes. Used by all history lists so past days are browsable.
List<Widget> groupedByDay<T>({
  required BuildContext context,
  required List<T> items,
  required DateTime Function(T) dateOf,
  required Widget Function(T) rowBuilder,
}) {
  final widgets = <Widget>[];
  String? currentDay;
  for (final item in items) {
    final label = dayLabel(dateOf(item));
    if (label != currentDay) {
      currentDay = label;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ));
    }
    widgets.add(rowBuilder(item));
  }
  return widgets;
}

String formatTimeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  if (diff.inHours < 24) return m > 0 ? '${h}h ${m}m ago' : '${h}h ago';
  return DateFormat.MMMd().add_jm().format(t);
}

/// "Last synced…" banner + pending count (REQUIREMENTS §5.6 data freshness).
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    if (status.syncing) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!status.online || status.pendingCount > 0) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Chip(
          avatar: const Icon(Icons.cloud_off, size: 16),
          label: Text(status.pendingCount > 0
              ? '${status.pendingCount} pending'
              : 'Offline'),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(right: 12),
      child: Icon(Icons.cloud_done, size: 20),
    );
  }
}

/// Small dot showing a record's sync state on history rows.
class SyncDot extends StatelessWidget {
  const SyncDot(this.state, {super.key});
  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final (color, tooltip) = switch (state) {
      SyncState.synced => (Colors.green, 'Synced'),
      SyncState.pending => (Colors.orange, 'Waiting to sync'),
      SyncState.failed => (Colors.red, 'Sync failed — will retry'),
    };
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Live-updating elapsed time text for running timers.
class ElapsedText extends StatefulWidget {
  const ElapsedText({super.key, required this.since, this.style});
  final DateTime since;
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return Text('$h:$m:$s', style: widget.style);
  }
}
