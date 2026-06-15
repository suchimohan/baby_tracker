import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'auth_providers.dart';
import 'core_providers.dart';

class ChildrenNotifier extends AsyncNotifier<List<Child>> {
  @override
  Future<List<Child>> build() async {
    final repo = ref.watch(childRepositoryProvider);
    final cached = repo.cached();
    if (ref.read(demoModeProvider)) return cached;
    // Serve cache instantly; refresh from server in background.
    if (cached.isNotEmpty) {
      _refreshSilently();
      return cached;
    }
    try {
      return await repo.refresh();
    } catch (_) {
      return cached; // offline — cache is the truth for now
    }
  }

  Future<void> _refreshSilently() async {
    try {
      final fresh = await ref.read(childRepositoryProvider).refresh();
      state = AsyncData(fresh);
    } catch (_) {
      /* offline */
    }
  }

  Future<Child> create({required String name, required DateTime dob}) async {
    final store = ref.read(localStoreProvider);
    late Child child;
    if (ref.read(demoModeProvider)) {
      child = Child(id: const Uuid().v4(), name: name, dateOfBirth: dob);
      await store.put('children', child.id, child.toJson());
    } else {
      child = await ref
          .read(childRepositoryProvider)
          .create(name: name, dob: dob);
    }
    await store.setMeta('selected_child', child.id);
    // Invalidate instead of setting state directly — avoids triggering a
    // synchronous rebuild cascade that Riverpod 3.3 flags as circular.
    ref.invalidateSelf();
    return child;
  }

  Future<void> deleteChild(Child child) async {
    final store = ref.read(localStoreProvider);
    final currentChildren = state.value ?? const <Child>[];
    if (ref.read(demoModeProvider)) {
      await ref.read(childRepositoryProvider).deleteLocalChildData(child.id);
    } else {
      await ref.read(childRepositoryProvider).deleteChildData(child.id);
    }
    final remainingChildren = currentChildren
        .where((c) => c.id != child.id)
        .toList(growable: false);
    await store.setMeta(
      'selected_child',
      remainingChildren.isEmpty ? null : remainingChildren.first.id,
    );
    state = AsyncData(remainingChildren);
  }
}

final childrenProvider = AsyncNotifierProvider<ChildrenNotifier, List<Child>>(
  ChildrenNotifier.new,
);

class SelectedChildNotifier extends Notifier<Child?> {
  @override
  Child? build() {
    final children = ref.watch(childrenProvider).value ?? const [];
    if (children.isEmpty) return null;
    final savedId = ref.read(localStoreProvider).getMeta('selected_child');
    return children.firstWhere(
      (c) => c.id == savedId,
      orElse: () => children.first,
    );
  }

  Future<void> select(Child child) async {
    await ref.read(localStoreProvider).setMeta('selected_child', child.id);
    state = child;
    // Pull the newly selected child's logs from the server.
    unawaited(ref.read(syncEngineProvider).requestSync());
  }
}

final selectedChildProvider = NotifierProvider<SelectedChildNotifier, Child?>(
  SelectedChildNotifier.new,
);
