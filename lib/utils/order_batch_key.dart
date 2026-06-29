import '../models/dish_model.dart';

String buildOrderBatchKey({
  required String date,
  required MealType mealType,
  required String merchantId,
}) {
  return '${date}_${mealType.name}_$merchantId';
}

String formatOrderDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

MealType mealTypeFromOrderItems(List<dynamic> items) {
  if (items.isEmpty) return MealType.lunch;
  try {
    final first = items.first;
    if (first is Map && first['dish'] is Map) {
      final mt = (first['dish'] as Map)['mealType'] as String?;
      if (mt != null) {
        return MealType.values.firstWhere(
          (m) => m.name == mt,
          orElse: () => MealType.lunch,
        );
      }
    }
  } catch (_) {}
  return MealType.lunch;
}
