import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'auth_providers.dart';
import 'child_providers.dart';
import 'core_providers.dart';

/// Server-state notifiers (REQUIREMENTS §5.5): one per entity, reading from
/// the local cache (instant) and reloading whenever the sync engine merges
/// server changes for its table.
abstract class _LogsNotifier<T extends SyncableRecord> extends Notifier<List<T>> {
  String get table;
  LogRepository<T> get repo;
  int Function(T, T) get comparator;

  @override
  List<T> build() {
    final child = ref.watch(selectedChildProvider);
    final sync = ref.watch(syncEngineProvider);
    final sub = sync.changes
        .where((t) => t == table)
        .listen((_) => state = _load(child?.id));
    ref.onDispose(sub.cancel);
    return _load(child?.id);
  }

  List<T> _load(String? childId) {
    if (childId == null) return [];
    final list = repo.forChild(childId).toList()..sort(comparator);
    return list;
  }

  String requireUser() {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) throw StateError('not signed in');
    return userId;
  }

  String requireChild() {
    final child = ref.read(selectedChildProvider);
    if (child == null) throw StateError('no child selected');
    return child.id;
  }

  Future<void> _persist(T record) async {
    await repo.save(record);
    state = _load(record.childId);
  }

  Future<void> remove(T record) async {
    await repo.softDelete(record);
    state = _load(record.childId);
  }
}

// ============================================================
// Sleep
// ============================================================
class SleepLogsNotifier extends _LogsNotifier<SleepLog> {
  @override
  String get table => 'sleep_logs';
  @override
  LogRepository<SleepLog> get repo => ref.read(sleepRepositoryProvider);
  @override
  int Function(SleepLog, SleepLog) get comparator =>
      (a, b) => b.startedAt.compareTo(a.startedAt);

  SleepLog? get inProgress =>
      state.where((l) => l.inProgress).firstOrNull;

  /// Start the sleep timer. [at] lets a parent start it retroactively
  /// ("she fell asleep 20 minutes ago and is still sleeping").
  Future<void> startTimer({DateTime? at}) => _persist(SleepLog(
        clientId: newClientId(),
        childId: requireChild(),
        loggedBy: requireUser(),
        startedAt: at ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ));

  /// Adjust the start of a running timer.
  Future<void> updateStart(SleepLog log, DateTime start) =>
      _persist(log.copyWith(startedAt: start, syncState: SyncState.pending));

  Future<void> stopTimer(SleepLog log) =>
      _persist(log.copyWith(endedAt: DateTime.now(), syncState: SyncState.pending));

  Future<void> addManual({
    required DateTime start,
    required DateTime end,
    String? note,
  }) =>
      _persist(SleepLog(
        clientId: newClientId(),
        childId: requireChild(),
        loggedBy: requireUser(),
        startedAt: start,
        endedAt: end,
        note: note,
        updatedAt: DateTime.now(),
      ));

  Future<void> update(SleepLog log, {required DateTime start, required DateTime end}) =>
      _persist(log.copyWith(startedAt: start, endedAt: end, syncState: SyncState.pending));
}

final sleepLogsProvider =
    NotifierProvider<SleepLogsNotifier, List<SleepLog>>(SleepLogsNotifier.new);

// ============================================================
// Feeding
// ============================================================
class FeedingLogsNotifier extends _LogsNotifier<FeedingLog> {
  @override
  String get table => 'feeding_logs';
  @override
  LogRepository<FeedingLog> get repo => ref.read(feedingRepositoryProvider);
  @override
  int Function(FeedingLog, FeedingLog) get comparator =>
      (a, b) => b.startedAt.compareTo(a.startedAt);

  FeedingLog? get inProgress => state.where((l) => l.inProgress).firstOrNull;

  Future<void> startTimer(FeedingType type) => _persist(FeedingLog(
        clientId: newClientId(),
        childId: requireChild(),
        loggedBy: requireUser(),
        feedingType: type,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

  Future<void> stopTimer(FeedingLog log, {double? amountMl}) =>
      _persist(log.copyWith(
        endedAt: DateTime.now(),
        amountMl: amountMl,
        syncState: SyncState.pending,
      ));

  Future<void> addManual({
    required FeedingType type,
    required DateTime start,
    DateTime? end,
    double? amountMl,
    List<String>? foods,
    String? note,
  }) =>
      _persist(FeedingLog(
        clientId: newClientId(),
        childId: requireChild(),
        loggedBy: requireUser(),
        feedingType: type,
        startedAt: start,
        endedAt: end ?? start,
        amountMl: amountMl,
        foods: foods,
        note: note,
        updatedAt: DateTime.now(),
      ));

  Future<void> update(
    FeedingLog log, {
    required FeedingType type,
    required DateTime start,
    double? amountMl,
    List<String>? foods,
  }) =>
      _persist(log.copyWith(
        feedingType: type,
        startedAt: start,
        amountMl: amountMl,
        foods: foods,
        syncState: SyncState.pending,
      ));
}

final feedingLogsProvider = NotifierProvider<FeedingLogsNotifier, List<FeedingLog>>(
    FeedingLogsNotifier.new);

// ============================================================
// Diaper
// ============================================================
class DiaperLogsNotifier extends _LogsNotifier<DiaperLog> {
  @override
  String get table => 'diaper_logs';
  @override
  LogRepository<DiaperLog> get repo => ref.read(diaperRepositoryProvider);
  @override
  int Function(DiaperLog, DiaperLog) get comparator =>
      (a, b) => b.changedAt.compareTo(a.changedAt);

  Future<void> add(DiaperType type, {DateTime? at, String? note}) =>
      _persist(DiaperLog(
        clientId: newClientId(),
        childId: requireChild(),
        loggedBy: requireUser(),
        diaperType: type,
        changedAt: at ?? DateTime.now(),
        note: note,
        updatedAt: DateTime.now(),
      ));

  Future<void> update(DiaperLog log, {required DiaperType type, required DateTime at}) =>
      _persist(log.copyWith(diaperType: type, changedAt: at, syncState: SyncState.pending));
}

final diaperLogsProvider =
    NotifierProvider<DiaperLogsNotifier, List<DiaperLog>>(DiaperLogsNotifier.new);
