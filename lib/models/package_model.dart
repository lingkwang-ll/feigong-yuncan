import 'dish_model.dart';

/// 套餐规则：荤/素/主食/汤/饮品 各需选择多少
class PackageRules {
  final int meat;
  final int vegetable;
  final int staple;
  final int soup;
  final int drink;

  const PackageRules({
    this.meat = 0,
    this.vegetable = 0,
    this.staple = 0,
    this.soup = 0,
    this.drink = 0,
  });

  int get total => meat + vegetable + staple + soup + drink;

  int requiredFor(DishCategory category) {
    switch (category) {
      case DishCategory.meat:
        return meat;
      case DishCategory.vegetable:
        return vegetable;
      case DishCategory.staple:
        return staple;
      case DishCategory.soup:
        return soup;
      case DishCategory.drink:
        return drink;
      default:
        return 0;
    }
  }

  Map<String, dynamic> toJson() => {
        if (meat > 0) 'meat': meat,
        if (vegetable > 0) 'vegetable': vegetable,
        if (staple > 0) 'staple': staple,
        if (soup > 0) 'soup': soup,
        if (drink > 0) 'drink': drink,
      };

  factory PackageRules.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PackageRules();
    int read(String k) {
      final v = json[k];
      if (v is num) return v.toInt();
      return 0;
    }

    return PackageRules(
      meat: read('meat'),
      vegetable: read('vegetable'),
      staple: read('staple'),
      soup: read('soup'),
      drink: read('drink'),
    );
  }
}

class MealPackage {
  final String id;
  final String merchantId;
  final String name;
  final String description;
  final double basePrice;
  final List<MealType> mealTypes;
  final PackageRules rules;
  final bool allowExtra;
  final List<String> extraDishIds;
  final bool isEnabled;

  const MealPackage({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.mealTypes,
    required this.rules,
    required this.allowExtra,
    required this.extraDishIds,
    required this.isEnabled,
  });

  /// 套餐是否适用于某个餐段；mealTypes 为空表示全部餐段可用。
  bool appliesTo(MealType mealType) {
    if (mealTypes.isEmpty) return true;
    return mealTypes.contains(mealType);
  }

  factory MealPackage.fromJson(Map<String, dynamic> json) {
    final mealTypesRaw = (json['mealTypes'] as List?) ?? const [];
    final mealTypes = <MealType>[];
    for (final v in mealTypesRaw) {
      final m = MealType.values.firstWhere(
        (t) => t.name == v,
        orElse: () => MealType.lunch,
      );
      if (!mealTypes.contains(m)) mealTypes.add(m);
    }
    return MealPackage(
      id: json['id'] as String,
      merchantId: json['merchantId'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      basePrice: ((json['basePrice'] as num?) ?? 0).toDouble(),
      mealTypes: mealTypes,
      rules: PackageRules.fromJson(json['rules'] as Map<String, dynamic>?),
      allowExtra: (json['allowExtra'] as bool?) ?? true,
      extraDishIds: ((json['extraDishIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      isEnabled: (json['isEnabled'] as bool?) ?? true,
    );
  }
}
