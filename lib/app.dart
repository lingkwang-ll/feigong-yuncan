import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'features/auth/auth_entry_gate.dart';
import 'features/auth/login_page.dart';
import 'models/user_model.dart';
import 'repositories/auth_repository.dart';
import 'repositories/dish_repository.dart';
import 'repositories/merchant_repository.dart';
import 'repositories/order_repository.dart';
import 'state/app_state.dart';
import 'state/cart_state.dart';
import 'state/employee_conversation_state.dart';
import 'state/merchant_conversation_state.dart';
import 'state/merchant_dish_state.dart';
import 'state/merchant_state.dart';
import 'repositories/address_repository.dart';
import 'repositories/review_repository.dart';
import 'state/address_state.dart';
import 'state/order_state.dart';
import 'state/review_state.dart';
import 'state/support_conversation_state.dart';
import 'theme/app_theme.dart';
import 'utils/notification_settings.dart';
import 'widgets/mobile_app_frame.dart';

class FeigongYuncanApp extends StatelessWidget {
  final ApiClient apiClient;
  final AuthRepository authRepository;
  final OrderRepository orderRepository;
  final DishRepository dishRepository;
  final MerchantRepository merchantRepository;
  final ReviewRepository reviewRepository;
  final AddressRepository addressRepository;

  const FeigongYuncanApp({
    super.key,
    required this.apiClient,
    required this.authRepository,
    required this.orderRepository,
    required this.dishRepository,
    required this.merchantRepository,
    required this.reviewRepository,
    required this.addressRepository,
  });

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<DishRepository>.value(value: dishRepository),
        Provider<OrderRepository>.value(value: orderRepository),
        ChangeNotifierProvider(
          create: (_) => AppState(authRepository: authRepository),
        ),
        ChangeNotifierProvider(create: (_) => CartState()),
        ChangeNotifierProvider(
          create: (_) => OrderState(orderRepository: orderRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => ReviewState(reviewRepository: reviewRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => AddressState(addressRepository: addressRepository),
        ),
        ChangeNotifierProvider(
          create: (ctx) => EmployeeConversationState(
            apiClient: ctx.read<ApiClient>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => MerchantConversationState(
            apiClient: ctx.read<ApiClient>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final state = SupportConversationState();
            state.bindApi(ctx.read<ApiClient>());
            return state;
          },
        ),
        ChangeNotifierProvider(
          create: (_) =>
              MerchantDishState(dishRepository: dishRepository),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              MerchantState(merchantRepository: merchantRepository),
        ),
      ],
      child: MaterialApp(
        title: '非攻云餐',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        theme: AppTheme.light(),
        builder: (context, child) =>
            MobileAppFrame(child: child ?? const SizedBox.shrink()),
        home: const _AppBootstrap(),
      ),
    );
  }
}

/// 启动引导：异步初始化所有 State，再根据登录状态分发到对应入口
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late final Future<void> _bootFuture;

  @override
  void initState() {
    super.initState();
    _bootFuture = _bootstrap();
  }

  Future<void> _bootstrap() async {
    final app = context.read<AppState>();
    final apiClient = context.read<ApiClient>();
    apiClient.onUnauthorized = () => app.handleUnauthorized();

    final orders = context.read<OrderState>();
    final reviews = context.read<ReviewState>();
    final addresses = context.read<AddressState>();
    final dishes = context.read<MerchantDishState>();
    final merchant = context.read<MerchantState>();
    final merchantConversations = context.read<MerchantConversationState>();
    final employeeConversations = context.read<EmployeeConversationState>();
    final supportConversations = context.read<SupportConversationState>();

    await NotificationSettings.load();

    await Future.wait([
      app.initialize(),
      orders.initialize(),
      reviews.initialize(),
      addresses.initialize(),
      dishes.initialize(),
      merchant.initialize(),
    ]);

    // 已登录用户：根据角色立刻刷新远端数据（仅 api 模式下会真正请求）
    final user = app.currentUser;
    if (user == null) return;
    if (user.role == UserRole.merchant) {
      final m = await merchant.refreshMerchantProfile(user.id);
      final merchantId = m?.id;
      if (merchantId != null) {
        app.setCurrentMerchantId(merchantId);
        await Future.wait([
          dishes.refreshFor(merchantId),
          orders.refreshForRole(
            role: UserRole.merchant,
            merchantId: merchantId,
          ),
          merchantConversations.refresh(merchantId: merchantId),
          supportConversations.refreshUnread(),
        ]);
      }
    } else if (app.isEmployeeBound) {
      await Future.wait([
        merchant.refreshNearbyMerchants(),
        orders.refreshForRole(role: UserRole.employee, userId: user.id),
        employeeConversations.refresh(employeeId: user.id),
        supportConversations.refreshUnread(),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        final appState = context.watch<AppState>();
        final user = appState.currentUser;
        if (user == null) {
          final hint = appState.sessionExpiredMessage;
          if (hint != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(hint)),
              );
              appState.clearSessionExpiredMessage();
            });
          }
          return const LoginPage();
        }
        return const AuthEntryGate();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              '加载中...',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
