import '../models/dish_model.dart';

import '../models/merchant_model.dart';

import '../models/user_model.dart';



/// 试运行账号条目

class TrialAccount {

  const TrialAccount({

    required this.phone,

    required this.name,

    required this.role,

    this.department,

  });



  final String phone;

  final String name;

  final UserRole role;

  final String? department;

}



/// 试运行登录手机号白名单

class LoginPhonePolicy {

  LoginPhonePolicy._();



  static const employeePhone = '13800000000';

  static const merchantPhone = '13900000000';



  static const _accounts = <TrialAccount>[

    TrialAccount(

      phone: '13800000000',

      name: '张三',

      department: '行政部',

      role: UserRole.employee,

    ),

    TrialAccount(

      phone: '13800000001',

      name: '李四',

      department: '销售部',

      role: UserRole.employee,

    ),

    TrialAccount(

      phone: '13800000002',

      name: '王五',

      department: '生产部',

      role: UserRole.employee,

    ),

    TrialAccount(

      phone: '13900000000',

      name: '绿健食堂',

      role: UserRole.merchant,

    ),

  ];



  static const unsupportedHint =

      '试运行账号：\n员工 13800000000 / 13800000001 / 13800000002\n商家 13900000000';



  static String normalize(String phone) =>

      phone.replaceAll(RegExp(r'\s'), '');



  static TrialAccount? accountForPhone(String phone) {

    final p = normalize(phone);

    for (final a in _accounts) {

      if (a.phone == p) return a;

    }

    return null;

  }



  /// 白名单手机号对应的固定身份；未登记返回 null

  static UserRole? roleForPhone(String phone) =>

      accountForPhone(phone)?.role;



  /// 员工姓名 / 部门（仅员工账号有值）

  static ({String name, String department})? employeeInfoForPhone(

    String phone,

  ) {

    final account = accountForPhone(phone);

    if (account == null ||

        account.role != UserRole.employee ||

        account.department == null) {

      return null;

    }

    return (name: account.name, department: account.department!);

  }



  /// 校验登录身份；通过返回 null，否则返回错误文案
  static String? validate(String phone, UserRole selectedRole) {
    final normalized = normalize(phone);
    final account = accountForPhone(normalized);

    if (selectedRole == UserRole.merchant) {
      if (account != null && account.role == UserRole.employee) {
        return '该手机号为员工账号，请选择「我是员工」';
      }
      return null;
    }

    if (account == null) {
      return '暂不支持该手机号登录（$unsupportedHint）';
    }
    if (account.role != selectedRole) {
      return account.role == UserRole.employee
          ? '该手机号为员工账号，请选择「我是员工」'
          : '该手机号为商家账号，请选择「我是商家」';
    }
    return null;
  }

}



/// 餐段订餐截止时间（当天 HH:mm 后不可下单）。
///
/// 取值优先级（与后端 `meal-deadline.util.ts` 对齐）：
///   1. 商家 `mealOpeningHours[type]` 营业结束时间 `end`（enabled）
///   2. 商家 `mealOrderDeadlines[type]`（历史同步字段）
///   3. 全局系统默认
class MealOrderDeadline {

  MealOrderDeadline._();

  /// 全局系统默认截止时间（分钟）。
  static const Map<MealType, int> _defaultMinutes = {
    MealType.breakfast: 7 * 60 + 30,
    MealType.lunch: 9 * 60 + 30,
    MealType.dinner: 15 * 60,
    MealType.overtime: 17 * 60 + 30,
  };

  /// 解析 `HH:mm` -> 分钟；非法返回 null。
  static int? _parseHm(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return h * 60 + min;
  }

  /// 餐段是否对外营业（未启用 supported / opening hours 视为未开放）。
  static bool isMealOpenFor(MealType type, {Merchant? merchant}) {
    if (merchant == null) return true;
    if (merchant.supportedMealTypes.isNotEmpty &&
        !merchant.supportedMealTypes.contains(type.name)) {
      return false;
    }
    final setting = merchant.mealOpeningHours[type.name];
    if (setting != null && !setting.enabled) return false;
    return true;
  }

  /// 订餐窗口（start/end 分钟 + 是否跨天）；无营业时间配置时返回 null。
  static ({int startMin, int endMin, bool crossDay})? _orderWindow(
    MealType type, {
    Merchant? merchant,
  }) {
    if (merchant == null) return null;
    final setting = merchant.mealOpeningHours[type.name];
    if (setting == null) return null;
    final start = _parseHm(setting.effectiveStart);
    final end = _parseHm(setting.effectiveEnd);
    if (start == null || end == null) return null;
    return (startMin: start, endMin: end, crossDay: end <= start);
  }

  /// 是否跨天营业（结束时间小于等于开始时间，如 23:00-03:00）。
  static bool isCrossDayFor(MealType type, {Merchant? merchant}) {
    final w = _orderWindow(type, merchant: merchant);
    return w != null && w.crossDay;
  }

  static bool _isWindowClosed(
    ({int startMin, int endMin, bool crossDay}) window,
    int nowMin,
  ) {
    if (window.crossDay) {
      if (nowMin >= window.startMin) return false;
      if (nowMin <= window.endMin) return false;
      return true;
    }
    return nowMin > window.endMin;
  }

  static int _minutes(MealType type, {Merchant? merchant}) {
    if (merchant != null) {
      final setting = merchant.mealOpeningHours[type.name];
      if (setting != null) {
        final fromEnd = _parseHm(setting.effectiveEnd);
        if (fromEnd != null) return fromEnd;
      }
      final fromDeadlines = _parseHm(merchant.mealOrderDeadlines[type.name]);
      if (fromDeadlines != null) return fromDeadlines;
    }
    return _defaultMinutes[type] ?? (24 * 60); // 兜底：不限制
  }

  static int _nowMinutes([DateTime? now]) {
    final n = now ?? DateTime.now();
    return n.hour * 60 + n.minute;
  }

  /// 当前时间是否已过该餐段截止时间或未开放。
  static bool isClosed(
    MealType type, [
    DateTime? now,
    Merchant? merchant,
  ]) {
    if (!isMealOpenFor(type, merchant: merchant)) return true;
    final window = _orderWindow(type, merchant: merchant);
    final nowMin = _nowMinutes(now);
    if (window != null) return _isWindowClosed(window, nowMin);
    return nowMin > _minutes(type, merchant: merchant);
  }

  static bool isClosedFor(
    MealType type, {
    Merchant? merchant,
    DateTime? now,
  }) {
    return isClosed(type, now, merchant);
  }

  /// 取某商家在某餐段的截止时间 `HH:mm`；商家未配置回退全局默认。
  static String deadlineLabel(MealType type, {Merchant? merchant}) {
    final mins = _minutes(type, merchant: merchant);
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 顶部餐段栏：跨天显示「次日 HH:mm 订餐截止」。
  static String deadlineTabLabel(MealType type, {Merchant? merchant}) {
    if (!isMealOpenFor(type, merchant: merchant)) return '未开放';
    final label = deadlineLabel(type, merchant: merchant);
    if (isCrossDayFor(type, merchant: merchant)) {
      return '次日 $label 订餐截止';
    }
    return '$label 订餐截止';
  }

  static const deadlineHint = '当前餐段已过订餐截止时间';
}



/// 订单按日期筛选

class OrderDateFilter {

  OrderDateFilter._();



  static bool isSameDay(DateTime a, DateTime b) =>

      a.year == b.year && a.month == b.month && a.day == b.day;



  static bool isToday(DateTime dt) => isSameDay(dt, DateTime.now());



  static List<T> onDate<T>(

    Iterable<T> source,

    DateTime date,

    DateTime Function(T) readDate,

  ) {

    return source.where((e) => isSameDay(readDate(e), date)).toList();

  }

}

