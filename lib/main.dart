import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/dish_api.dart';
import 'api/merchant_api.dart';
import 'api/order_api.dart';
import 'app.dart';
import 'repositories/auth_repository.dart';
import 'repositories/dish_repository.dart';
import 'repositories/local_storage.dart';
import 'repositories/merchant_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/address_repository.dart';
import 'repositories/review_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await LocalStorage.instance();

  // API 层（占位）。当前默认 DataSourceMode.local，
  // repository 不会真正调用这些 API。
  final apiClient = ApiClient();
  final authApi = AuthApi(apiClient);
  final orderApi = OrderApi(apiClient);
  final dishApi = DishApi(apiClient);
  final merchantApi = MerchantApi(apiClient);

  // Repository 同时拿到本地存储和 API 客户端，
  // 内部依据 AppConfig.dataSourceMode 选择调用路径。
  final authRepo = AuthRepository(
    storage,
    authApi: authApi,
    apiClient: apiClient,
  );
  final orderRepo = OrderRepository(storage, orderApi: orderApi);
  final dishRepo = DishRepository(storage, dishApi: dishApi);
  final merchantRepo = MerchantRepository(
    storage,
    merchantApi: merchantApi,
    orderApi: orderApi,
  );
  final reviewRepo = ReviewRepository(storage);
  final addressRepo = AddressRepository(storage);

  runApp(FeigongYuncanApp(
    apiClient: apiClient,
    authRepository: authRepo,
    orderRepository: orderRepo,
    dishRepository: dishRepo,
    merchantRepository: merchantRepo,
    reviewRepository: reviewRepo,
    addressRepository: addressRepo,
  ));
}
