import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/support_conversation_state.dart';
import '../../state/employee_conversation_state.dart';
import '../../state/employee_notification_service.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/notification_sound.dart';
import 'employee_home_page.dart';
import 'employee_orders_page.dart';
import 'employee_profile_page.dart';

/// 员工端外壳：底部三 Tab（首页 / 订单 / 我的）
class EmployeeShell extends StatefulWidget {
  final int initialIndex;
  const EmployeeShell({super.key, this.initialIndex = 0});

  @override
  State<EmployeeShell> createState() => _EmployeeShellState();
}

class _EmployeeShellState extends State<EmployeeShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex;
  Timer? _orderPollTimer;

  final _pages = const [
    EmployeeHomePage(),
    EmployeeOrdersPage(),
    EmployeeProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final user = context.read<AppState>().currentUser;
    if (user != null) {
      EmployeeNotificationService.instance.resetForEmployee(user.id);
    }
    NotificationSound.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEmployeeData());
    _orderPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshEmployeeData();
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
      _refreshEmployeeData();
    }
  }

  Future<void> _refreshEmployeeData() async {
    if (!mounted) return;
    final user = context.read<AppState>().currentUser;
    if (user == null) return;
    await context.read<OrderState>().refreshEmployeeOrders(user.id);
    if (!mounted) return;
    await context.read<EmployeeConversationState>().refresh(
          employeeId: user.id,
        );
    if (!mounted) return;
    await context.read<SupportConversationState>().refreshUnread();
  }

  void _switchTab(int idx) {
    NotificationSound.unlockAfterUserGesture();
    setState(() => _index = idx);
    if (idx == 1 || idx == 2) {
      _refreshEmployeeData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatUnread = context.watch<EmployeeConversationState>().totalUnread;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 60,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
                top: BorderSide(color: AppColors.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              _NavItem(
                label: '首页',
                icon: Icons.home_outlined,
                active: _index == 0,
                onTap: () => _switchTab(0),
              ),
              _NavItem(
                label: '订单',
                icon: Icons.assignment_outlined,
                active: _index == 1,
                badgeCount: chatUnread > 0 && _index != 1 ? chatUnread : 0,
                onTap: () => _switchTab(1),
              ),
              _NavItem(
                label: '我的',
                icon: Icons.person_outline,
                active: _index == 2,
                onTap: () => _switchTab(2),
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
                          ? Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
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
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
