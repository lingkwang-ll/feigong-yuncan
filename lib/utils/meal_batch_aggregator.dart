import '../models/dish_model.dart';
import '../models/order_model.dart';
import '../widgets/merchant_order_status_chip.dart';
import 'employee_info_helper.dart';
import 'order_time_util.dart';

enum MealBatchPhase {
  pending('待确认'),
  preparing('备餐中'),
  delivering('配送中'),
  completed('已完成'),
  empty('暂无订餐');

  final String label;
  const MealBatchPhase(this.label);
}

class DishAggregate {
  final String dishName;
  final int quantity;

  const DishAggregate({required this.dishName, required this.quantity});
}

class MealBatchCollectorInfo {
  final String name;
  final String phone;
  final String address;
  final String poiName;
  final String addressText;
  final bool hasCollector;
  final bool multipleCollectors;

  const MealBatchCollectorInfo({
    required this.name,
    required this.phone,
    required this.address,
    this.poiName = '',
    this.addressText = '',
    required this.hasCollector,
    this.multipleCollectors = false,
  });

  factory MealBatchCollectorInfo.empty() => const MealBatchCollectorInfo(
        name: '',
        phone: '',
        address: '',
        hasCollector: false,
      );

  String get addressShort => EmployeeInfoHelper.addressShort(address);

  String get pickupPointLabel =>
      addressShort.isEmpty || addressShort == '—' ? '' : addressShort;
}

class MealLabelDishLine {
  final String name;
  final int quantity;

  const MealLabelDishLine({required this.name, required this.quantity});

  String get display => '$name x$quantity';
}

class MealLabelGroup {
  final String labelCode;
  final String orderId;
  final OrderStatus status;
  final String employeeName;
  final String department;
  final List<MealLabelDishLine> packages;
  final List<MealLabelDishLine> meats;
  final List<MealLabelDishLine> vegetables;
  final List<MealLabelDishLine> extras;
  final String remark;
  final bool extrasFollowOrder;
  final bool isLabelPrinted;
  final int labelPrintCount;
  final DateTime? labelPrintedAt;

  const MealLabelGroup({
    required this.labelCode,
    required this.orderId,
    required this.status,
    required this.employeeName,
    required this.department,
    this.packages = const [],
    this.meats = const [],
    this.vegetables = const [],
    this.extras = const [],
    this.remark = '',
    this.extrasFollowOrder = false,
    this.isLabelPrinted = false,
    this.labelPrintCount = 0,
    this.labelPrintedAt,
  });

  String get labelKey => '$orderId|$labelCode';

  String get primaryPackageName =>
      packages.isNotEmpty ? packages.first.name : '';

  MealLabelGroup copyWithPrintStatus({
    required bool isLabelPrinted,
    required int labelPrintCount,
    DateTime? labelPrintedAt,
  }) {
    return MealLabelGroup(
      labelCode: labelCode,
      orderId: orderId,
      status: status,
      employeeName: employeeName,
      department: department,
      packages: packages,
      meats: meats,
      vegetables: vegetables,
      extras: extras,
      remark: remark,
      extrasFollowOrder: extrasFollowOrder,
      isLabelPrinted: isLabelPrinted,
      labelPrintCount: labelPrintCount,
      labelPrintedAt: labelPrintedAt,
    );
  }

  int get totalQuantity =>
      packages.fold<int>(0, (s, i) => s + i.quantity) +
      meats.fold<int>(0, (s, i) => s + i.quantity) +
      vegetables.fold<int>(0, (s, i) => s + i.quantity) +
      extras.fold<int>(0, (s, i) => s + i.quantity);

  List<String> get displayLines {
    final lines = <String>['$employeeName｜$department'];
    if (packages.isNotEmpty) {
      lines.add('套餐：${packages.map((p) => p.display).join('、')}');
    }
    if (meats.isNotEmpty) {
      lines.add('荤菜：${meats.map((m) => m.display).join('、')}');
    }
    if (vegetables.isNotEmpty) {
      lines.add('素菜：${vegetables.map((v) => v.display).join('、')}');
    }
    if (extras.isNotEmpty) {
      final suffix = extrasFollowOrder ? '（随单）' : '';
      lines.add('加菜：${extras.map((e) => e.display).join('、')}$suffix');
    }
    return lines;
  }

  String get detailLine {
    final taste = remark.isEmpty ? '无' : remark;
    return '${displayLines.join('\n')}\n备注：$taste';
  }
}

class MealBatchSummary {
  final DateTime date;
  final MealType mealType;
  final String merchantId;
  final String merchantName;
  final List<Order> sourceOrders;
  final List<MealLabelGroup> labelGroups;
  final List<DishAggregate> dishTotals;
  final MealBatchCollectorInfo collectorInfo;
  final int totalPeople;
  final int totalPortions;
  final double totalAmount;
  final int pendingPeople;
  final MealBatchPhase phase;

  const MealBatchSummary({
    required this.date,
    required this.mealType,
    required this.merchantId,
    required this.merchantName,
    required this.sourceOrders,
    required this.labelGroups,
    required this.dishTotals,
    required this.collectorInfo,
    required this.totalPeople,
    required this.totalPortions,
    required this.totalAmount,
    required this.pendingPeople,
    required this.phase,
  });

  String get dateLabel =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String get title => '今日${mealType.label}';

  bool get isEmpty => labelGroups.isEmpty;

  /// 待商家确认（不含待支付）
  List<Order> get ordersAwaitingConfirm => sourceOrders
      .where((o) => MerchantOrderStatusRules.isAwaitingMerchantConfirm(o.status))
      .toList();

  List<Order> get ordersAccepted =>
      sourceOrders.where((o) => o.status == OrderStatus.accepted).toList();

  List<Order> get ordersDelivering =>
      sourceOrders.where((o) => o.status == OrderStatus.delivering).toList();

  List<Order> get ordersPendingPayment =>
      sourceOrders.where((o) => o.status == OrderStatus.pendingPayment).toList();

  /// 可打印标签的明细（排除待支付、已取消）
  List<MealLabelGroup> get printableLabelGroups => labelGroups
      .where((g) => MerchantOrderStatusRules.isPrintableLabelStatus(g.status))
      .toList();

  bool get hasConfirmableOrders => ordersAwaitingConfirm.isNotEmpty;

  bool get allActiveCompleted {
    final active = sourceOrders
        .where((o) => o.status != OrderStatus.cancelled)
        .toList();
    return active.isNotEmpty &&
        active.every((o) => o.status == OrderStatus.completed);
  }
}

class _MealBoxDraft {
  final String orderId;
  final OrderStatus status;
  final String employeeName;
  final String department;
  final String employeeKey;
  final String remark;
  final Map<String, int> packages;
  final Map<String, int> meats;
  final Map<String, int> vegetables;

  _MealBoxDraft({
    required this.orderId,
    required this.status,
    required this.employeeName,
    required this.department,
    required this.employeeKey,
    required this.remark,
    required this.packages,
    required this.meats,
    required this.vegetables,
  });
}

class MealBatchAggregator {
  MealBatchAggregator._();

  static const merchantSummaryMealTypes = [
    MealType.breakfast,
    MealType.lunch,
    MealType.dinner,
  ];

  static MealType merchantCurrentMealPeriod([DateTime? now]) {
    final t = currentMealPeriod(now);
    if (merchantSummaryMealTypes.contains(t)) return t;
    return MealType.lunch;
  }

  static int pendingCountFor({
    required List<Order> orders,
    required DateTime date,
    required MealType mealType,
    required String merchantId,
  }) {
    return orders
        .where(
          (o) =>
              o.merchantId == merchantId &&
              o.status != OrderStatus.cancelled &&
              OrderTimeUtil.isSameShanghaiDay(o.createdAt, date) &&
              _orderMatchesMeal(o, mealType) &&
              MerchantOrderStatusRules.isAwaitingMerchantConfirm(o.status),
        )
        .length;
  }

  static MealType currentMealPeriod([DateTime? now]) {
    final n = now ?? DateTime.now();
    final mins = n.hour * 60 + n.minute;
    if (mins <= 7 * 60 + 30) return MealType.breakfast;
    if (mins <= 9 * 60 + 30) return MealType.lunch;
    if (mins <= 15 * 60) return MealType.dinner;
    if (mins <= 17 * 60 + 30) return MealType.overtime;
    return MealType.dinner;
  }

  static String _groupKey(String name, String dept) => '$name|$dept';

  static MealBatchCollectorInfo _resolveCollector(List<Order> batchOrders) {
    final collectors =
        batchOrders.where((o) => o.isMealCollector).toList();
    if (collectors.isEmpty) {
      final legacy = batchOrders
          .where(
            (o) =>
                o.collectorAddress.isNotEmpty ||
                (o.address.isNotEmpty && o.phone.isNotEmpty),
          )
          .toList();
      if (legacy.isEmpty) return MealBatchCollectorInfo.empty();
      final first = legacy.first;
      return MealBatchCollectorInfo(
        name: first.collectorName.isNotEmpty
            ? first.collectorName
            : first.customerName,
        phone: first.collectorPhone.isNotEmpty
            ? first.collectorPhone
            : first.phone,
        address: first.collectorAddress.isNotEmpty
            ? first.collectorAddress
            : first.address,
        poiName: first.collectorPoiName,
        addressText: first.collectorAddressText.isNotEmpty
            ? first.collectorAddressText
            : first.collectorAddress,
        hasCollector: true,
        multipleCollectors: legacy.length > 1,
      );
    }
    final first = collectors.first;
    return MealBatchCollectorInfo(
      name: first.collectorName.isNotEmpty
          ? first.collectorName
          : first.customerName,
      phone: first.collectorPhone.isNotEmpty
          ? first.collectorPhone
          : first.phone,
      address: first.collectorAddress.isNotEmpty
          ? first.collectorAddress
          : first.address,
      poiName: first.collectorPoiName,
      addressText: first.collectorAddressText.isNotEmpty
          ? first.collectorAddressText
          : first.collectorAddress,
      hasCollector: true,
      multipleCollectors: collectors.length > 1,
    );
  }

  static MealBatchSummary build({
    required List<Order> orders,
    required DateTime date,
    required MealType mealType,
    required String merchantId,
    required String merchantName,
  }) {
    final dayOrders = orders
        .where((o) =>
            o.merchantId == merchantId &&
            o.status != OrderStatus.cancelled &&
            OrderTimeUtil.isSameShanghaiDay(o.createdAt, date))
        .toList();

    final batchOrders = dayOrders
        .where((o) =>
            _orderMatchesMeal(o, mealType) &&
            MerchantOrderStatusRules.isVisibleInMerchantSummary(o.status))
        .toList();

    final dishMap = <String, int>{};
    final boxDrafts = <_MealBoxDraft>[];
    final extrasByEmployee = <String, Map<String, int>>{};

    for (final order in batchOrders) {
      final dept = EmployeeInfoHelper.departmentDisplay(
        customerCompany: order.customerCompany,
        address: order.address,
      );
      final empKey = _groupKey(order.customerName, dept);
      final boxes = _extractMealBoxes(order, mealType, dishMap);
      for (final box in boxes) {
        boxDrafts.add(
          _MealBoxDraft(
            orderId: order.id,
            status: order.status,
            employeeName: order.customerName,
            department: dept,
            employeeKey: empKey,
            remark: order.remark,
            packages: box.packages,
            meats: box.meats,
            vegetables: box.vegetables,
          ),
        );
      }
      final empExtras = extrasByEmployee.putIfAbsent(empKey, () => {});
      _collectOrderExtras(order, mealType, empExtras, dishMap);
    }

    final firstBoxIndexByEmployee = <String, int>{};
    for (var i = 0; i < boxDrafts.length; i++) {
      firstBoxIndexByEmployee.putIfAbsent(boxDrafts[i].employeeKey, () => i);
    }

    var labelSeq = 0;
    final labelGroups = boxDrafts.asMap().entries.map((entry) {
      labelSeq++;
      final d = entry.value;
      final isFirst = firstBoxIndexByEmployee[d.employeeKey] == entry.key;
      final extrasMap =
          isFirst ? (extrasByEmployee[d.employeeKey] ?? {}) : <String, int>{};
      return MealLabelGroup(
        labelCode: labelSeq.toString().padLeft(3, '0'),
        orderId: d.orderId,
        status: d.status,
        employeeName: d.employeeName,
        department: d.department,
        packages: _linesFromMap(d.packages),
        meats: _linesFromMap(d.meats),
        vegetables: _linesFromMap(d.vegetables),
        extras: _linesFromMap(extrasMap),
        remark: d.remark,
        extrasFollowOrder: isFirst && extrasMap.isNotEmpty,
      );
    }).toList();

    final people = batchOrders
        .map((o) => o.customerName)
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;

    final pendingPeople = batchOrders
        .where((o) =>
            MerchantOrderStatusRules.isAwaitingMerchantConfirm(o.status))
        .map((o) => o.customerName)
        .toSet()
        .length;

    final portions =
        labelGroups.fold<int>(0, (s, g) => s + g.totalQuantity);
    final amount = batchOrders.fold<double>(
      0,
      (s, o) => s + o.displayAmount,
    );

    final dishTotals = dishMap.entries
        .map((e) => DishAggregate(dishName: e.key, quantity: e.value))
        .toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    return MealBatchSummary(
      date: date,
      mealType: mealType,
      merchantId: merchantId,
      merchantName: merchantName,
      sourceOrders: batchOrders,
      labelGroups: labelGroups,
      dishTotals: dishTotals,
      collectorInfo: _resolveCollector(batchOrders),
      totalPeople: people,
      totalPortions: portions,
      totalAmount: amount,
      pendingPeople: pendingPeople,
      phase: _phase(batchOrders),
    );
  }

  static MealBatchPhase _phase(List<Order> orders) {
    final active =
        orders.where((o) => o.status != OrderStatus.cancelled).toList();
    if (active.isEmpty) return MealBatchPhase.empty;
    if (active.any(
        (o) => MerchantOrderStatusRules.isAwaitingMerchantConfirm(o.status))) {
      return MealBatchPhase.pending;
    }
    if (active.every((o) => o.status == OrderStatus.completed)) {
      return MealBatchPhase.completed;
    }
    if (active.any((o) => o.status == OrderStatus.delivering)) {
      return MealBatchPhase.delivering;
    }
    if (active.any((o) => o.status == OrderStatus.accepted)) {
      return MealBatchPhase.preparing;
    }
    return MealBatchPhase.empty;
  }

  static bool _selectedItemMatchesMeal(
    OrderSelectedItem si,
    MealType mealType,
  ) =>
      si.mealType == null ||
      si.mealType!.isEmpty ||
      si.mealType == mealType.name;

  static bool _hasStructuredPackageData(Order order) =>
      order.isPackageOrder ||
      order.selectedItems.isNotEmpty ||
      order.extraItems.isNotEmpty ||
      (order.packageName?.trim().isNotEmpty ?? false);

  static bool _orderMatchesMeal(Order o, MealType mealType) {
    if (o.items.any((i) => i.dish.mealType == mealType)) return true;
    if (!_hasStructuredPackageData(o)) return false;

    if (o.selectedItems.any((si) => _selectedItemMatchesMeal(si, mealType))) {
      return true;
    }
    if (o.selectedItems.isEmpty &&
        (o.packageName?.trim().isNotEmpty ?? false)) {
      return o.items.any((i) => i.dish.mealType == mealType);
    }
    return false;
  }

  static List<MealLabelDishLine> _linesFromMap(Map<String, int> map) =>
      map.entries
          .map((e) => MealLabelDishLine(name: e.key, quantity: e.value))
          .toList();

  static void _collectOrderExtras(
    Order order,
    MealType mealType,
    Map<String, int> target,
    Map<String, int> dishMap,
  ) {
    void bumpDish(String name, int qty) {
      dishMap[name] = (dishMap[name] ?? 0) + qty;
    }

    for (final ex in order.extraItems) {
      target[ex.name] = (target[ex.name] ?? 0) + ex.quantity;
      bumpDish(ex.name, ex.quantity);
    }
    if (order.extraItems.isNotEmpty) return;
    for (final item in order.items) {
      if (item.dish.mealType != mealType) continue;
      final name = item.dish.name;
      if (name.startsWith('【加菜】')) {
        final extra = name.replaceFirst('【加菜】', '');
        target[extra] = (target[extra] ?? 0) + item.quantity;
        bumpDish(extra, item.quantity);
      }
    }
  }

  static List<({Map<String, int> packages, Map<String, int> meats, Map<String, int> vegetables})>
      _extractMealBoxes(Order order, MealType mealType, Map<String, int> dishMap) {
    void bumpDish(String name, int qty) {
      dishMap[name] = (dishMap[name] ?? 0) + qty;
    }

    final boxes = <({Map<String, int> packages, Map<String, int> meats, Map<String, int> vegetables})>[];

    if (_hasStructuredPackageData(order)) {
      final packages = <String, int>{};
      final meats = <String, int>{};
      final vegetables = <String, int>{};
      final pkgLabel = order.packageName?.trim() ?? '';
      if (pkgLabel.isNotEmpty) {
        packages[pkgLabel] = 1;
        bumpDish(pkgLabel, 1);
      }
      for (final si in order.selectedItems) {
        if (!_selectedItemMatchesMeal(si, mealType)) continue;
        switch (si.category) {
          case 'meat':
            meats[si.name] = (meats[si.name] ?? 0) + 1;
            break;
          case 'vegetable':
            vegetables[si.name] = (vegetables[si.name] ?? 0) + 1;
            break;
          default:
            if (si.category != 'staple' &&
                si.category != 'soup' &&
                si.category != 'drink') {
              vegetables[si.name] = (vegetables[si.name] ?? 0) + 1;
            }
        }
        bumpDish(si.name, 1);
      }
      if (packages.isNotEmpty || meats.isNotEmpty || vegetables.isNotEmpty) {
        boxes.add((packages: packages, meats: meats, vegetables: vegetables));
      }
      return boxes;
    }

    final looseVegetables = <String, int>{};
    for (final item in order.items) {
      final name = item.dish.name;
      if (name.startsWith('【套餐】')) {
        final pkg = name.replaceFirst('【套餐】', '');
        for (var i = 0; i < item.quantity; i++) {
          boxes.add((
            packages: {pkg: 1},
            meats: <String, int>{},
            vegetables: <String, int>{},
          ));
          bumpDish(pkg, 1);
        }
      } else if (!name.startsWith('【加菜】') &&
          item.dish.mealType == mealType) {
        looseVegetables[name] =
            (looseVegetables[name] ?? 0) + item.quantity;
        bumpDish(name, item.quantity);
      }
    }

    if (boxes.isEmpty && looseVegetables.isNotEmpty) {
      boxes.add((
        packages: <String, int>{},
        meats: <String, int>{},
        vegetables: looseVegetables,
      ));
    } else if (boxes.isNotEmpty && looseVegetables.isNotEmpty) {
      final first = boxes.first;
      final merged = Map<String, int>.from(first.vegetables);
      looseVegetables.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
      boxes[0] = (
        packages: first.packages,
        meats: first.meats,
        vegetables: merged,
      );
    }

    return boxes;
  }
}
