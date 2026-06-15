import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'data/local_store.dart';
import 'providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local cache first — the app must boot with no network (§5.6).
  final store = await LocalStore.open();

  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  } catch (e) {
    // Backend unreachable/not configured: offline-first still works; writes
    // stay queued in Hive until a sync succeeds.
    debugPrint('Supabase init failed (continuing offline): $e');
  }

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const BabyTrackerApp(),
    ),
  );
}
