import '../models/cart_item_model.dart';
import '../models/dish_model.dart';
import '../models/order_model.dart';
import 'mock_data.dart';

/// 商家端首次启动用的演示订单（企业订餐风格）
List<Order> seedOrders() {
  final now = DateTime.now();
  final m = MockData.currentMerchant;

  Dish d(String id, String name, double price, MealType type) => Dish(
        id: 'seed_$id',
        merchantId: m.id,
        name: name,
        image: 'dish',
        description: '',
        price: price,
        mealType: type,
        tags: const [],
      );

  return [
    Order(
      id: '20240516001',
      merchantId: m.id,
      merchantName: m.name,
      customerName: '张三',
      customerCompany: '行政部',
      items: [
        CartItem(dish: d('a1', '黄焖鸡米饭', 16, MealType.lunch)),
        CartItem(dish: d('a2', '番茄炒蛋', 8, MealType.lunch)),
      ],
      deliveryType: DeliveryType.delivery,
      address: '',
      phone: '',
      remark: '少辣',
      goodsAmount: 24,
      deliveryFee: 3,
      totalAmount: 27,
      status: OrderStatus.pendingMerchantConfirm,
      paymentScreenshot: 'mock',
      createdAt: now.subtract(const Duration(minutes: 25)),
      isMealCollector: true,
      collectorName: '张三',
      collectorPhone: '13800000000',
      collectorAddress:
          '科技园A区 · 综合楼A座 · 5楼\n行政部 / 前台\n备注：前台自取',
    ),
    Order(
      id: '20240516002',
      merchantId: m.id,
      merchantName: m.name,
      customerName: '李四',
      customerCompany: '销售部',
      items: [
        CartItem(dish: d('b1', '番茄炒蛋', 8, MealType.lunch)),
        CartItem(dish: d('b2', '青椒牛肉丝', 18, MealType.lunch)),
      ],
      deliveryType: DeliveryType.delivery,
      address: '',
      phone: '',
      remark: '不要香菜',
      goodsAmount: 26,
      deliveryFee: 3,
      totalAmount: 29,
      status: OrderStatus.accepted,
      paymentScreenshot: 'mock',
      createdAt: now.subtract(const Duration(hours: 1, minutes: 15)),
    ),
    Order(
      id: '20240516003',
      merchantId: m.id,
      merchantName: m.name,
      customerName: '王五',
      customerCompany: '生产部',
      items: [
        CartItem(dish: d('c1', '黄焖鸡米饭', 16, MealType.lunch)),
        CartItem(dish: d('c2', '青椒牛肉丝', 18, MealType.lunch)),
      ],
      deliveryType: DeliveryType.delivery,
      address: '',
      phone: '',
      remark: '',
      goodsAmount: 34,
      deliveryFee: 0,
      totalAmount: 34,
      status: OrderStatus.completed,
      paymentScreenshot: 'mock',
      createdAt: now.subtract(const Duration(hours: 2, minutes: 50)),
    ),
  ];
}