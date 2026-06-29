import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/order_api.dart';
import '../../api/package_api.dart';
import '../../models/dish_model.dart';
import '../../models/order_model.dart';
import '../../models/package_order_data_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coupon_checkout_section.dart';
import '../../widgets/dish_card.dart';
import 'order_payment_page.dart';

/// 员工套餐点餐页 — 仅从 package-order-data 接口加载标准数据。
class PackageOrderPage extends StatefulWidget {
  final String merchantId;
  final String merchantName;
  final MealType mealType;
  final String? selectedPackageId;
  final Map<String, int> initialMeatQty;
  final Map<String, int> initialVegQty;
  final Map<String, int> initialExtraQty;

  const PackageOrderPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    required this.mealType,
    this.selectedPackageId,
    this.initialMeatQty = const {},
    this.initialVegQty = const {},
    this.initialExtraQty = const {},
  });

  @override
  State<PackageOrderPage> createState() => _PackageOrderPageState();
}

class _PackageOrderPageState extends State<PackageOrderPage> {
  PackageOrderData? _data;
  PackageOrderPackage? _selected;
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  /// 荤/素：dishId -> qty
  final Map<String, int> _meatQty = {};
  final Map<String, int> _vegQty = {};
  final Map<String, int> _extraQty = {};
  String? _couponClaimId;
  CouponPreviewAmounts? _couponPreview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = PackageApi(context.read<ApiClient>());
      final data = await api.getPackageOrderData(
        widget.merchantId,
        mealType: widget.mealType,
      );
      if (!mounted) return;

      PackageOrderPackage? selected;
      var packageMissing = false;
      if (widget.selectedPackageId != null) {
        for (final p in data.packages) {
          if (p.id == widget.selectedPackageId) {
            selected = p;
            break;
          }
        }
        if (selected == null && data.packages.isNotEmpty) {
          packageMissing = true;
        }
      }
      selected ??= data.packages.isNotEmpty ? data.packages.first : null;

      final meatQty = <String, int>{};
      final vegQty = <String, int>{};
      final extraQty = <String, int>{};
      var skippedExtras = 0;

      if (selected != null) {
        for (final entry in widget.initialMeatQty.entries) {
          if (data.meat.any((d) => d.id == entry.key)) {
            meatQty[entry.key] = entry.value;
          }
        }
        for (final entry in widget.initialVegQty.entries) {
          if (data.vegetable.any((d) => d.id == entry.key)) {
            vegQty[entry.key] = entry.value;
          }
        }
        for (final entry in widget.initialExtraQty.entries) {
          if (data.extra.any((d) => d.id == entry.key)) {
            extraQty[entry.key] = entry.value;
          } else {
            skippedExtras++;
          }
        }
      }

      setState(() {
        _data = data;
        _selected = selected;
        _loading = false;
        _meatQty
          ..clear()
          ..addAll(meatQty);
        _vegQty
          ..clear()
          ..addAll(vegQty);
        _extraQty
          ..clear()
          ..addAll(extraQty);
      });

      if (packageMissing && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('原套餐已下架，请重新选择套餐')),
        );
      } else if (skippedExtras > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('部分加菜已下架，已忽略')),
        );
      }

      debugPrint(
        '[package-order-data] packages=${data.packages.length}, meat=${data.meat.length}, vegetable=${data.vegetable.length}, extra=${data.extra.length}',
      );
    } catch (e, st) {
      debugPrint('[package-order-data] FAILED error=$e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _pickPackage(PackageOrderPackage pkg) {
    if (_selected?.id == pkg.id) return;
    setState(() {
      _selected = pkg;
      _meatQty.clear();
      _vegQty.clear();
      _extraQty.clear();
    });
  }

  int _meatTotal() => _meatQty.values.fold(0, (a, b) => a + b);
  int _vegTotal() => _vegQty.values.fold(0, (a, b) => a + b);

  double _extraAmount() {
    final extras = _data?.extra ?? const [];
    var sum = 0.0;
    for (final entry in _extraQty.entries) {
      final dish = extras.where((d) => d.id == entry.key).firstOrNull;
      if (dish != null) sum += dish.extraPrice * entry.value;
    }
    return sum;
  }

  String? _validate() {
    final pkg = _selected;
    if (pkg == null) return '请选择套餐';
    final meatGot = _meatTotal();
    if (meatGot < pkg.meatCount) {
      return '还差 ${pkg.meatCount - meatGot} 个荤菜';
    }
    if (meatGot > pkg.meatCount) {
      return '荤菜最多选择 ${pkg.meatCount} 个';
    }
    final vegGot = _vegTotal();
    if (vegGot < pkg.vegetableCount) {
      return '还差 ${pkg.vegetableCount - vegGot} 个素菜';
    }
    if (vegGot > pkg.vegetableCount) {
      return '素菜最多选择 ${pkg.vegetableCount} 个';
    }
    return null;
  }

  void _changeMeat(String dishId, int delta) {
    final pkg = _selected;
    if (pkg == null) return;
    final current = _meatQty[dishId] ?? 0;
    final total = _meatTotal();
    if (delta > 0 && total >= pkg.meatCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('荤菜最多选择 ${pkg.meatCount} 个')),
      );
      return;
    }
    final next = current + delta;
    setState(() {
      if (next <= 0) {
        _meatQty.remove(dishId);
      } else {
        _meatQty[dishId] = next;
      }
    });
  }

  void _changeVeg(String dishId, int delta) {
    final pkg = _selected;
    if (pkg == null) return;
    final current = _vegQty[dishId] ?? 0;
    final total = _vegTotal();
    if (delta > 0 && total >= pkg.vegetableCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('素菜最多选择 ${pkg.vegetableCount} 个')),
      );
      return;
    }
    final next = current + delta;
    setState(() {
      if (next <= 0) {
        _vegQty.remove(dishId);
      } else {
        _vegQty[dishId] = next;
      }
    });
  }

  void _changeExtra(String dishId, int delta) {
    final current = _extraQty[dishId] ?? 0;
    final next = (current + delta).clamp(0, 99);
    setState(() {
      if (next == 0) {
        _extraQty.remove(dishId);
      } else {
        _extraQty[dishId] = next;
      }
    });
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final pkg = _selected!;
    setState(() => _submitting = true);
    try {
      final selectedIds = <String>[];
      _meatQty.forEach((id, qty) {
        for (var i = 0; i < qty; i++) selectedIds.add(id);
      });
      _vegQty.forEach((id, qty) {
        for (var i = 0; i < qty; i++) selectedIds.add(id);
      });
      final extras = _extraQty.entries
          .map((e) => {'dishId': e.key, 'quantity': e.value})
          .toList();
      final api = OrderApi(context.read<ApiClient>());
      final order = await api.createPackageOrder(
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        packageId: pkg.id,
        selectedDishIds: selectedIds,
        extras: extras,
        deliveryType: DeliveryType.selfPickup,
        mealType: widget.mealType.name,
        couponClaimId: _couponClaimId,
      );
      if (!mounted) return;
      if (order.employeePayAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              order.companyPayAmount > 0 || (order.couponDiscountAmount) > 0
                  ? '订单已提交，等待商家确认'
                  : '企业代付订单已提交，等待商家确认',
            ),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      if (order.status == OrderStatus.pendingPayment) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OrderPaymentPage(order: order),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '下单成功，最终金额 ¥${order.finalAmount.toStringAsFixed(2)}',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下单失败：$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pkg = _selected;
    final basePrice = pkg?.basePrice ?? 0;
    final extraAmount = _extraAmount();
    final total = basePrice + extraAmount;
    final validationMsg = _validate();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.merchantName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '${widget.mealType.label} · 套餐点餐',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _PriceBar(
        packageName: pkg?.name,
        basePrice: basePrice,
        extraAmount: extraAmount,
        total: total,
        preview: _couponPreview,
        submitting: _submitting,
        validationMsg: validationMsg,
        onSubmit: _submit,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.accent),
              const SizedBox(height: 12),
              Text(
                '加载失败',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    if (data.packages.isEmpty) {
      return const Center(
        child: Text(
          '当前餐段暂无套餐',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        const _StepTitle('① 选择套餐'),
        const SizedBox(height: 8),
        _PackageGrid(
          packages: data.packages,
          selectedId: _selected?.id,
          onPick: _pickPackage,
        ),
        const SizedBox(height: 16),
        const _StepTitle('② 按规则选菜'),
        const SizedBox(height: 8),
        if (_selected == null)
          const _HintText('请先选择套餐')
        else ...[
          _SelectedBanner(
            package: _selected!,
            meatTotal: _meatTotal(),
            vegTotal: _vegTotal(),
          ),
          const SizedBox(height: 10),
          _DishSection(
            title: '荤菜',
            required: _selected!.meatCount,
            selected: _meatTotal(),
            dishes: data.meat,
            qtyMap: _meatQty,
            emptyHint:
                '当前商家未配置可选荤菜/素菜，请联系商家完善菜品。',
            onChange: _changeMeat,
          ),
          const SizedBox(height: 10),
          _DishSection(
            title: '素菜',
            required: _selected!.vegetableCount,
            selected: _vegTotal(),
            dishes: data.vegetable,
            qtyMap: _vegQty,
            emptyHint:
                '当前商家未配置可选荤菜/素菜，请联系商家完善菜品。',
            onChange: _changeVeg,
          ),
        ],
        if (data.extra.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _StepTitle('③ 加菜（可选，另计）'),
          const SizedBox(height: 8),
          _ExtraSection(
            extras: data.extra,
            quantities: _extraQty,
            onChange: _changeExtra,
          ),
        ],
        const SizedBox(height: 16),
        const _StepTitle('④ 优惠券'),
        const SizedBox(height: 8),
        CouponCheckoutSection(
          merchantId: widget.merchantId,
          mealType: widget.mealType,
          orderTotal: basePrice + extraAmount,
          onClaimIdChanged: (id) => setState(() => _couponClaimId = id),
          onPreviewChanged: (p) => setState(() => _couponPreview = p),
        ),
      ],
    );
  }

  double get basePrice => _selected?.basePrice ?? 0;

  double get extraAmount => _extraAmount();
}

class _StepTitle extends StatelessWidget {
  final String text;
  const _StepTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;
  const _HintText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
      ),
    );
  }
}

class _PackageGrid extends StatelessWidget {
  final List<PackageOrderPackage> packages;
  final String? selectedId;
  final ValueChanged<PackageOrderPackage> onPick;

  const _PackageGrid({
    required this.packages,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: packages.length,
      itemBuilder: (_, i) {
        final p = packages[i];
        final selected = p.id == selectedId;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onPick(p),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : AppColors.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '¥${p.basePrice.toStringAsFixed(p.basePrice % 1 == 0 ? 0 : 2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.meatCount}荤${p.vegetableCount}素',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SelectedBanner extends StatelessWidget {
  final PackageOrderPackage package;
  final int meatTotal;
  final int vegTotal;

  const _SelectedBanner({
    required this.package,
    required this.meatTotal,
    required this.vegTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前套餐：${package.name}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '套餐价：¥${package.basePrice.toStringAsFixed(package.basePrice % 1 == 0 ? 0 : 2)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            '需要选择：${package.meatCount} 个荤菜 + ${package.vegetableCount} 个素菜',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            '当前进度：荤菜 $meatTotal/${package.meatCount}，素菜 $vegTotal/${package.vegetableCount}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DishSection extends StatelessWidget {
  final String title;
  final int required;
  final int selected;
  final List<PackageOrderDish> dishes;
  final Map<String, int> qtyMap;
  final String emptyHint;
  final void Function(String dishId, int delta) onChange;

  const _DishSection({
    required this.title,
    required this.required,
    required this.selected,
    required this.dishes,
    required this.qtyMap,
    required this.emptyHint,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title｜已选 $selected/$required',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (selected < required) ...[
            const SizedBox(height: 4),
            Text(
              '还差 ${required - selected} 个$title',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (dishes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyHint,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            ...dishes.map((d) {
              final qty = qtyMap[d.id] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    DishImagePlaceholder(
                      seed: d.id,
                      size: 44,
                      imageUrl: d.imageUrl,
                      dishName: d.name,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        d.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _QtyStepper(
                      qty: qty,
                      onMinus: qty > 0 ? () => onChange(d.id, -1) : null,
                      onPlus: () => onChange(d.id, 1),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ExtraSection extends StatelessWidget {
  final List<PackageOrderExtraDish> extras;
  final Map<String, int> quantities;
  final void Function(String dishId, int delta) onChange;

  const _ExtraSection({
    required this.extras,
    required this.quantities,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: extras.map((d) {
          final qty = quantities[d.id] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                DishImagePlaceholder(
                  seed: d.id,
                  size: 44,
                  imageUrl: d.imageUrl,
                  dishName: d.name,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '+ ¥${d.extraPrice.toStringAsFixed(d.extraPrice % 1 == 0 ? 0 : 2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _QtyStepper(
                  qty: qty,
                  onMinus: qty > 0 ? () => onChange(d.id, -1) : null,
                  onPlus: () => onChange(d.id, 1),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  const _QtyStepper({
    required this.qty,
    required this.onPlus,
    this.onMinus,
  });

  @override
  Widget build(BuildContext context) {
    final disabledMinus = onMinus == null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onMinus,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: disabledMinus
                  ? AppColors.divider
                  : AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.remove,
              size: 16,
              color: disabledMinus ? AppColors.textTertiary : AppColors.primary,
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        InkWell(
          onTap: onPlus,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.add, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _PriceBar extends StatelessWidget {
  final String? packageName;
  final double basePrice;
  final double extraAmount;
  final double total;
  final CouponPreviewAmounts? preview;
  final bool submitting;
  final String? validationMsg;
  final VoidCallback onSubmit;

  const _PriceBar({
    required this.packageName,
    required this.basePrice,
    required this.extraAmount,
    required this.total,
    this.preview,
    required this.submitting,
    required this.validationMsg,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasPackage = packageName != null;
    final canSubmit = validationMsg == null && !submitting;
    final payPreview = preview;
    final employeePay = payPreview?.employeePayAmount ?? total;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPackage)
                Text(
                  '已选：$packageName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employeePay < total
                              ? '您需支付 ¥${employeePay.toStringAsFixed(2)}'
                              : '合计 ¥${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accent,
                          ),
                        ),
                        if (payPreview != null &&
                            (payPreview.companyPayAmount > 0 ||
                                payPreview.couponDiscountAmount > 0))
                          Text(
                            '总额 ¥${payPreview.orderTotal.toStringAsFixed(2)}'
                            '${payPreview.companyPayAmount > 0 ? ' · 企业代付 ¥${payPreview.companyPayAmount.toStringAsFixed(2)}' : ''}'
                            '${payPreview.couponDiscountAmount > 0 ? ' · 券 -¥${payPreview.couponDiscountAmount.toStringAsFixed(2)}' : ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        if (hasPackage)
                          Text(
                            extraAmount > 0
                                ? '套餐 ¥${basePrice.toStringAsFixed(2)} + 加菜 ¥${extraAmount.toStringAsFixed(2)}'
                                : '套餐 ¥${basePrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        if (validationMsg != null)
                          Text(
                            validationMsg!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: canSubmit ? onSubmit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.divider,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '提交订单',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
