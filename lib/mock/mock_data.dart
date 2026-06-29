import '../models/dish_model.dart';
import '../models/merchant_model.dart';
import '../models/user_model.dart';

/// 本地 Mock 数据集合
class MockData {
  // 默认员工与商家
  static const User employeeUser = User(
    id: 'u_emp_1',
    name: '张三',
    phone: '138 1234 5678',
    role: UserRole.employee,
  );

  static const User merchantUser = User(
    id: 'u_mer_1',
    name: '绿健食堂',
    phone: '138 8888 0001',
    role: UserRole.merchant,
  );

  /// 附近商家列表（员工端首页左侧）
  static const List<Merchant> merchants = [
    Merchant(
      id: 'm_1',
      name: '绿禾餐饮',
      logo: 'logo',
      coverImage: 'cover',
      distance: 120,
      rating: 4.8,
      monthSold: 1288,
      hygieneGrade: 'A',
      isOpen: true,
      address: '科技园 A 区 1 栋',
      paymentQrCode: 'qr',
      deliveryFee: 3.0,
    ),
    Merchant(
      id: 'm_2',
      name: '食光小厨',
      logo: 'logo',
      coverImage: 'cover',
      distance: 180,
      rating: 4.7,
      monthSold: 980,
      hygieneGrade: 'A',
      isOpen: true,
      address: '科技园 A 区 3 栋',
      paymentQrCode: 'qr',
      deliveryFee: 3.0,
    ),
    Merchant(
      id: 'm_3',
      name: '轻食工坊',
      logo: 'logo',
      coverImage: 'cover',
      distance: 210,
      rating: 4.6,
      monthSold: 720,
      hygieneGrade: 'A',
      isOpen: true,
      address: '科技园 B 区 2 栋',
      paymentQrCode: 'qr',
      deliveryFee: 3.0,
    ),
    Merchant(
      id: 'm_4',
      name: '家常味道',
      logo: 'logo',
      coverImage: 'cover',
      distance: 260,
      rating: 4.8,
      monthSold: 1500,
      hygieneGrade: 'A',
      isOpen: true,
      address: '科技园 B 区 5 栋',
      paymentQrCode: 'qr',
      deliveryFee: 3.0,
    ),
  ];

  /// 商家端默认登录的商家（绿健食堂）
  static const Merchant currentMerchant = Merchant(
    id: 'm_self',
    name: '绿健食堂',
    logo: 'logo',
    coverImage: 'cover',
    distance: 0,
    rating: 4.8,
    monthSold: 1860,
    hygieneGrade: 'A',
    isOpen: true,
    address: '科技园 A 区 综合楼 1 层',
    paymentQrCode: 'qr',
    deliveryFee: 3.0,
  );

  /// 每个商家的菜品
  static final List<Dish> dishes = [
    // m_1 绿禾餐饮 —— 中餐为主
    Dish(
      id: 'd_1_1',
      merchantId: 'm_1',
      name: '香煎鸡胸肉饭',
      image: 'dish',
      description: '低脂高蛋白，营养均衡',
      price: 16.8,
      mealType: MealType.lunch,
      tags: ['健康', '推荐'],
    ),
    Dish(
      id: 'd_1_2',
      merchantId: 'm_1',
      name: '番茄牛腩饭',
      image: 'dish',
      description: '番茄酸甜，牛腩软糯',
      price: 15.8,
      mealType: MealType.lunch,
      tags: ['实惠', '推荐'],
    ),
    Dish(
      id: 'd_1_3',
      merchantId: 'm_1',
      name: '清炒时蔬',
      image: 'dish',
      description: '时令蔬菜，清淡爽口',
      price: 6.8,
      mealType: MealType.lunch,
      tags: ['健康'],
    ),
    Dish(
      id: 'd_1_4',
      merchantId: 'm_1',
      name: '玉米排骨汤',
      image: 'dish',
      description: '小火慢炖，营养滋补',
      price: 4.8,
      mealType: MealType.lunch,
      tags: ['健康'],
    ),
    Dish(
      id: 'd_1_5',
      merchantId: 'm_1',
      name: '杂粮饭',
      image: 'dish',
      description: '多种谷物，膳食纤维丰富',
      price: 2.0,
      mealType: MealType.lunch,
      tags: ['健康'],
    ),
    Dish(
      id: 'd_1_6',
      merchantId: 'm_1',
      name: '原味豆浆',
      image: 'dish',
      description: '现磨豆浆，浓香醇厚',
      price: 3.0,
      mealType: MealType.breakfast,
      tags: ['健康'],
    ),

    // m_2 食光小厨
    Dish(
      id: 'd_2_1',
      merchantId: 'm_2',
      name: '宫保鸡丁饭',
      image: 'dish',
      description: '经典川菜，下饭神器',
      price: 18.0,
      mealType: MealType.lunch,
      tags: ['推荐'],
    ),
    Dish(
      id: 'd_2_2',
      merchantId: 'm_2',
      name: '冬瓜汤',
      image: 'dish',
      description: '清爽冬瓜汤',
      price: 4.0,
      mealType: MealType.lunch,
      tags: ['健康'],
    ),

    // m_3 轻食工坊
    Dish(
      id: 'd_3_1',
      merchantId: 'm_3',
      name: '鸡胸肉沙拉',
      image: 'dish',
      description: '低脂高蛋白，健身首选',
      price: 22.0,
      mealType: MealType.lunch,
      tags: ['健康', '推荐'],
    ),
    Dish(
      id: 'd_3_2',
      merchantId: 'm_3',
      name: '藜麦饭团',
      image: 'dish',
      description: '藜麦杂粮饭团',
      price: 12.0,
      mealType: MealType.lunch,
      tags: ['健康'],
    ),
    Dish(
      id: 'd_3_3',
      merchantId: 'm_3',
      name: '美式咖啡',
      image: 'dish',
      description: '现磨美式咖啡',
      price: 8.0,
      mealType: MealType.breakfast,
      tags: ['推荐'],
    ),

    // m_4 家常味道
    Dish(
      id: 'd_4_1',
      merchantId: 'm_4',
      name: '红烧肉饭',
      image: 'dish',
      description: '肥而不腻，家常美味',
      price: 19.8,
      mealType: MealType.lunch,
      tags: ['推荐'],
    ),
    Dish(
      id: 'd_4_2',
      merchantId: 'm_4',
      name: '麻婆豆腐饭',
      image: 'dish',
      description: '麻辣鲜香',
      price: 14.0,
      mealType: MealType.lunch,
      tags: [],
    ),
  ];

  /// 商家端"我的菜品"——绑定到 currentMerchant
  static final List<Dish> merchantOwnDishes = [
    Dish(
      id: 'mo_1',
      merchantId: 'm_self',
      name: '小米粥',
      image: 'dish',
      description: '清淡养胃，早餐首选',
      price: 4.0,
      mealType: MealType.breakfast,
      tags: ['健康'],
    ),
    Dish(
      id: 'mo_2',
      merchantId: 'm_self',
      name: '茶叶蛋',
      image: 'dish',
      description: '现煮茶叶蛋',
      price: 2.5,
      mealType: MealType.breakfast,
      tags: [],
    ),
    Dish(
      id: 'mo_3',
      merchantId: 'm_self',
      name: '黄焖鸡米饭',
      image: 'dish',
      description: '鸡肉鲜嫩，酱香浓郁',
      price: 16.0,
      mealType: MealType.lunch,
      tags: ['推荐'],
    ),
    Dish(
      id: 'mo_4',
      merchantId: 'm_self',
      name: '清炒时蔬',
      image: 'dish',
      description: '时令蔬菜，清淡爽口',
      price: 6.0,
      mealType: MealType.lunch,
      tags: ['健康'],
    ),
    Dish(
      id: 'mo_5',
      merchantId: 'm_self',
      name: '番茄炒蛋盖饭',
      image: 'dish',
      description: '家常滋味',
      price: 13.0,
      mealType: MealType.dinner,
      tags: [],
    ),
  ];

  static List<Dish> dishesOfMerchant(String merchantId) =>
      dishes.where((d) => d.merchantId == merchantId).toList();
}
