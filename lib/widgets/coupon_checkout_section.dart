import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/coupon_api.dart';
import '../models/coupon_model.dart';
import '../models/dish_model.dart';
import '../theme/app_theme.dart';

/// 员工下单页优惠券区：领券、自动选最优、可取消使用
class CouponCheckoutSection extends StatefulWidget {
  final String merchantId;
  final MealType mealType;
  final double orderTotal;
  final ValueChanged<String?> onClaimIdChanged;
  final ValueChanged<CouponPreviewAmounts> onPreviewChanged;

  const CouponCheckoutSection({
    super.key,
    required this.merchantId,
    required this.mealType,
    required this.orderTotal,
    required this.onClaimIdChanged,
    required this.onPreviewChanged,
  });

  @override
  State<CouponCheckoutSection> createState() => _CouponCheckoutSectionState();
}

class CouponPreviewAmounts {
  final double orderTotal;
  final double companyPayAmount;
  final double couponDiscountAmount;
  final double employeePayAmount;

  const CouponPreviewAmounts({
    required this.orderTotal,
    this.companyPayAmount = 0,
    this.couponDiscountAmount = 0,
    required this.employeePayAmount,
  });
}

class _CouponCheckoutSectionState extends State<CouponCheckoutSection> {
  late final CouponApi _api;
  List<CouponTemplate> _claimable = const [];
  BestCouponResult? _best;
  bool _useCoupon = true;
  bool _loading = true;
  String? _claimingId;

  @override
  void initState() {
    super.initState();
    _api = CouponApi(context.read<ApiClient>());
    _load();
  }

  @override
  void didUpdateWidget(covariant CouponCheckoutSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderTotal != widget.orderTotal ||
        oldWidget.mealType != widget.mealType) {
      _refreshBest();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final claimable =
          await _api.listClaimableForMerchant(widget.merchantId);
      if (!mounted) return;
      setState(() => _claimable = claimable);
      await _refreshBest();
    } catch (_) {
      if (mounted) {
        setState(() {
          _claimable = const [];
          _best = null;
        });
        _emitSelection(null);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshBest() async {
    if (widget.orderTotal <= 0) {
      _emitSelection(null);
      return;
    }
    try {
      final best = await _api.findBest(
        merchantId: widget.merchantId,
        mealType: widget.mealType,
        amount: widget.orderTotal,
      );
      if (!mounted) return;
      setState(() => _best = best);
      if (_useCoupon && best != null) {
        _emitSelection(best.claim.id, best: best);
      } else {
        _emitSelection(null);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _best = null);
      _emitSelection(null);
    }
  }

  void _emitSelection(String? claimId, {BestCouponResult? best}) {
    widget.onClaimIdChanged(claimId);
    final preview = best ?? _best;
    if (preview != null && claimId != null) {
      widget.onPreviewChanged(
        CouponPreviewAmounts(
          orderTotal: widget.orderTotal,
          companyPayAmount:
              widget.orderTotal - preview.employeePayBeforeCoupon,
          couponDiscountAmount: preview.discountAmount,
          employeePayAmount: preview.employeePayAmount,
        ),
      );
    } else {
      widget.onPreviewChanged(
        CouponPreviewAmounts(
          orderTotal: widget.orderTotal,
          employeePayAmount: widget.orderTotal,
        ),
      );
    }
  }

  Future<void> _claim(CouponTemplate tpl) async {
    setState(() => _claimingId = tpl.id);
    try {
      await _api.claim(tpl.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已领取：${tpl.name}')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('领取失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _claimingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
      );
    }

    final hasClaimable = _claimable.isNotEmpty;
    final hasBest = _best != null;

    if (!hasClaimable && !hasBest) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          const Row(
            children: [
              Icon(Icons.local_offer_outlined,
                  size: 18, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                '优惠券',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (hasClaimable) ...[
            const SizedBox(height: 10),
            ..._claimable.map(
              (tpl) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tpl.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            tpl.summary,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _claimingId == tpl.id
                          ? null
                          : () => _claim(tpl),
                      child: Text(
                        _claimingId == tpl.id ? '领取中…' : '领取优惠券',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (hasBest) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _useCoupon
                        ? '已选：${_best!.claim.template?.name ?? '优惠券'}（-¥${_best!.discountAmount.toStringAsFixed(2)}）'
                        : '不使用优惠券',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Switch(
                  value: _useCoupon,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _useCoupon = v);
                    if (v && _best != null) {
                      _emitSelection(_best!.claim.id);
                    } else {
                      _emitSelection(null);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
