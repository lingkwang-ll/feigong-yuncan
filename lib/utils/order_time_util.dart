import 'package:intl/intl.dart';

/// 订单时间：后端 ISO 为权威来源，展示统一为 Asia/Shanghai。
class OrderTimeUtil {
  OrderTimeUtil._();

  static const _shanghaiOffset = Duration(hours: 8);

  /// 解析后端返回的 createdAt（优先 UTC ISO）。
  static DateTime parseCreatedAt(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return DateTime.now().toUtc();
    }
    final trimmed = raw.trim();
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return DateTime.now().toUtc();
    if (trimmed.endsWith('Z')) return parsed.toUtc();
    if (RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(trimmed)) {
      return parsed.toUtc();
    }
    // 历史无时区标记：按 UTC 存储解释
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }

  static DateTime toShanghai(DateTime dt) {
    final utc = dt.toUtc();
    return utc.add(_shanghaiOffset);
  }

  /// 格式：YYYY-MM-DD HH:mm（上海时区）
  static String formatDisplay(DateTime dt) {
    final sh = toShanghai(dt);
    return DateFormat('yyyy-MM-dd HH:mm').format(sh);
  }

  /// 判断订单创建时间（UTC）是否落在上海时区的指定自然日。
  static bool isSameShanghaiDay(DateTime utcOrLocal, DateTime dayAnchor) {
    final sh = toShanghai(utcOrLocal);
    return sh.year == dayAnchor.year &&
        sh.month == dayAnchor.month &&
        sh.day == dayAnchor.day;
  }
}
