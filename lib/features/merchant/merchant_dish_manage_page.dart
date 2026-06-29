import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/dish_model.dart';
import '../../state/merchant_dish_state.dart';
import '../../state/merchant_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/dish_card.dart';
import 'dish_editor_sheet.dart';
import 'merchant_package_manage_page.dart';

/// 商家菜品管理 - 严格参考 09_merchant_dish_manage.png
class MerchantDishManagePage extends StatefulWidget {
  const MerchantDishManagePage({super.key});

  @override
  State<MerchantDishManagePage> createState() =>
      _MerchantDishManagePageState();
}

/// 顶部 Tab：菜品库 / 套餐管理 / 加菜管理
enum _ManageTab { library, packages, extras }

class _MerchantDishManagePageState extends State<MerchantDishManagePage> {
  MealType? _filter;
  _ManageTab _tab = _ManageTab.library;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final merchantId =
        context.read<MerchantState>().currentMerchant.id;
    await context.read<MerchantDishState>().refreshFor(merchantId);
  }

  @override
  Widget build(BuildContext context) {
    final dishState = context.watch<MerchantDishState>();
    // 菜品库 / 加菜管理 按 category 过滤；套餐管理是独立子页
    final mealTypeFiltered = dishState
        .byMealType(_filter)
        .where((d) => d.mealType.isOrderMealType)
        .toList();
    final filtered = _tab == _ManageTab.extras
        ? mealTypeFiltered.where((d) => d.category == DishCategory.extra).toList()
        : _tab == _ManageTab.library
            ? mealTypeFiltered.where((d) => d.category != DishCategory.extra).toList()
            : <Dish>[];

    final grouped = <MealType, List<Dish>>{};
    for (final d in filtered) {
      grouped.putIfAbsent(d.mealType, () => []).add(d);
    }
    final orderedTypes = kOrderMealTypes
        .where((t) => grouped[t]?.isNotEmpty == true)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '菜品管理',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '菜品库 / 套餐管理 / 加菜管理',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_tab != _ManageTab.packages) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showEditor(
                        presetCategory: _tab == _ManageTab.extras
                            ? DishCategory.extra
                            : null,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        _tab == _ManageTab.extras ? '新增加菜' : '新增菜品',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 顶部分段 Tab
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _ManageTabBar(
                current: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
            if (_tab != _ManageTab.packages)
              _FilterRow(
                selected: _filter,
                counts: {
                  null: dishState.dishes.length,
                  MealType.breakfast:
                      dishState.countByMealType(MealType.breakfast),
                  MealType.lunch:
                      dishState.countByMealType(MealType.lunch),
                  MealType.dinner:
                      dishState.countByMealType(MealType.dinner),
                },
                onChanged: (v) => setState(() => _filter = v),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: _tab == _ManageTab.packages
                  ? const MerchantPackageManagePanel()
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _tab == _ManageTab.extras ? '暂无加菜' : '暂无菜品',
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: orderedTypes.length,
                          itemBuilder: (_, i) {
                            final type = orderedTypes[i];
                            final list = grouped[type]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _GroupHeader(type: type, count: list.length),
                                ...list.map(
                                  (d) => _DishManageCard(
                                    dish: d,
                                    onToggle: (v) => context
                                        .read<MerchantDishState>()
                                        .toggleAvailable(d.id, v),
                                    onToggleSoldOut: (v) => context
                                        .read<MerchantDishState>()
                                        .toggleSoldOut(d.id, v),
                                    onEdit: () => _showEditor(dish: d),
                                    onTakedown: () => context
                                        .read<MerchantDishState>()
                                        .toggleAvailable(d.id, false),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditor({Dish? dish, DishCategory? presetCategory}) async {
    await DishEditorSheet.show(
      context,
      dish: dish,
      presetCategory: presetCategory,
    );
  }
}

class _ManageTabBar extends StatelessWidget {
  final _ManageTab current;
  final ValueChanged<_ManageTab> onChanged;
  const _ManageTabBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = <(_ManageTab, String)>[
      (_ManageTab.library, '菜品库'),
      (_ManageTab.packages, '套餐管理'),
      (_ManageTab.extras, '加菜管理'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: items.map((it) {
          final active = it.$1 == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(it.$1),
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  it.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textSecondary,
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.chevron_left,
                color: AppColors.textPrimary, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const Expanded(
            child: Text(
              '非攻云餐 · 商家端',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const AppLogo(size: 40, radius: 10),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final MealType? selected;
  final Map<MealType?, int> counts;
  final ValueChanged<MealType?> onChanged;

  const _FilterRow({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 参考图仅展示：全部 / 早餐 / 中餐 / 晚餐
    final items = <(String, MealType?)>[
      ('全部', null),
      ('早餐', MealType.breakfast),
      ('中餐', MealType.lunch),
      ('晚餐', MealType.dinner),
    ];

    return SizedBox(
      height: 44,
      child: Row(
        children: items.map((item) {
          final active = item.$2 == selected;
          final count = counts[item.$2] ?? 0;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(item.$2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: 14,
                          color: active
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primaryLight
                              : AppColors.divider,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            color: active
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 2.5,
                    width: 28,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final MealType type;
  final int count;

  const _GroupHeader({required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${type.label} ($count)',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Row(
            children: const [
              Text(
                '管理',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              Icon(Icons.keyboard_arrow_down,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _DishManageCard extends StatelessWidget {
  final Dish dish;
  final ValueChanged<bool> onToggle;
  final ValueChanged<bool> onToggleSoldOut;
  final VoidCallback onEdit;
  final VoidCallback onTakedown;

  const _DishManageCard({
    required this.dish,
    required this.onToggle,
    required this.onToggleSoldOut,
    required this.onEdit,
    required this.onTakedown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DishImagePlaceholder(
            seed: dish.id,
            size: 76,
            imageUrl: dish.image,
            dishName: dish.name,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dish.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: dish.isSoldOut
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                  ),
                ),
                if (dish.isSoldOut)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '已售罄',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                if (dish.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: dish.tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                if (dish.tags.isNotEmpty) const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dish.mealType.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '¥ ${dish.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: dish.isAvailable,
                      onChanged: onToggle,
                      activeTrackColor:
                          AppColors.primary.withValues(alpha: 0.5),
                      activeThumbColor: AppColors.primary,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Text(
                    dish.isAvailable ? '上架' : '下架',
                    style: TextStyle(
                      fontSize: 12,
                      color: dish.isAvailable
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _SmallOutlineBtn(
                    label: '编辑',
                    color: AppColors.textSecondary,
                    onPressed: onEdit,
                  ),
                  const SizedBox(width: 8),
                  _SmallOutlineBtn(
                    label: dish.isSoldOut ? '取消售罄' : '售罄',
                    color: AppColors.accent,
                    onPressed: dish.isAvailable
                        ? () => onToggleSoldOut(!dish.isSoldOut)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _SmallOutlineBtn(
                    label: '下架',
                    color: AppColors.accent,
                    onPressed: dish.isAvailable ? onTakedown : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallOutlineBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _SmallOutlineBtn({
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.7)),
        minimumSize: const Size(52, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}
