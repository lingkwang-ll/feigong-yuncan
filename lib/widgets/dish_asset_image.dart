import 'package:flutter/material.dart';

/// 菜品名 → 本地 PNG 资源映射
///
/// 严格按用户要求统一改用 `assets/images/ui/dish_*.png` 命名：
///   香煎鸡胸肉饭 → dish_chicken.png
///   番茄牛腩饭   → dish_beef.png
///   清炒时蔬     → dish_vegetable.png
///   玉米排骨汤   → dish_soup.png
///   杂粮饭       → dish_rice.png
///   原味豆浆     → dish_soymilk.png
class DishAsset {
  /// 与 pubspec.yaml `assets/images/ui/` 一致
  static const String _base = 'assets/images/ui';

  static const Map<String, String> _exactMap = {
    // 来自参考图 02_employee_home.png 的 6 个核心菜品
    '香煎鸡胸肉饭': 'dish_chicken.png',
    '番茄牛腩饭': 'dish_beef.png',
    '清炒时蔬': 'dish_vegetable.png',
    '玉米排骨汤': 'dish_soup.png',
    '杂粮饭': 'dish_rice.png',
    '原味豆浆': 'dish_soymilk.png',
  };

  // 关键字兜底（在不精确匹配时按词命中）
  static const List<MapEntry<String, String>> _keywordMap = [
    MapEntry('豆浆', 'dish_soymilk.png'),
    MapEntry('鸡胸', 'dish_chicken.png'),
    MapEntry('鸡丁', 'dish_chicken.png'),
    MapEntry('鸡米', 'dish_chicken.png'),
    MapEntry('黄焖鸡', 'dish_chicken.png'),
    MapEntry('牛腩', 'dish_beef.png'),
    MapEntry('牛肉', 'dish_beef.png'),
    MapEntry('时蔬', 'dish_vegetable.png'),
    MapEntry('青菜', 'dish_vegetable.png'),
    MapEntry('炒蔬', 'dish_vegetable.png'),
    MapEntry('青椒', 'dish_vegetable.png'),
    MapEntry('排骨汤', 'dish_soup.png'),
    MapEntry('排骨', 'dish_soup.png'),
    MapEntry('冬瓜汤', 'dish_soup.png'),
    MapEntry('杂粮', 'dish_rice.png'),
    MapEntry('米饭', 'dish_rice.png'),
    MapEntry('饭团', 'dish_rice.png'),
  ];

  /// 返回完整 asset path，如 `assets/images/ui/dish_chicken.png`；
  /// 没有匹配的菜品返回 null（调用方应回退到通用占位）。
  static String? resolveByName(String? name) {
    if (name == null || name.isEmpty) return null;

    final exact = _exactMap[name];
    if (exact != null) return '$_base/$exact';

    for (final e in _keywordMap) {
      if (name.contains(e.key)) return '$_base/${e.value}';
    }
    return null;
  }
}

/// 菜品图组件
///
/// 渲染优先级（从高到低）：
/// 1. 远程图片：`http(s)://` 或 `/uploads/...`
/// 2. 显式指定的 `assetPath`
/// 3. 通过 [dishName] 查找本地静态资源
/// 4. 通用空盘占位（纯色 + 弧线，不使用 emoji）
class DishAssetImage extends StatelessWidget {
  final String? imageUrl;
  final String? dishName;
  final String? assetPath;
  final double width;
  final double height;
  final double radius;

  const DishAssetImage({
    super.key,
    this.imageUrl,
    this.dishName,
    this.assetPath,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  bool get _isRemote {
    final u = imageUrl;
    if (u == null || u.isEmpty) return false;
    return u.startsWith('http://') ||
        u.startsWith('https://') ||
        u.startsWith('/uploads/');
  }

  @override
  Widget build(BuildContext context) {
    if (_isRemote) {
      // 远端：尝试加载；失败时回退到本地资源 / 占位
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          imageUrl!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _localOrFallback(),
        ),
      );
    }
    return _localOrFallback();
  }

  Widget _localOrFallback() {
    final p = assetPath ?? DishAsset.resolveByName(dishName);
    if (p != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          p,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _EmptyPlatePlaceholder(
            width: width,
            height: height,
            radius: radius,
          ),
        ),
      );
    }
    return _EmptyPlatePlaceholder(
      width: width,
      height: height,
      radius: radius,
    );
  }
}

/// 通用菜品图占位：浅色背景 + 写实“空白瓷盘”
///
/// 没有任何 emoji；保留干净的中性视觉，免得被误认为是设计风格。
class _EmptyPlatePlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _EmptyPlatePlaceholder({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECDF),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: SizedBox(
          width: width * 0.62,
          height: width * 0.62,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFFAF7EF),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

