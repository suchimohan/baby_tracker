import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/create_child_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/home/home_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/child_providers.dart';
import 'providers/core_providers.dart';

class BabyTrackerApp extends StatelessWidget {
  const BabyTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baby Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7E57C2)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7E57C2),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Routing by app state (REQUIREMENTS §5.5 — App State layer):
///   signed out          → SignInScreen
///   signed in, no child → CreateChildScreen
///   signed in + child   → HomeShell (+ realtime subscription)
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const SignInScreen();

    final children = ref.watch(childrenProvider);
    return children.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Something went wrong:\n$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(childrenProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (list) =>
          list.isEmpty ? const CreateChildScreen() : const _RealtimeScope(),
    );
  }
}

/// Holds the Realtime subscription for the selected child while home is shown.
class _RealtimeScope extends ConsumerStatefulWidget {
  const _RealtimeScope();

  @override
  ConsumerState<_RealtimeScope> createState() => _RealtimeScopeState();
}

class _RealtimeScopeState extends ConsumerState<_RealtimeScope> {
  RealtimeChannel? _channel;
  String? _childId;

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final demo = ref.watch(demoModeProvider);
    if (!demo && child != null && child.id != _childId) {
      _channel?.unsubscribe();
      _channel = ref.read(syncEngineProvider).subscribeRealtime(child.id);
      _childId = child.id;
    }
    return const HomeShell();
  }
}
