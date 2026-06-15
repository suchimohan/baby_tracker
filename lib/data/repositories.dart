import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'local_store.dart';
import 'sync_engine.dart';

const _uuid = Uuid();

/// Offline-optimistic write flow (REQUIREMENTS §5.6):
/// 1. Write to Hive immediately with `_sync: pending` → instant UI update.
/// 2. Kick the sync engine; on success the row flips to `synced` and gains
///    its server `id`. Deletes are soft (`deleted_at`) so peers converge.
class LogRepository<T extends SyncableRecord> {
  LogRepository({
    required this.table,
    required this.store,
    required this.sync,
    required this.fromLocalJson,
  });

  final String table;
  final LocalStore store;
  final SyncEngine sync;
  final T Function(Map<String, dynamic>) fromLocalJson;

  List<T> forChild(String childId) => store
      .all(table)
      .map(fromLocalJson)
      .where((r) => r.childId == childId && r.deletedAt == null)
      .toList(growable: false);

  Future<void> save(T record) async {
    await store.put(table, record.clientId, record.toLocalJson());
    unawaited(sync.requestSync());
  }

  Future<void> softDelete(T record) async {
    final json = record.toLocalJson()
      ..['deleted_at'] = DateTime.now().toUtc().toIso8601String()
      ..['_sync'] = 'pending';
    await store.put(table, record.clientId, json);
    unawaited(sync.requestSync());
  }
}

/// Child profiles + caregiver membership.
class ChildRepository {
  ChildRepository({required this.store, required this.client});

  final LocalStore store;
  final SupabaseClient client;

  List<Child> cached() =>
      store.all('children').map(Child.fromJson).toList(growable: false);

  Future<List<Child>> refresh() async {
    final rows = List<Map<String, dynamic>>.from(
      await client.from('children').select(),
    );
    for (final row in rows) {
      await store.put('children', row['id'] as String, row);
    }
    return cached();
  }

  /// Creates the child and links the creator as primary caregiver.
  Future<Child> create({required String name, required DateTime dob}) async {
    final userId = client.auth.currentUser!.id;
    final row = await client
        .from('children')
        .insert({
          'name': name,
          'date_of_birth': dob.toIso8601String().split('T').first,
          'created_by': userId,
        })
        .select()
        .single();
    await client.from('caregiver_children').insert({
      'child_id': row['id'],
      'caregiver_id': userId,
      'role': 'primary',
    });
    await store.put('children', row['id'] as String, row);
    return Child.fromJson(row);
  }

  Future<String> invite({
    required String childId,
    required String email,
  }) async {
    final row = await client
        .from('caregiver_invites')
        .insert({
          'child_id': childId,
          'invited_by': client.auth.currentUser!.id,
          'invite_email': email.trim().toLowerCase(),
        })
        .select()
        .single();
    return row['token'] as String;
  }

  Future<void> acceptInvite(String token) async {
    await client.rpc(
      'accept_caregiver_invite',
      params: {'invite_token': token},
    );
  }

  /// COPPA §8.1: one-action deletion of all child data (server + local).
  Future<void> deleteChildData(String childId) async {
    await client.rpc('delete_child_data', params: {'target_child': childId});
    await deleteLocalChildData(childId);
  }

  Future<void> deleteLocalChildData(String childId) async {
    await store.delete('children', childId);
    for (final table in ['sleep_logs', 'feeding_logs', 'diaper_logs']) {
      for (final row in store.all(table)) {
        if (row['child_id'] == childId) {
          await store.delete(table, row['client_id'] as String);
        }
      }
    }
  }
}

String newClientId() => _uuid.v4();
