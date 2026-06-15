import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';

/// Connectivity-aware background sync (REQUIREMENTS §5.6).
///
/// Write path: repositories write to Hive with `_sync: pending`, then call
/// [requestSync]. The engine pushes pending rows (upsert on `client_id` so
/// retries are idempotent), then pulls server rows and merges by
/// Last-Write-Wins on `updated_at`.
class SyncEngine {
  SyncEngine({
    required this.store,
    required this.client,
    this.tables = const ['sleep_logs', 'feeding_logs', 'diaper_logs'],
  });

  final LocalStore store;
  final SupabaseClient client;
  final List<String> tables;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _statusController.stream;
  SyncStatus _current = const SyncStatus();
  SyncStatus get current => _current;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  bool _syncing = false;
  final _changeController = StreamController<String>.broadcast();

  /// Emits a table name whenever the merge step changed local rows
  /// (providers listen to refresh their state).
  Stream<String> get changes => _changeController.stream;

  void start() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      _setStatus(_current.copyWith(online: online));
      if (online) requestSync();
    });
    // Retry loop: every 5 minutes while anything is pending (§5.6 sync job).
    _retryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_pendingCount() > 0) requestSync();
    });
    requestSync();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _statusController.close();
    _changeController.close();
  }

  int _pendingCount() =>
      tables.fold(0, (sum, t) => sum + store.pending(t).length);

  void _setStatus(SyncStatus s) {
    _current = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  Future<void> requestSync() async {
    // Local mode: everything stays on-device; never touch the network.
    if (store.getMeta('demo_mode') == 'true') return;
    if (_syncing) return;
    _syncing = true;
    _setStatus(_current.copyWith(syncing: true, pendingCount: _pendingCount()));
    try {
      for (final table in tables) {
        await _pushPending(table);
      }
      final childId = store.getMeta('selected_child');
      if (childId != null) {
        for (final table in tables) {
          await _pullTable(table, childId);
        }
      }
      _setStatus(SyncStatus(
        online: true,
        syncing: false,
        pendingCount: _pendingCount(),
        lastSyncedAt: DateTime.now(),
      ));
      await store.setMeta('last_synced_at', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('sync failed: $e');
      _setStatus(_current.copyWith(
        syncing: false,
        online: false,
        pendingCount: _pendingCount(),
      ));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pushPending(String table) async {
    final rows = store.pending(table);
    for (final row in rows) {
      final clientId = row['client_id'] as String;
      // Strip local-only fields before sending.
      final payload = Map<String, dynamic>.from(row)
        ..remove('_sync')
        ..remove('id')
        ..remove('updated_at');
      try {
        final inserted = await client
            .from(table)
            .upsert(payload, onConflict: 'client_id')
            .select()
            .single();
        final merged = Map<String, dynamic>.from(inserted)..['_sync'] = 'synced';
        await store.put(table, clientId, merged);
      } on PostgrestException catch (e) {
        // 4xx (validation/RLS) → permanent failure, surface to user (§5.6 d).
        // Anything else → keep pending, retry on next cycle (§5.6 e).
        final code = int.tryParse(e.code ?? '') ?? 0;
        if (code >= 400 && code < 500) {
          final failed = Map<String, dynamic>.from(row)..['_sync'] = 'failed';
          await store.put(table, clientId, failed);
        }
        rethrow;
      }
    }
    if (rows.isNotEmpty) _changeController.add(table);
  }

  Future<void> _pullTable(String table, String childId) async {
    final since = store.getMeta('last_synced_at');
    var query = client.from(table).select().eq('child_id', childId);
    if (since != null) {
      query = query.gte('updated_at', since);
    }
    final rows = List<Map<String, dynamic>>.from(await query);
    var changed = false;
    for (final serverRow in rows) {
      final clientId = serverRow['client_id'] as String;
      final local = store.get(table, clientId);
      if (local != null && local['_sync'] == 'pending') {
        // Local unsynced edit in flight: Last-Write-Wins on updated_at.
        final localTs = DateTime.tryParse(local['updated_at'] as String? ?? '');
        final serverTs =
            DateTime.tryParse(serverRow['updated_at'] as String? ?? '');
        if (localTs != null && serverTs != null && localTs.isAfter(serverTs)) {
          continue; // keep local; next push wins
        }
      }
      await store.put(
        table,
        clientId,
        Map<String, dynamic>.from(serverRow)..['_sync'] = 'synced',
      );
      changed = true;
    }
    if (changed) _changeController.add(table);
  }

  /// Subscribe to Realtime changes for the selected child so other
  /// caregivers' edits appear within seconds (REQUIREMENTS §5.4).
  RealtimeChannel subscribeRealtime(String childId) {
    final channel = client.channel('logs-$childId');
    for (final table in tables) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'child_id',
          value: childId,
        ),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final clientId = row['client_id'] as String?;
          if (clientId == null) return;
          final local = store.get(table, clientId);
          if (local != null && local['_sync'] == 'pending') return; // LWW: ours newer
          await store.put(
            table,
            clientId,
            Map<String, dynamic>.from(row)..['_sync'] = 'synced',
          );
          _changeController.add(table);
        },
      );
    }
    channel.subscribe();
    return channel;
  }
}

class SyncStatus {
  const SyncStatus({
    this.online = true,
    this.syncing = false,
    this.pendingCount = 0,
    this.lastSyncedAt,
  });

  final bool online;
  final bool syncing;
  final int pendingCount;
  final DateTime? lastSyncedAt;

  SyncStatus copyWith({
    bool? online,
    bool? syncing,
    int? pendingCount,
    DateTime? lastSyncedAt,
  }) =>
      SyncStatus(
        online: online ?? this.online,
        syncing: syncing ?? this.syncing,
        pendingCount: pendingCount ?? this.pendingCount,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
}
