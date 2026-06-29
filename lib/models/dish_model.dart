enum MealType { breakfast, lunch, dinner, overtime }

/// 可上架/订餐展示的餐段（不含加班餐；加班餐仅用于企业代付名单）
const kOrderMealTypes = <MealType>[
  MealType.breakfast,
  MealType.lunch,
  MealType.dinner,
];

extension MealTypeOrdering on MealType {
  bool get isOrderMealType => kOrderMealTypes.contains(this);

  /// 历史 overtime 等不可展示餐段在编辑时回退
  MealType get normalizedForOrdering =>
      isOrderMealType ? this : MealType.lunch;
}

extension MealTypeLabel on MealType {
  String get label {
    switch (this) {
      case MealType.breakfast:
        return '早餐';
      case MealType.lunch:
        return '中餐';
      case MealType.dinner:
        return '晚餐';
      case MealType.overtime:
        return '加班餐';
    }
  }

  String get cutoff {
    switch (this) {
      case MealType.breakfast:
        return '07:30截止';
      case MealType.lunch:
        return '09:30截止';
      case MealType.dinner:
        return '15:00截止';
      case MealType.overtime:
        return '17:30截止';
    }
  }

  /// 订餐截止时间 HH:mm
  String get deadlineAt {
    switch (this) {
      case MealType.breakfast:
        return '07:30';
      case MealType.lunch:
        return '09:30';
      case MealType.dinner:
        return '15:00';
      case MealType.overtime:
        return '17:30';
    }
  }
}

/// 套餐体系菜品分类：
/// - `''`：历史菜品未分类（不影响旧逻辑）
/// - meat/vegetable/staple/soup/drink：套餐选菜可用
/// - extra：加菜
enum DishCategory { none, meat, vegetable, staple, soup, drink, extra }

extension DishCategoryX on DishCategory {
  String get apiValue {
    switch (this) {
      case DishCategory.none:
        return '';
      case DishCategory.meat:
        return 'meat';
      case DishCategory.vegetable:
        return 'vegetable';
      case DishCategory.staple:
        return 'staple';
      case DishCategory.soup:
        return 'soup';
      case DishCategory.drink:
        return 'drink';
      case DishCategory.extra:
        return 'extra';
    }
  }

  String get label {
    switch (this) {
      case DishCategory.none:
        return '';
      case DishCategory.meat:
        return '荤菜';
      case DishCategory.vegetable:
        return '素菜';
      case DishCategory.staple:
        return '主食';
      case DishCategory.soup:
        return '汤品';
      case DishCategory.drink:
        return '饮品';
      case DishCategory.extra:
        return '加菜';
    }
  }

  static DishCategory parse(String? raw) {
    final v = (raw ?? '').trim();
    switch (v) {
      case 'meat':
      case '荤菜':
      case '荤':
        return DishCategory.meat;
      case 'vegetable':
      case '素菜':
      case '素':
        return DishCategory.vegetable;
      case 'staple':
      case '主食':
        return DishCategory.staple;
      case 'soup':
      case '汤品':
      case '汤':
        return DishCategory.soup;
      case 'drink':
      case '饮品':
        return DishCategory.drink;
      case 'extra':
      case '加菜':
        return DishCategory.extra;
      default:
        return DishCategory.none;
    }
  }
}

class Dish {
  final String id;
  final String merchantId;
  final String name;
  final String image; // 占位图标识
  final String description;
  final double price;
  final MealType mealType;
  final List<String> tags;
  final bool isAvailable;
  final bool isSoldOut;
  // 套餐体系扩展字段
  final DishCategory category;
  final double extraPrice;
  final List<MealType> mealTypes;

  const Dish({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.image,
    required this.description,
    required this.price,
    required this.mealType,
    required this.tags,
    this.isAvailable = true,
    this.isSoldOut = false,
    this.category = DishCategory.none,
    this.extraPrice = 0,
    this.mealTypes = const [],
  });

  Dish copyWith({
    String? name,
    double? price,
    String? description,
    MealType? mealType,
    List<String>? tags,
    bool? isAvailable,
    bool? isSoldOut,
    String? image,
    DishCategory? category,
    double? extraPrice,
    List<MealType>? mealTypes,
  }) {
    return Dish(
      id: id,
      merchantId: merchantId,
      name: name ?? this.name,
      image: image ?? this.image,
      description: description ?? this.description,
      price: price ?? this.price,
      mealType: mealType ?? this.mealType,
      tags: tags ?? this.tags,
      isAvailable: isAvailable ?? this.isAvailable,
      isSoldOut: isSoldOut ?? this.isSoldOut,
      category: category ?? this.category,
      extraPrice: extraPrice ?? this.extraPrice,
      mealTypes: mealTypes ?? this.mealTypes,
    );
  }

  /// 是否适用于指定餐段（优先 `mealTypes`，兼容旧字段 `mealType`）。
  bool matchesMealType(MealType type) {
    if (mealTypes.isNotEmpty) return mealTypes.contains(type);
    return mealType == type;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchantId': merchantId,
        'name': name,
        'image': image,
        'description': description,
        'price': price,
        'mealType': mealType.name,
        'tags': tags,
        'isAvailable': isAvailable,
        'isSoldOut': isSoldOut,
        'category': category.apiValue,
        'extraPrice': extraPrice,
        'mealTypes': mealTypes.map((m) => m.name).toList(),
      };

  factory Dish.fromJson(Map<String, dynamic> json) {
    final mealTypesRaw = (json['mealTypes'] as List?) ?? const [];
    final mealTypes = <MealType>[];
    for (final v in mealTypesRaw) {
      final m = MealType.values.firstWhere(
        (t) => t.name == v,
        orElse: () => MealType.lunch,
      );
      if (!mealTypes.contains(m)) mealTypes.add(m);
    }
    return Dish(
      id: json['id'] as String,
      merchantId: json['merchantId'] as String,
      name: json['name'] as String,
      image: (json['image'] as String?) ?? 'dish',
      description: (json['description'] as String?) ?? '',
      price: ((json['price'] as num?) ?? 0).toDouble(),
      mealType: MealType.values.firstWhere(
        (t) => t.name == json['mealType'],
        orElse: () => MealType.lunch,
      ),
      tags: ((json['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      isAvailable: (json['isAvailable'] as bool?) ?? true,
      isSoldOut: (json['isSoldOut'] as bool?) ?? false,
      category: DishCategoryX.parse(json['category'] as String?),
      extraPrice: ((json['extraPrice'] as num?) ?? 0).toDouble(),
      mealTypes: mealTypes,
    );
  }
}
