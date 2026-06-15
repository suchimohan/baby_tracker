import 'package:hive_ce_flutter/hive_flutter.dart';

/// Hive-backed local cache (REQUIREMENTS §5.6).
///
/// One box per server table; records are stored as JSON maps keyed by
/// `client_id`. Records with `_sync == 'pending'` form the offline queue.
class LocalStore {
  LocalStore._();

  static const _boxNames = [
    'sleep_logs',
    'feeding_logs',
    'diaper_logs',
    'children',
    'meta',
  ];

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    for (final name in _boxNames) {
      await Hive.openBox<Map>(name);
    }
    return LocalStore._();
  }

  Box<Map> box(String table) => Hive.box<Map>(table);

  /// All rows of a table as string-keyed JSON maps.
  List<Map<String, dynamic>> all(String table) => box(table)
      .values
      .map((m) => Map<String, dynamic>.from(m))
      .toList(growable: false);

  Map<String, dynamic>? get(String table, String clientId) {
    final raw = box(table).get(clientId);
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<void> put(String table, String clientId, Map<String, dynamic> json) =>
      box(table).put(clientId, json);

  Future<void> delete(String table, String clientId) =>
      box(table).delete(clientId);

  /// Rows awaiting upload to Supabase.
  List<Map<String, dynamic>> pending(String table) =>
      all(table).where((r) => r['_sync'] == 'pending').toList(growable: false);

  // -- meta (selected child, last sync time, consent flag) --
  String? getMeta(String key) {
    final raw = box('meta').get('kv');
    return raw == null ? null : raw[key] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    final raw = Map<String, dynamic>.from(box('meta').get('kv') ?? {});
    if (value == null) {
      raw.remove(key);
    } else {
      raw[key] = value;
    }
    await box('meta').put('kv', raw);
  }

  /// COPPA: wipe everything local (sign-out / account deletion).
  Future<void> clearAll() async {
    for (final name in _boxNames) {
      await box(name).clear();
    }
  }
}
