/// 展示文本兜底：避免 UI 出现 `????`、null、空字符串等。

bool looksLikeGarbledDisplayText(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return true;
  if (s.toLowerCase() == 'null' || s.toLowerCase() == 'undefined') return true;
  if (RegExp(r'^[\?？]+$').hasMatch(s)) return true;
  if (s.contains('???')) return true;
  if (RegExp(r'^[\?？]+').hasMatch(s) && s.toUpperCase().contains('E2E')) {
    return true;
  }
  return false;
}

String resolveDisplayMerchantName(
  String? raw, {
  String? fromMerchantProfile,
}) {
  final profile = (fromMerchantProfile ?? '').trim();
  if (profile.isNotEmpty && !looksLikeGarbledDisplayText(profile)) {
    return profile;
  }
  final n = (raw ?? '').trim();
  if (n.isNotEmpty && !looksLikeGarbledDisplayText(n)) return n;
  return '未知商家';
}

String resolveDisplayDishName(String? raw) {
  final n = (raw ?? '').trim();
  if (n.isNotEmpty && !looksLikeGarbledDisplayText(n)) return n;
  return '菜品信息缺失';
}

String resolveDisplayPackageName(String? raw) {
  final n = (raw ?? '').trim();
  if (n.isNotEmpty && !looksLikeGarbledDisplayText(n)) return n;
  return '套餐信息缺失';
}

String buildOrderItemsSummary({
  required bool isPackageOrder,
  String? packageName,
  required List<({String name, int quantity})> lineItems,
  List<({String name, int quantity})> selectedItems = const [],
  List<({String name, int quantity})> extraItems = const [],
}) {
  if (isPackageOrder) {
    final parts = <String>[resolveDisplayPackageName(packageName)];
    for (final s in selectedItems) {
      parts.add('${resolveDisplayDishName(s.name)} x${s.quantity > 0 ? s.quantity : 1}');
    }
    for (final e in extraItems) {
      if (e.quantity > 0) {
        parts.add('${resolveDisplayDishName(e.name)} x${e.quantity}');
      }
    }
    return parts.join('、');
  }
  if (lineItems.isEmpty) return '菜品信息缺失';
  return lineItems
      .map((e) => '${resolveDisplayDishName(e.name)} x${e.quantity}')
      .join('、');
}
