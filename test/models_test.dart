import 'package:flutter_test/flutter_test.dart';

import 'package:baby_tracker/models/models.dart';

void main() {
  group('SleepLog', () {
    final start = DateTime(2026, 6, 10, 14);
    final end = DateTime(2026, 6, 10, 15, 30);

    test('local JSON round-trip preserves fields and sync state', () {
      final log = SleepLog(
        clientId: 'c-1',
        childId: 'child-1',
        loggedBy: 'user-1',
        startedAt: start,
        endedAt: end,
        note: 'crib nap',
        updatedAt: end,
      );
      final restored = SleepLog.fromLocalJson(log.toLocalJson());
      expect(restored.clientId, 'c-1');
      expect(restored.childId, 'child-1');
      expect(restored.startedAt, start);
      expect(restored.endedAt, end);
      expect(restored.note, 'crib nap');
      expect(restored.syncState, SyncState.pending);
      expect(restored.duration, const Duration(hours: 1, minutes: 30));
    });

    test('server rows parse as synced', () {
      final log = SleepLog(
        clientId: 'c-2',
        childId: 'child-1',
        loggedBy: 'user-1',
        startedAt: start,
        updatedAt: start,
      );
      final serverRow = log.toLocalJson()..['id'] = 'srv-1';
      final restored = SleepLog.fromServerJson(serverRow);
      expect(restored.syncState, SyncState.synced);
      expect(restored.serverId, 'srv-1');
      expect(restored.inProgress, isTrue); // no ended_at yet
    });

    test('server payload never contains local sync metadata', () {
      final log = SleepLog(
        clientId: 'c-3',
        childId: 'child-1',
        loggedBy: 'user-1',
        startedAt: start,
        updatedAt: start,
      );
      final payload = log.toServerJson();
      expect(payload.containsKey('_sync'), isFalse);
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('updated_at'), isFalse);
    });
  });

  group('FeedingLog', () {
    test('bottle round-trip keeps amount', () {
      final log = FeedingLog(
        clientId: 'f-1',
        childId: 'child-1',
        loggedBy: 'user-1',
        feedingType: FeedingType.bottle,
        startedAt: DateTime(2026, 6, 10, 9),
        endedAt: DateTime(2026, 6, 10, 9, 20),
        amountMl: 120,
        updatedAt: DateTime(2026, 6, 10, 9, 20),
      );
      final restored = FeedingLog.fromLocalJson(log.toLocalJson());
      expect(restored.feedingType, FeedingType.bottle);
      expect(restored.amountMl, 120);
    });
  });

  group('DiaperLog', () {
    test('round-trip keeps type', () {
      final log = DiaperLog(
        clientId: 'd-1',
        childId: 'child-1',
        loggedBy: 'user-1',
        diaperType: DiaperType.mixed,
        changedAt: DateTime(2026, 6, 10, 8),
        updatedAt: DateTime(2026, 6, 10, 8),
      );
      final restored = DiaperLog.fromLocalJson(log.toLocalJson());
      expect(restored.diaperType, DiaperType.mixed);
    });
  });

  group('Child', () {
    test('ageLabel under two years uses months', () {
      final child = Child(
        id: 'k-1',
        name: 'Asha',
        dateOfBirth: DateTime.now().subtract(const Duration(days: 100)),
      );
      expect(child.ageLabel, '3 mo');
    });
  });
}
