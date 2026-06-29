import 'dish_model.dart';

/// GET /api/merchants/:id/package-order-data 聚合响应
class PackageOrderData {
  final String merchantId;
  final String merchantName;
  final MealType mealType;
  final List<PackageOrderPackage> packages;
  final List<PackageOrderDish> meat;
  final List<PackageOrderDish> vegetable;
  final List<PackageOrderExtraDish> extra;

  const PackageOrderData({
    required this.merchantId,
    required this.merchantName,
    required this.mealType,
    required this.packages,
    required this.meat,
    required this.vegetable,
    required this.extra,
  });

  factory PackageOrderData.fromJson(Map<String, dynamic> json) {
    final merchant = (json['merchant'] as Map?)?.cast<String, dynamic>() ?? {};
    final mealTypeRaw = json['mealType'] as String? ?? 'lunch';
    final mealType = MealType.values.firstWhere(
      (m) => m.name == mealTypeRaw,
      orElse: () => MealType.lunch,
    );
    final dishes =
        (json['dishes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final packagesRaw = (json['packages'] as List?) ?? const [];

    return PackageOrderData(
      merchantId: (merchant['id'] as String?) ?? '',
      merchantName: (merchant['name'] as String?) ?? '',
      mealType: mealType,
      packages: packagesRaw
          .map((e) => PackageOrderPackage.fromJson(
                (e as Map).cast<String, dynamic>(),
              ))
          .toList(),
      meat: _parseDishList(dishes['meat']),
      vegetable: _parseDishList(dishes['vegetable']),
      extra: _parseExtraList(dishes['extra']),
    );
  }

  static List<PackageOrderDish> _parseDishList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => PackageOrderDish.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static List<PackageOrderExtraDish> _parseExtraList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) =>
            PackageOrderExtraDish.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}

class PackageOrderPackage {
  final String id;
  final String name;
  final double basePrice;
  final int meatCount;
  final int vegetableCount;
  final List<MealType> mealTypes;
  final bool isEnabled;
  final String description;

  const PackageOrderPackage({
    required this.id,
    required this.name,
    required this.basePrice,
    required this.meatCount,
    required this.vegetableCount,
    required this.mealTypes,
    required this.isEnabled,
    this.description = '',
  });

  factory PackageOrderPackage.fromJson(Map<String, dynamic> json) {
    final mealTypesRaw = (json['mealTypes'] as List?) ?? const [];
    final mealTypes = <MealType>[];
    for (final v in mealTypesRaw) {
      final m = MealType.values.firstWhere(
        (t) => t.name == v,
        orElse: () => MealType.lunch,
      );
      if (!mealTypes.contains(m)) mealTypes.add(m);
    }
    return PackageOrderPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      basePrice: ((json['basePrice'] as num?) ?? 0).toDouble(),
      meatCount: ((json['meatCount'] as num?) ?? 0).toInt(),
      vegetableCount: ((json['vegetableCount'] as num?) ?? 0).toInt(),
      mealTypes: mealTypes,
      isEnabled: (json['isEnabled'] as bool?) ?? true,
      description: (json['description'] as String?) ?? '',
    );
  }
}

class PackageOrderDish {
  final String id;
  final String name;
  final String imageUrl;
  final String description;

  const PackageOrderDish({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.description,
  });

  factory PackageOrderDish.fromJson(Map<String, dynamic> json) {
    return PackageOrderDish(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: (json['imageUrl'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }
}

class PackageOrderExtraDish {
  final String id;
  final String name;
  final String imageUrl;
  final double extraPrice;

  const PackageOrderExtraDish({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.extraPrice,
  });

  factory PackageOrderExtraDish.fromJson(Map<String, dynamic> json) {
    return PackageOrderExtraDish(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: (json['imageUrl'] as String?) ?? '',
      extraPrice: ((json['extraPrice'] as num?) ?? 0).toDouble(),
    );
  }
}
