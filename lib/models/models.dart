/// Domain models for Baby Tracker v1.
///
/// All tracking logs share the offline-first envelope:
///  - [clientId]: UUID generated on-device; the idempotency key used to
///    upsert into Supabase (`on conflict client_id`).
///  - [serverId]: assigned by Postgres after first successful sync.
///  - [updatedAt]: drives Last-Write-Wins merging (REQUIREMENTS §5.4).
library;

enum SyncState { pending, synced, failed }

SyncState syncStateFrom(String? raw) => switch (raw) {
      'synced' => SyncState.synced,
      'failed' => SyncState.failed,
      _ => SyncState.pending,
    };

DateTime? _parseTs(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
String? _toTs(DateTime? v) => v?.toUtc().toIso8601String();

/// Common contract every syncable record implements.
abstract class SyncableRecord {
  String get clientId;
  String get childId;
  DateTime get updatedAt;
  SyncState get syncState;
  DateTime? get deletedAt;

  /// Row sent to Supabase (server columns only — no local sync metadata).
  Map<String, dynamic> toServerJson();

  /// Full local representation (server columns + sync metadata).
  Map<String, dynamic> toLocalJson();
}

// ============================================================
// Child
// ============================================================
class Child {
  const Child({
    required this.id,
    required this.name,
    required this.dateOfBirth,
    this.photoUrl,
  });

  final String id;
  final String name;
  final DateTime dateOfBirth;
  final String? photoUrl;

  factory Child.fromJson(Map<String, dynamic> json) => Child(
        id: json['id'] as String,
        name: json['name'] as String,
        dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
        photoUrl: json['photo_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date_of_birth':
            dateOfBirth.toIso8601String().split('T').first, // date column
        'photo_url': photoUrl,
      };

  /// Age like "3 mo" / "1 yr 2 mo" for the dashboard header.
  String get ageLabel {
    final now = DateTime.now();
    var months = (now.year - dateOfBirth.year) * 12 + now.month - dateOfBirth.month;
    if (now.day < dateOfBirth.day) months--;
    if (months < 0) months = 0;
    if (months < 24) return '$months mo';
    return '${months ~/ 12} yr ${months % 12} mo';
  }
}

// ============================================================
// Sleep
// ============================================================
class SleepLog implements SyncableRecord {
  const SleepLog({
    required this.clientId,
    required this.childId,
    required this.loggedBy,
    required this.startedAt,
    required this.updatedAt,
    this.serverId,
    this.endedAt,
    this.note,
    this.syncState = SyncState.pending,
    this.deletedAt,
  });

  @override
  final String clientId;
  final String? serverId;
  @override
  final String childId;
  final String loggedBy;
  final DateTime startedAt;
  final DateTime? endedAt; // null = timer running
  final String? note;
  @override
  final DateTime updatedAt;
  @override
  final SyncState syncState;
  @override
  final DateTime? deletedAt;

  bool get inProgress => endedAt == null && deletedAt == null;
  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt);

  SleepLog copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    String? note,
    String? serverId,
    SyncState? syncState,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      SleepLog(
        clientId: clientId,
        serverId: serverId ?? this.serverId,
        childId: childId,
        loggedBy: loggedBy,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        note: note ?? this.note,
        updatedAt: updatedAt ?? DateTime.now(),
        syncState: syncState ?? this.syncState,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  factory SleepLog.fromLocalJson(Map<String, dynamic> json) => SleepLog(
        clientId: json['client_id'] as String,
        serverId: json['id'] as String?,
        childId: json['child_id'] as String,
        loggedBy: json['logged_by'] as String,
        startedAt: _parseTs(json['started_at'])!,
        endedAt: _parseTs(json['ended_at']),
        note: json['note'] as String?,
        updatedAt: _parseTs(json['updated_at']) ?? DateTime.now(),
        syncState: syncStateFrom(json['_sync'] as String?),
        deletedAt: _parseTs(json['deleted_at']),
      );

  factory SleepLog.fromServerJson(Map<String, dynamic> json) =>
      SleepLog.fromLocalJson(json).copyWith(syncState: SyncState.synced);

  @override
  Map<String, dynamic> toServerJson() => {
        'client_id': clientId,
        'child_id': childId,
        'logged_by': loggedBy,
        'started_at': _toTs(startedAt),
        'ended_at': _toTs(endedAt),
        'note': note,
        'deleted_at': _toTs(deletedAt),
      };

  @override
  Map<String, dynamic> toLocalJson() => {
        ...toServerJson(),
        'id': serverId,
        'updated_at': _toTs(updatedAt),
        '_sync': syncState.name,
      };
}

// ============================================================
// Feeding
// ============================================================
enum FeedingType { bottle, breast, solids }

class FeedingLog implements SyncableRecord {
  const FeedingLog({
    required this.clientId,
    required this.childId,
    required this.loggedBy,
    required this.feedingType,
    required this.startedAt,
    required this.updatedAt,
    this.serverId,
    this.endedAt,
    this.amountMl,
    this.foods,
    this.note,
    this.syncState = SyncState.pending,
    this.deletedAt,
  });

  @override
  final String clientId;
  final String? serverId;
  @override
  final String childId;
  final String loggedBy;
  final FeedingType feedingType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? amountMl;
  final List<String>? foods; // solids only
  final String? note;
  @override
  final DateTime updatedAt;
  @override
  final SyncState syncState;
  @override
  final DateTime? deletedAt;

  bool get inProgress => endedAt == null && deletedAt == null;
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  FeedingLog copyWith({
    FeedingType? feedingType,
    DateTime? startedAt,
    DateTime? endedAt,
    double? amountMl,
    List<String>? foods,
    String? note,
    String? serverId,
    SyncState? syncState,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      FeedingLog(
        clientId: clientId,
        serverId: serverId ?? this.serverId,
        childId: childId,
        loggedBy: loggedBy,
        feedingType: feedingType ?? this.feedingType,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        amountMl: amountMl ?? this.amountMl,
        foods: foods ?? this.foods,
        note: note ?? this.note,
        updatedAt: updatedAt ?? DateTime.now(),
        syncState: syncState ?? this.syncState,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  factory FeedingLog.fromLocalJson(Map<String, dynamic> json) => FeedingLog(
        clientId: json['client_id'] as String,
        serverId: json['id'] as String?,
        childId: json['child_id'] as String,
        loggedBy: json['logged_by'] as String,
        feedingType: FeedingType.values.firstWhere(
          (t) => t.name == json['feeding_type'],
          orElse: () => FeedingType.bottle,
        ),
        startedAt: _parseTs(json['started_at'])!,
        endedAt: _parseTs(json['ended_at']),
        amountMl: (json['amount_ml'] as num?)?.toDouble(),
        foods: json['foods'] == null
            ? null
            : List<String>.from(json['foods'] as List),
        note: json['note'] as String?,
        updatedAt: _parseTs(json['updated_at']) ?? DateTime.now(),
        syncState: syncStateFrom(json['_sync'] as String?),
        deletedAt: _parseTs(json['deleted_at']),
      );

  factory FeedingLog.fromServerJson(Map<String, dynamic> json) =>
      FeedingLog.fromLocalJson(json).copyWith(syncState: SyncState.synced);

  @override
  Map<String, dynamic> toServerJson() => {
        'client_id': clientId,
        'child_id': childId,
        'logged_by': loggedBy,
        'feeding_type': feedingType.name,
        'started_at': _toTs(startedAt),
        'ended_at': _toTs(endedAt),
        'amount_ml': amountMl,
        'foods': foods,
        'note': note,
        'deleted_at': _toTs(deletedAt),
      };

  @override
  Map<String, dynamic> toLocalJson() => {
        ...toServerJson(),
        'id': serverId,
        'updated_at': _toTs(updatedAt),
        '_sync': syncState.name,
      };
}

// ============================================================
// Diaper
// ============================================================
enum DiaperType { wet, dirty, mixed, dry }

class DiaperLog implements SyncableRecord {
  const DiaperLog({
    required this.clientId,
    required this.childId,
    required this.loggedBy,
    required this.diaperType,
    required this.changedAt,
    required this.updatedAt,
    this.serverId,
    this.note,
    this.syncState = SyncState.pending,
    this.deletedAt,
  });

  @override
  final String clientId;
  final String? serverId;
  @override
  final String childId;
  final String loggedBy;
  final DiaperType diaperType;
  final DateTime changedAt;
  final String? note;
  @override
  final DateTime updatedAt;
  @override
  final SyncState syncState;
  @override
  final DateTime? deletedAt;

  DiaperLog copyWith({
    DiaperType? diaperType,
    DateTime? changedAt,
    String? note,
    String? serverId,
    SyncState? syncState,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      DiaperLog(
        clientId: clientId,
        serverId: serverId ?? this.serverId,
        childId: childId,
        loggedBy: loggedBy,
        diaperType: diaperType ?? this.diaperType,
        changedAt: changedAt ?? this.changedAt,
        note: note ?? this.note,
        updatedAt: updatedAt ?? DateTime.now(),
        syncState: syncState ?? this.syncState,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  factory DiaperLog.fromLocalJson(Map<String, dynamic> json) => DiaperLog(
        clientId: json['client_id'] as String,
        serverId: json['id'] as String?,
        childId: json['child_id'] as String,
        loggedBy: json['logged_by'] as String,
        diaperType: DiaperType.values.firstWhere(
          (t) => t.name == json['diaper_type'],
          orElse: () => DiaperType.wet,
        ),
        changedAt: _parseTs(json['changed_at'])!,
        note: json['note'] as String?,
        updatedAt: _parseTs(json['updated_at']) ?? DateTime.now(),
        syncState: syncStateFrom(json['_sync'] as String?),
        deletedAt: _parseTs(json['deleted_at']),
      );

  factory DiaperLog.fromServerJson(Map<String, dynamic> json) =>
      DiaperLog.fromLocalJson(json).copyWith(syncState: SyncState.synced);

  @override
  Map<String, dynamic> toServerJson() => {
        'client_id': clientId,
        'child_id': childId,
        'logged_by': loggedBy,
        'diaper_type': diaperType.name,
        'changed_at': _toTs(changedAt),
        'note': note,
        'deleted_at': _toTs(deletedAt),
      };

  @override
  Map<String, dynamic> toLocalJson() => {
        ...toServerJson(),
        'id': serverId,
        'updated_at': _toTs(updatedAt),
        '_sync': syncState.name,
      };
}
