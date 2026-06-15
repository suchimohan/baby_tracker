import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';

/// Common first foods, grouped by category. Shown as multi-select chips
/// when logging a solids meal.
const foodCatalog = <String, List<String>>{
  'Fruits': [
    'Banana', 'Apple', 'Pear', 'Avocado', 'Peach', 'Mango', 'Blueberries',
    'Strawberries',
  ],
  'Vegetables': [
    'Sweet potato', 'Carrot', 'Peas', 'Green beans', 'Squash', 'Broccoli',
    'Spinach',
  ],
  'Grains': [
    'Oatmeal', 'Rice cereal', 'Rice', 'Toast', 'Pasta', 'Puffs',
  ],
  'Protein & Dairy': [
    'Yogurt', 'Cheese', 'Egg', 'Chicken', 'Turkey', 'Beef', 'Salmon',
    'Lentils', 'Tofu',
  ],
};

/// Foods the parent added themselves (persisted on-device, shown in a
/// "Your foods" section).
class CustomFoodsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final raw = ref.watch(localStoreProvider).getMeta('custom_foods');
    if (raw == null) return const [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  Future<void> add(String food) async {
    final name = food.trim();
    if (name.isEmpty) return;
    final all = {...state, name}.toList();
    await ref.read(localStoreProvider).setMeta('custom_foods', jsonEncode(all));
    state = all;
  }

  Future<void> remove(String food) async {
    final all = state.where((f) => f != food).toList();
    await ref.read(localStoreProvider).setMeta('custom_foods', jsonEncode(all));
    state = all;
  }
}

final customFoodsProvider =
    NotifierProvider<CustomFoodsNotifier, List<String>>(CustomFoodsNotifier.new);

/// Built-in catalog foods the parent removed from their list (persisted).
/// Removal is only allowed when the food never appears in past meals.
class RemovedFoodsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final raw = ref.watch(localStoreProvider).getMeta('removed_foods');
    if (raw == null) return const {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  Future<void> add(String food) async {
    final all = {...state, food};
    await ref
        .read(localStoreProvider)
        .setMeta('removed_foods', jsonEncode(all.toList()));
    state = all;
  }
}

final removedFoodsProvider =
    NotifierProvider<RemovedFoodsNotifier, Set<String>>(RemovedFoodsNotifier.new);

/// Bottle amounts are stored in ml (schema unchanged); display unit is a
/// device preference. Oz is the common unit in the US.
enum VolumeUnit { ml, oz }

const mlPerOz = 29.5735;

double ozToMl(double oz) => oz * mlPerOz;
double mlToOz(double ml) => ml / mlPerOz;

class VolumeUnitNotifier extends Notifier<VolumeUnit> {
  @override
  VolumeUnit build() =>
      ref.watch(localStoreProvider).getMeta('volume_unit') == 'ml'
          ? VolumeUnit.ml
          : VolumeUnit.oz; // default oz (primary market is US)

  Future<void> set(VolumeUnit unit) async {
    await ref.read(localStoreProvider).setMeta('volume_unit', unit.name);
    state = unit;
  }
}

final volumeUnitProvider =
    NotifierProvider<VolumeUnitNotifier, VolumeUnit>(VolumeUnitNotifier.new);

/// "4 oz" / "4.5 oz" / "120 ml" from a stored-ml amount.
String formatVolume(double ml, VolumeUnit unit) {
  if (unit == VolumeUnit.ml) return '${ml.round()} ml';
  final oz = mlToOz(ml);
  final rounded = (oz * 2).round() / 2; // nearest half ounce
  return rounded == rounded.truncate()
      ? '${rounded.truncate()} oz'
      : '$rounded oz';
}

/// Parse user input in [unit] into stored ml. Returns null if not a number.
double? parseVolumeToMl(String input, VolumeUnit unit) {
  final value = double.tryParse(input.trim());
  if (value == null) return null;
  return unit == VolumeUnit.oz ? ozToMl(value) : value;
}
