import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 员工端首页底部购物车栏（旧版，已废弃，保留导出避免破坏）
@Deprecated('Use FloatingCartBar instead')
class CartBar extends StatelessWidget {
  final int totalQuantity;
  final double totalAmount;
  final VoidCallback? onCheckout;

  const CartBar({
    super.key,
    required this.totalQuantity,
    required this.totalAmount,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingCartBar(
      totalQuantity: totalQuantity,
      totalAmount: totalAmount,
      onCheckout: onCheckout,
    );
  }
}

/// 悬浮购物车底栏（严格还原 02_employee_home.png）
///
/// 视觉规范：
/// - 白色圆角胶囊浮在主体之上，整栏高 60，圆角 30
/// - 左侧 50x50 绿色实心圆，内白色购物车图标
/// - 右上角橙色圆形角标（带白边），显示总件数
/// - 中间两行：
///     已选 N 件   （13pt 灰）
///     合计：¥XX.X （¥金额 18pt 橙色加粗）
/// - 右侧橙色椭圆按钮"去结算"
class FloatingCartBar extends StatelessWidget {
  final int totalQuantity;
  final double totalAmount;
  final VoidCallback? onCheckout;
  /// 为 false 时即使有商品也不可结算（如已过订餐截止）
  final bool checkoutEnabled;

  const FloatingCartBar({
    super.key,
    required this.totalQuantity,
    required this.totalAmount,
    required this.onCheckout,
    this.checkoutEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasItems = totalQuantity > 0;
    final canCheckout = hasItems && checkoutEnabled;
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 60,
        padding: const EdgeInsets.fromLTRB(6, 5, 5, 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左侧绿色购物车圆 + 角标
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: hasItems
                        ? AppColors.primary
                        : AppColors.textTertiary,
                    shape: BoxShape.circle,
                    boxShadow: hasItems
                        ? [
                            BoxShadow(
                              color: AppColors.primary
                                  .withValues(alpha: 0.30),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: const Icon(Icons.shopping_cart,
                      color: Colors.white, size: 24),
                ),
                if (hasItems)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$totalQuantity',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // 中间文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    hasItems ? '已选 $totalQuantity 件' : '购物车空空如也',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (hasItems) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Text(
                          '合计：',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                        Text(
                          '¥${totalAmount.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // 右侧"去结算"按钮 —— 参考图中即使空购物车也是橙色（保持视觉），
            // 但根据需求"有商品时必须可点击"，空时降透明度
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: canCheckout ? onCheckout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  disabledBackgroundColor:
                      AppColors.accent.withValues(alpha: 0.45),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(110, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: const Text(
                  '去结算',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
