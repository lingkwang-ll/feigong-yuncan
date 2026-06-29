import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/coupon_api.dart';
import '../../api/package_api.dart';
import '../../mock/mock_data.dart';
import '../../models/dish_model.dart';
import '../../models/merchant_model.dart';
import '../../models/package_model.dart';
import '../../state/merchant_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/trial_run_policy.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/merchant_card.dart';
import 'package_order_page.dart';

/// 员工端首页 — 仅展示商家与套餐入口
class EmployeeHomePage extends StatefulWidget {
  const EmployeeHomePage({super.key});

  @override
  State<EmployeeHomePage> createState() => _EmployeeHomePageState();
}

class _EmployeeHomePageState extends State<EmployeeHomePage> {
  MealType _mealType = MealType.lunch;
  Merchant? _selectedMerchant;
  List<MealPackage> _packages = const [];
  bool _loadingPackages = false;
  final Map<String, bool> _merchantHasCoupons = {};
  List<MealType> get _visibleMealTypes => const [
        MealType.breakfast,
        MealType.lunch,
        MealType.dinner,
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final merchantState = context.read<MerchantState>();
    final list = await merchantState.refreshNearbyMerchants();
    if (!mounted) return;
    if (!_visibleMealTypes.contains(_mealType)) {
      _mealType = MealType.lunch;
    }
    final initial = list.isNotEmpty ? list.first : MockData.merchants.first;
    setState(() {
      _selectedMerchant = initial;
    });
    await _loadPackages(initial);
    await _loadCouponFlags(list);
  }

  Future<void> _loadCouponFlags(List<Merchant> merchants) async {
    final api = CouponApi(context.read<ApiClient>());
    final map = <String, bool>{};
    for (final m in merchants) {
      try {
        final claimable = await api.listClaimableForMerchant(m.id);
        map[m.id] = claimable.isNotEmpty;
      } catch (_) {
        map[m.id] = false;
      }
    }
    if (!mounted) return;
    setState(() => _merchantHasCoupons
      ..clear()
      ..addAll(map));
  }

  Future<void> _loadPackages(Merchant merchant) async {
    setState(() => _loadingPackages = true);
    try {
      final api = PackageApi(context.read<ApiClient>());
      final list = await api.getMerchantPackages(
        merchant.id,
        mealType: _mealType,
      );
      if (!mounted) return;
      setState(() => _packages = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _packages = const []);
    } finally {
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _onSelectMerchant(Merchant m) async {
    setState(() => _selectedMerchant = m);
    await _loadPackages(m);
  }

  Future<void> _onMealTypeChanged(MealType t) async {
    setState(() => _mealType = t);
    final m = _selectedMerchant;
    if (m != null) await _loadPackages(m);
  }

  void _openPackage(Merchant merchant, MealPackage pkg) {
    debugPrint(
      '[package-home-click] merchantId=${merchant.id}, mealType=${_mealType.name}, packageId=${pkg.id}',
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PackageOrderPage(
          merchantId: merchant.id,
          merchantName: merchant.name,
          mealType: _mealType,
          selectedPackageId: pkg.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merchantState = context.watch<MerchantState>();
    final merchants = merchantState.nearbyMerchants;
    final selected = _selectedMerchant ??
        (merchants.isNotEmpty ? merchants.first : MockData.merchants.first);
    final mealClosed =
        MealOrderDeadline.isClosedFor(_mealType, merchant: selected);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _SearchBox(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _EmployeeMealTypeTabs(
                selected: _mealType,
                merchant: selected,
                visibleMealTypes: _visibleMealTypes,
                onChanged: _onMealTypeChanged,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '订餐截止时间以当前商家设置为准',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MerchantSidebar(
                      merchants: merchants,
                      selectedId: selected.id,
                      merchantHasCoupons: _merchantHasCoupons,
                      onSelect: _onSelectMerchant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PackagePanel(
                        merchant: selected,
                        packages: _packages,
                        mealType: _mealType,
                        loading: _loadingPackages,
                        mealClosed: mealClosed,
                        onPackageTap: (pkg) => _openPackage(selected, pkg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: [
            const AppLogo(size: 38, radius: 10),
            const SizedBox(width: 10),
            const Text(
              '非攻云餐',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, color: AppColors.primary, size: 16),
                  SizedBox(width: 3),
                  Text(
                    '科技园A区',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary, size: 18),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.notifications_outlined,
                color: AppColors.textPrimary, size: 24),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isCollapsed: true,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 6),
            child: Icon(Icons.search, color: AppColors.textTertiary, size: 22),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          hintText: '搜索商家或套餐',
          hintStyle:
              const TextStyle(color: AppColors.textTertiary, fontSize: 14),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(23),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(23),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(23),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _MerchantSidebar extends StatelessWidget {
  final List<Merchant> merchants;
  final String selectedId;
  final Map<String, bool> merchantHasCoupons;
  final ValueChanged<Merchant> onSelect;

  const _MerchantSidebar({
    required this.merchants,
    required this.selectedId,
    required this.merchantHasCoupons,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 126,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
            child: Text(
              '附近商家',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ...merchants.map(
            (m) => MerchantCard(
              merchant: m,
              selected: m.id == selectedId,
              hasClaimableCoupons: merchantHasCoupons[m.id] == true,
              onTap: () => onSelect(m),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackagePanel extends StatelessWidget {
  final Merchant merchant;
  final List<MealPackage> packages;
  final MealType mealType;
  final bool loading;
  final bool mealClosed;
  final ValueChanged<MealPackage> onPackageTap;

  const _PackagePanel({
    required this.merchant,
    required this.packages,
    required this.mealType,
    required this.loading,
    required this.mealClosed,
    required this.onPackageTap,
  });

  @override
  Widget build(BuildContext context) {
    final applicable =
        packages.where((p) => p.appliesTo(mealType) && p.isEnabled).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
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
              MerchantBadgeLogo(seed: merchant.logo, size: 38, radius: 9),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star,
                            color: Color(0xFFF5A623), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          '${merchant.rating}分',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '| 月售 ${merchant.monthSold}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 14, thickness: 0.5, color: AppColors.divider),
          if (mealClosed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                MealOrderDeadline.deadlineHint,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.accent.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '加菜可在套餐点餐页选择，按加菜价格另计',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
          Expanded(child: _buildPackageArea(applicable)),
        ],
      ),
    );
  }

  Widget _buildPackageArea(List<MealPackage> applicable) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 3,
        ),
      );
    }
    if (applicable.isEmpty) {
      return Center(
        child: Text(
          packages.isEmpty
              ? '暂无套餐，请联系商家'
              : '该餐段暂无套餐，请联系商家',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: _PackageSection(
        packages: applicable,
        mealClosed: mealClosed,
        onPackageTap: onPackageTap,
      ),
    );
  }
}

class _PackageSection extends StatelessWidget {
  final List<MealPackage> packages;
  final bool mealClosed;
  final ValueChanged<MealPackage> onPackageTap;

  const _PackageSection({
    required this.packages,
    required this.mealClosed,
    required this.onPackageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '套餐推荐',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 118,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: packages.length,
          itemBuilder: (_, i) => RepaintBoundary(
            key: ValueKey(packages[i].id),
            child: _PackageCard(
              package: packages[i],
              mealClosed: mealClosed,
              onOpen: () => onPackageTap(packages[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  final MealPackage package;
  final bool mealClosed;
  final VoidCallback onOpen;

  const _PackageCard({
    required this.package,
    required this.mealClosed,
    required this.onOpen,
  });

  String _rulesLabel() {
    final r = package.rules;
    final parts = <String>[];
    if (r.meat > 0) parts.add('${r.meat}荤');
    if (r.vegetable > 0) parts.add('${r.vegetable}素');
    return parts.isEmpty ? '套餐' : parts.join('');
  }

  void _handleTap(BuildContext context) {
    if (mealClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(MealOrderDeadline.deadlineHint)),
      );
      return;
    }
    onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final titleColor =
        mealClosed ? AppColors.textTertiary : AppColors.textPrimary;
    final priceColor =
        mealClosed ? AppColors.textSecondary : AppColors.accent;
    final rulesColor = AppColors.textSecondary;
    final borderColor = mealClosed
        ? AppColors.divider
        : AppColors.primary.withValues(alpha: 0.28);
    final buttonBg =
        mealClosed ? AppColors.divider : AppColors.primary;
    final buttonFg =
        mealClosed ? AppColors.textTertiary : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 118,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: mealClosed
                    ? AppColors.background.withValues(alpha: 0.6)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    package.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '¥${package.basePrice.toStringAsFixed(package.basePrice % 1 == 0 ? 0 : 2)}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: priceColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _rulesLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      color: rulesColor,
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: buttonBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        mealClosed ? '已截止' : '去选菜',
                        style: TextStyle(
                          color: buttonFg,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 餐段切换（按当前商家截止时间展示，分段卡片样式）
class _EmployeeMealTypeTabs extends StatelessWidget {
  final MealType selected;
  final Merchant merchant;
  final List<MealType> visibleMealTypes;
  final ValueChanged<MealType> onChanged;

  const _EmployeeMealTypeTabs({
    required this.selected,
    required this.merchant,
    required this.visibleMealTypes,
    required this.onChanged,
  });

  String _subtitle(MealType t) {
    final open = MealOrderDeadline.isMealOpenFor(t, merchant: merchant);
    final closed = MealOrderDeadline.isClosedFor(t, merchant: merchant);
    if (!open) return '未开放';
    if (closed) return '已截止';
    return '${MealOrderDeadline.deadlineLabel(t, merchant: merchant)}截止';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: visibleMealTypes.map((t) {
          final isSelected = t == selected;
          final open = MealOrderDeadline.isMealOpenFor(t, merchant: merchant);
          final closed = MealOrderDeadline.isClosedFor(t, merchant: merchant);
          final subtitle = _subtitle(t);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onChanged(t),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryLight
                          : AppColors.background.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.divider.withValues(alpha: 0.85),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: isSelected ? 16 : 14,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primaryDark
                                : (open && !closed
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: closed || !open
                                ? AppColors.textTertiary
                                : (isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
