import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/cart_item_model.dart';
import '../models/dish_model.dart';
import '../models/merchant_model.dart';

/// 购物车状态
///
/// 规则：一次只能包含同一商家的餐；切换商家需确认后清空。
class CartState extends ChangeNotifier {
  Merchant? _merchant;
  MealType? _mealType;
  final List<CartItem> _items = [];

  Merchant? get merchant => _merchant;
  MealType? get mealType => _mealType;
  List<CartItem> get items => List.unmodifiable(_items);

  int get totalQuantity =>
      _items.fold(0, (sum, item) => sum + item.quantity);

  double get goodsAmount =>
      _items.fold(0.0, (sum, item) => sum + item.subtotal);

  bool get isEmpty => _items.isEmpty;

  int quantityOf(String dishId) {
    final found = _items.where((e) => e.dish.id == dishId).toList();
    if (found.isEmpty) return 0;
    return found.first.quantity;
  }

  /// 切换商家时如购物车非空，弹出确认；返回 false 表示用户取消。
  Future<bool> ensureMerchant(
    BuildContext context,
    Merchant merchant,
  ) async {
    if (_merchant != null &&
        _merchant!.id != merchant.id &&
        _items.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('切换商家'),
          content: const Text('切换商家会清空当前购物车，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (ok != true) return false;
      clear();
    }
    _merchant = merchant;
    return true;
  }

  void addDish(Dish dish, Merchant merchant) {
    if (_merchant != null && _merchant!.id != merchant.id) {
      _items.clear();
    }
    _merchant = merchant;
    _mealType ??= dish.mealType;
    final existing = _items.where((e) => e.dish.id == dish.id).toList();
    if (existing.isEmpty) {
      _items.add(CartItem(dish: dish));
    } else {
      existing.first.quantity += 1;
    }
    notifyListeners();
  }

  /// 带商家冲突确认的加购
  Future<bool> addDishWithCheck(
    BuildContext context,
    Dish dish,
    Merchant merchant,
  ) async {
    final ok = await ensureMerchant(context, merchant);
    if (!ok) return false;
    addDish(dish, merchant);
    return true;
  }

  /// 再次下单：批量加入原单点菜品
  Future<bool> addDishesFromOrder({
    required BuildContext context,
    required Merchant merchant,
    required List<CartItem> items,
  }) async {
    if (items.isEmpty) return false;
    final ok = await ensureMerchant(context, merchant);
    if (!ok) return false;
    _merchant = merchant;
    _mealType = items.first.dish.mealType;
    _items.clear();
    for (final src in items) {
      final existing = _items.where((e) => e.dish.id == src.dish.id).toList();
      if (existing.isEmpty) {
        _items.add(CartItem(dish: src.dish, quantity: src.quantity));
      } else {
        existing.first.quantity += src.quantity;
      }
    }
    notifyListeners();
    return true;
  }

  void removeOne(Dish dish) {
    final idx = _items.indexWhere((e) => e.dish.id == dish.id);
    if (idx < 0) return;
    final item = _items[idx];
    if (item.quantity <= 1) {
      _items.removeAt(idx);
    } else {
      item.quantity -= 1;
    }
    if (_items.isEmpty) _merchant = null;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _merchant = null;
    _mealType = null;
    notifyListeners();
  }
}
