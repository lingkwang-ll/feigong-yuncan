import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../state/merchant_conversation_state.dart';
import '../../state/merchant_notification_service.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/notification_sound.dart';
import '../../widgets/app_logo.dart';
import 'merchant_dashboard_page.dart';
import 'merchant_dish_manage_page.dart';
import 'merchant_order_process_page.dart';
import 'merchant_profile_page.dart';

/// 商家端外壳：底部 4 Tab（工作台 / 订单管理 / 菜品管理 / 我的）
class MerchantShell extends StatefulWidget {
  final int initialIndex;
  const MerchantShell({super.key, this.initialIndex = 0});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex;
  Timer? _orderPollTimer;

  late final List<Widget> _pages = [
    MerchantDashboardPage(onJump: _jumpTo),
    const MerchantOrderProcessPage(),
    const MerchantDishManagePage(),
    const MerchantProfilePage(),
  ];

  void _jumpTo(int idx) => setState(() => _index = idx);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final merchant = context.read<MerchantState>().currentMerchant;
    MerchantNotificationService.instance.resetForMerchant(merchant.id);
    NotificationSound.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMerchantDashboard());
    _orderPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshMerchantDashboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orderPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshMerchantDashboard();
    }
  }

  Future<void> _refreshMerchantDashboard() async {
    if (!mounted) return;
    final merchant = context.read<MerchantState>().currentMerchant;
    await context.read<OrderState>().refreshMerchantDashboard(
          merchantId: merchant.id,
          merchantName: merchant.name,
        );
    if (!mounted) return;
    await context.read<MerchantConversationState>().refresh(
          merchantId: merchant.id,
        );
  }

  void _onTabTap(int idx) {
    NotificationSound.unlockAfterUserGesture();
    _jumpTo(idx);
    _refreshMerchantDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final merchant = context.watch<MerchantState>().currentMerchant;
    final pending = context
        .watch<OrderState>()
        .merchantOrders(merchant.id)
        .where((o) =>
            o.status == OrderStatus.pendingMerchantConfirm ||
            o.status == OrderStatus.paymentSubmitted)
        .length;
    final chatUnread = context.watch<MerchantConversationState>().totalUnread;
    final tabBadge = pending + chatUnread;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 62,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              _NavItem(
                label: '工作台',
                icon: Icons.home_outlined,
                active: _index == 0,
                badgeCount: tabBadge > 0 && _index != 0 ? tabBadge : 0,
                onTap: () => _onTabTap(0),
              ),
              _NavItem(
                label: '订餐汇总',
                icon: Icons.assignment_outlined,
                active: _index == 1,
                badgeCount: tabBadge > 0 && _index != 1 ? tabBadge : 0,
                onTap: () => _onTabTap(1),
              ),
              _NavItem(
                label: '菜品管理',
                icon: Icons.restaurant_outlined,
                active: _index == 2,
                onTap: () => _onTabTap(2),
              ),
              _NavItemLogo(
                label: '我的',
                active: _index == 3,
                onTap: () => _onTabTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 24),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -6,
                    child: Container(
                      padding: badgeCount > 9
                          ? const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1)
                          : null,
                      constraints: badgeCount > 9
                          ? const BoxConstraints(minWidth: 16, minHeight: 14)
                          : const BoxConstraints(minWidth: 8, minHeight: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: badgeCount > 9
                          ? const Text(
                              '9+',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 3,
              width: 24,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemLogo extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItemLogo({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: active ? 1 : 0.55,
              child: const AppLogo(size: 22, radius: 6),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 3,
              width: 24,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
