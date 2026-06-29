import 'dish_model.dart';

class CartItem {
  final Dish dish;
  int quantity;

  CartItem({required this.dish, this.quantity = 1});

  double get subtotal => dish.price * quantity;

  Map<String, dynamic> toJson() => {
        'dish': dish.toJson(),
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        dish: Dish.fromJson(json['dish'] as Map<String, dynamic>),
        quantity: (json['quantity'] as num).toInt(),
      );
}
