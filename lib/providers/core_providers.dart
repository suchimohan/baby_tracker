import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local_store.dart';
import '../data/repositories.dart';
import '../data/sync_engine.dart';
import '../models/models.dart';

/// Overridden in main() with the opened store.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    store: ref.watch(localStoreProvider),
    client: ref.watch(supabaseClientProvider),
  );
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.current;
  yield* engine.status;
});

final childRepositoryProvider = Provider<ChildRepository>((ref) {
  return ChildRepository(
    store: ref.watch(localStoreProvider),
    client: ref.watch(supabaseClientProvider),
  );
});

final sleepRepositoryProvider = Provider<LogRepository<SleepLog>>((ref) {
  return LogRepository(
    table: 'sleep_logs',
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncEngineProvider),
    fromLocalJson: SleepLog.fromLocalJson,
  );
});

final feedingRepositoryProvider = Provider<LogRepository<FeedingLog>>((ref) {
  return LogRepository(
    table: 'feeding_logs',
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncEngineProvider),
    fromLocalJson: FeedingLog.fromLocalJson,
  );
});

final diaperRepositoryProvider = Provider<LogRepository<DiaperLog>>((ref) {
  return LogRepository(
    table: 'diaper_logs',
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncEngineProvider),
    fromLocalJson: DiaperLog.fromLocalJson,
  );
});
