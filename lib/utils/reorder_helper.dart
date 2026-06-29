import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/order_api.dart';
import '../features/employee/employee_confirm_order_page.dart';
import '../features/employee/package_order_page.dart';
import '../models/cart_item_model.dart';
import '../models/dish_model.dart';
import '../models/merchant_model.dart';
import '../models/order_model.dart';
import '../state/cart_state.dart';
import '../state/merchant_state.dart';
import '../utils/trial_run_policy.dart';

/// 再次下单：跳转套餐页或写入购物车后进入确认页（不直接生成订单）
class ReorderHelper {
  ReorderHelper._();

  static MealType inferMealType(Order order) {
    if (order.items.isNotEmpty) {
      return order.items.first.dish.mealType;
    }
    for (final si in order.selectedItems) {
      final raw = si.mealType;
      if (raw != null && raw.isNotEmpty) {
        for (final mt in MealType.values) {
          if (mt.name == raw) return mt;
        }
      }
    }
    return MealType.lunch;
  }

  static Future<void> start(BuildContext context, Order order) async {
    final messenger = ScaffoldMessenger.of(context);
    final mealType = inferMealType(order);
    final wasRosterCompanyPay =
        (order.paymentType == PaymentType.companyPay ||
            order.paymentType == PaymentType.mixedPay) &&
        mealType != MealType.overtime;

    if (AppConfig.dataSourceMode == DataSourceMode.api && wasRosterCompanyPay) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('再次下单'),
          content: const Text(
            '你今日该餐段的企业代付资格已使用，本次订单需自行支付，是否继续？',
          ),
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
      if (ok != true || !context.mounted) return;
    } else if (AppConfig.dataSourceMode == DataSourceMode.api &&
        mealType != MealType.overtime) {
      try {
        final eligibility = await OrderApi(context.read<ApiClient>())
            .getCompanyPayEligibility(mealType);
        if (eligibility.companyPayUsed && context.mounted) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('企业代付已使用'),
              content: Text(
                '${mealType.label}：${eligibility.hint.isNotEmpty ? eligibility.hint : "今日该餐段企业代付已使用，再次下单需自费"}，是否继续？',
              ),
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
          if (ok != true || !context.mounted) return;
        }
      } catch (_) {}
    }

    final merchantState = context.read<MerchantState>();
    await merchantState.refreshNearbyMerchants();
    if (!context.mounted) return;

    final merchant = _findMerchant(merchantState, order.merchantId);
    if (merchant == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('商家当前不可下单，请稍后再试')),
      );
      return;
    }
    if (!merchant.isOpen) {
      messenger.showSnackBar(
        const SnackBar(content: Text('商家当前不可下单，请稍后再试')),
      );
      return;
    }

    if (!MealOrderDeadline.isMealOpenFor(mealType, merchant: merchant)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前餐段未开放，请选择其他餐段')),
      );
      return;
    }

    if (order.isPackageOrder) {
      final meatQty = <String, int>{};
      final vegQty = <String, int>{};
      for (final si in order.selectedItems) {
        if (si.category == 'meat') {
          meatQty[si.dishId] = (meatQty[si.dishId] ?? 0) + 1;
        } else if (si.category == 'vegetable') {
          vegQty[si.dishId] = (vegQty[si.dishId] ?? 0) + 1;
        }
      }
      final extraQty = {
        for (final e in order.extraItems) e.dishId: e.quantity,
      };
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PackageOrderPage(
            merchantId: merchant.id,
            merchantName: merchant.name,
            mealType: mealType,
            selectedPackageId: order.packageId,
            initialMeatQty: meatQty,
            initialVegQty: vegQty,
            initialExtraQty: extraQty,
          ),
        ),
      );
      return;
    }

    final cart = context.read<CartState>();
    cart.clear();
    final added = await cart.addDishesFromOrder(
      context: context,
      merchant: merchant,
      items: order.items,
    );
    if (!added || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EmployeeConfirmOrderPage()),
    );
  }

  static Merchant? _findMerchant(MerchantState state, String merchantId) {
    for (final m in state.nearbyMerchants) {
      if (m.id == merchantId) return m;
    }
    return null;
  }
}
