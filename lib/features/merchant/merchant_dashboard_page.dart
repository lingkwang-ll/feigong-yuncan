import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/dish_model.dart';
import '../../state/merchant_conversation_state.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/meal_batch_aggregator.dart';
import '../../widgets/app_logo.dart';
import 'merchant_dashboard_drill_sheet.dart';
import 'merchant_meal_label_sheet.dart';

/// 商家工作台 — 企业订餐餐段汇总视角
class MerchantDashboardPage extends StatefulWidget {
  final ValueChanged<int> onJump;
  const MerchantDashboardPage({super.key, required this.onJump});

  @override
  State<MerchantDashboardPage> createState() =>
      _MerchantDashboardPageState();
}

class _MerchantDashboardPageState extends State<MerchantDashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _refresh() async {
    final merchant = context.read<MerchantState>().currentMerchant;
    await Future.wait([
      context.read<OrderState>().refreshMerchantDashboard(
            merchantId: merchant.id,
            merchantName: merchant.name,
          ),
      context.read<MerchantConversationState>().refresh(
            merchantId: merchant.id,
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final orderState = context.watch<OrderState>();
    final merchant = context.watch<MerchantState>().currentMerchant;
    final today = DateTime.now();
    final mealType = MealBatchAggregator.currentMealPeriod();
    final batch = MealBatchAggregator.build(
      orders: orderState.merchantOrders(merchant.id),
      date: DateTime(today.year, today.month, today.day),
      mealType: mealType,
      merchantId: merchant.id,
      merchantName: merchant.name,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _TopBar(
                merchantName: merchant.name,
                merchantLogo: merchant.logo,
                isOpen: merchant.isOpen,
              ),
              const SizedBox(height: 14),
              _MealBatchCard(
                batch: batch,
                onDrill: (drill) => MerchantDashboardDrillSheet.show(
                  context,
                  drill: drill,
                  batch: batch,
                ),
              ),
              const SizedBox(height: 14),
              _QuickActions(
                onJump: widget.onJump,
                batch: batch,
                pendingPeople: batch.pendingPeople,
              ),
              const SizedBox(height: 14),
              _DishTopSummary(dishTotals: batch.dishTotals),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String merchantName;
  final String merchantLogo;
  final bool isOpen;

  const _TopBar({
    required this.merchantName,
    required this.merchantLogo,
    required this.isOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1FA855), Color(0xFF0D8A42)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          MerchantBadgeLogo(seed: merchantLogo, size: 44, radius: 11),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '非攻云餐 · 商家端',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  merchantName,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.circle,
                        size: 7,
                        color: isOpen ? Colors.white : Colors.white54),
                    const SizedBox(width: 5),
                    Text(
                      isOpen ? '营业中' : '休息中',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealBatchCard extends StatelessWidget {
  final MealBatchSummary batch;
  final ValueChanged<MerchantStatDrill> onDrill;

  const _MealBatchCard({
    required this.batch,
    required this.onDrill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                batch.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  batch.phase.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '订餐截止：${batch.mealType.deadlineAt}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat(
                '总份数',
                '${batch.totalPortions}',
                onTap: () => onDrill(MerchantStatDrill.totalPortions),
              ),
              _miniStat(
                '总人数',
                '${batch.totalPeople}',
                onTap: () => onDrill(MerchantStatDrill.totalPeople),
              ),
              _miniStat(
                '总金额',
                '¥${batch.totalAmount.toStringAsFixed(0)}',
                valueColor: AppColors.accent,
                onTap: () => onDrill(MerchantStatDrill.totalAmount),
              ),
              _miniStat(
                '待处理',
                '${batch.pendingPeople}人',
                valueColor: AppColors.accent,
                onTap: () => onDrill(MerchantStatDrill.pending),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final ValueChanged<int> onJump;
  final MealBatchSummary batch;
  final int pendingPeople;

  const _QuickActions({
    required this.onJump,
    required this.batch,
    required this.pendingPeople,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '快捷操作',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _action(
                color: AppColors.accent,
                icon: Icons.summarize_outlined,
                title: '查看今日汇总',
                badge: pendingPeople,
                onTap: () => onJump(1),
              ),
              _action(
                color: AppColors.primary,
                icon: Icons.label_outline,
                title: '打印餐盒标签',
                onTap: () => MerchantMealLabelSheet.show(
                  context,
                  batch: batch,
                ),
              ),
              _action(
                color: AppColors.statusBlue,
                icon: Icons.rice_bowl_outlined,
                title: '菜品管理',
                onTap: () => onJump(2),
              ),
              _action(
                color: const Color(0xFFF59E0B),
                icon: Icons.storefront_outlined,
                title: '店铺设置',
                onTap: () => onJump(3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action({
    required Color color,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DishTopSummary extends StatelessWidget {
  final List<DishAggregate> dishTotals;
  const _DishTopSummary({required this.dishTotals});

  @override
  Widget build(BuildContext context) {
    final top = dishTotals.take(8).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '今日菜品 TOP 汇总',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '当前餐段暂无订餐',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...top.map(
              (d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.dishName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '×${d.quantity}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
