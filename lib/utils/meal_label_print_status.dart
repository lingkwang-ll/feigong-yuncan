import 'meal_batch_aggregator.dart';

class MealLabelPrintStatusItem {
  final String orderId;
  final String labelCode;
  final DateTime? printedAt;
  final int printCount;

  const MealLabelPrintStatusItem({
    required this.orderId,
    required this.labelCode,
    this.printedAt,
    this.printCount = 0,
  });

  factory MealLabelPrintStatusItem.fromJson(Map<String, dynamic> json) {
    return MealLabelPrintStatusItem(
      orderId: (json['orderId'] as String?) ?? '',
      labelCode: (json['labelCode'] as String?) ?? '',
      printedAt: DateTime.tryParse(json['printedAt'] as String? ?? ''),
      printCount: ((json['printCount'] as num?) ?? 0).toInt(),
    );
  }
}

Map<String, MealLabelPrintStatusItem> parseMealLabelPrintStatusMap(
  List<dynamic> items,
) {
  final map = <String, MealLabelPrintStatusItem>{};
  for (final raw in items) {
    if (raw is! Map) continue;
    final item = MealLabelPrintStatusItem.fromJson(raw.cast<String, dynamic>());
    if (item.orderId.isEmpty || item.labelCode.isEmpty) continue;
    map['${item.orderId}|${item.labelCode}'] = item;
  }
  return map;
}

List<MealLabelGroup> applyMealLabelPrintStatus(
  List<MealLabelGroup> groups,
  Map<String, MealLabelPrintStatusItem> statusMap,
) {
  return groups.map((g) {
    final st = statusMap[g.labelKey];
    if (st == null) return g;
    return g.copyWithPrintStatus(
      isLabelPrinted: st.printCount > 0,
      labelPrintCount: st.printCount,
      labelPrintedAt: st.printedAt,
    );
  }).toList();
}

String formatBusinessDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

enum MealLabelPrintFilter { unprinted, printed, all }

List<MealLabelGroup> filterMealLabelGroups(
  List<MealLabelGroup> groups,
  MealLabelPrintFilter filter,
) {
  switch (filter) {
    case MealLabelPrintFilter.unprinted:
      return groups.where((g) => !g.isLabelPrinted).toList();
    case MealLabelPrintFilter.printed:
      return groups.where((g) => g.isLabelPrinted).toList();
    case MealLabelPrintFilter.all:
      return groups;
  }
}
