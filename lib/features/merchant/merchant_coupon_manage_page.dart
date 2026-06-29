import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/coupon_api.dart';
import '../../models/coupon_model.dart';
import '../../models/dish_model.dart';
import '../../theme/app_theme.dart';

/// 商家端 — 优惠券管理
class MerchantCouponManagePage extends StatefulWidget {
  const MerchantCouponManagePage({super.key});

  @override
  State<MerchantCouponManagePage> createState() =>
      _MerchantCouponManagePageState();
}

class _MerchantCouponManagePageState extends State<MerchantCouponManagePage> {
  late final CouponApi _api;
  bool _loading = true;
  String? _error;
  List<CouponTemplate> _coupons = const [];

  @override
  void initState() {
    super.initState();
    _api = CouponApi(context.read<ApiClient>());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listMerchantCoupons();
      if (!mounted) return;
      setState(() => _coupons = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _CouponEditorSheet(api: _api),
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _toggleStatus(CouponTemplate c) async {
    try {
      await _api.setCouponStatus(couponId: c.id, enabled: !c.isEnabled);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$e')));
    }
  }

  String _mealLabel(List<MealType> types) {
    if (types.length >= 3) return '早/中/晚';
    return types.map((t) => t.label).join('、');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('优惠券管理'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('新增优惠券'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppColors.primary,
                  child: _coupons.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                '暂无优惠券，点击右下角新增',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: _coupons.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final c = _coupons[i];
                            return Container(
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
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.isEnabled
                                              ? AppColors.primaryLight
                                              : const Color(0xFFF1F3F5),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          c.isEnabled ? '启用' : '停用',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: c.isEnabled
                                                ? AppColors.primary
                                                : AppColors.textTertiary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${c.couponType.label} · ${c.summary}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '适用餐段：${_mealLabel(c.mealTypes)} · 有效期至 ${c.endAt.toLocal().toString().substring(0, 10)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '已领 ${c.claimedCount}/${c.totalQuantity} · 已用 ${c.usedCount}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => _toggleStatus(c),
                                      child: Text(c.isEnabled ? '停用' : '启用'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _CouponEditorSheet extends StatefulWidget {
  final CouponApi api;

  const _CouponEditorSheet({required this.api});

  @override
  State<_CouponEditorSheet> createState() => _CouponEditorSheetState();
}

class _CouponEditorSheetState extends State<_CouponEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '5');
  final _minOrderCtrl = TextEditingController(text: '0');
  final _qtyCtrl = TextEditingController(text: '100');
  final _limitCtrl = TextEditingController(text: '1');
  CouponType _type = CouponType.fixed;
  final Set<MealType> _meals = {
    MealType.breakfast,
    MealType.lunch,
    MealType.dinner,
  };
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _discountCtrl.dispose();
    _minOrderCtrl.dispose();
    _qtyCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写优惠券名称')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await widget.api.createCoupon(
        name: name,
        couponType: _type,
        discountAmount: double.tryParse(_discountCtrl.text) ?? 0,
        minOrderAmount: double.tryParse(_minOrderCtrl.text) ?? 0,
        mealTypes: _meals.toList(),
        totalQuantity: int.tryParse(_qtyCtrl.text) ?? 100,
        perUserLimit: int.tryParse(_limitCtrl.text) ?? 1,
        startAt: now,
        endAt: now.add(const Duration(days: 30)),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '新增优惠券',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '优惠券名称'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CouponType>(
              value: _type,
              decoration: const InputDecoration(labelText: '类型'),
              items: CouponType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? CouponType.fixed),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '优惠金额（元）'),
            ),
            if (_type == CouponType.threshold) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _minOrderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '使用门槛（元）'),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '发放数量'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _limitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '每人限领'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: MealType.values
                  .where((m) =>
                      m == MealType.breakfast ||
                      m == MealType.lunch ||
                      m == MealType.dinner)
                  .map(
                    (m) => FilterChip(
                      label: Text(m.label),
                      selected: _meals.contains(m),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _meals.add(m);
                          } else if (_meals.length > 1) {
                            _meals.remove(m);
                          }
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
