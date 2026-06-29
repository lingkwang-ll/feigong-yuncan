import 'package:flutter/material.dart';

import '../models/dish_model.dart';
import '../theme/app_theme.dart';

/// 餐段切换 Tab（早餐 / 中餐 / 晚餐 / 加班餐）
///
/// 严格按 02_employee_home.png：
/// - 白色圆角卡片整体
/// - 选中：绿色文字 + 绿色下划线
/// - 未选中：灰黑色
/// - 使用 Flutter Icon（不允许 emoji）
class MealTypeTabs extends StatelessWidget {
  final MealType selected;
  final ValueChanged<MealType> onChanged;

  const MealTypeTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  IconData _iconFor(MealType type) {
    switch (type) {
      case MealType.breakfast:
        return Icons.wb_twilight_outlined; // 朝阳
      case MealType.lunch:
        return Icons.wb_sunny_outlined; // 正午
      case MealType.dinner:
        return Icons.nightlight_outlined; // 晚月
      case MealType.overtime:
        return Icons.work_outline; // 加班餐盒
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: MealType.values.map((t) {
          final isActive = t == selected;
          final color = isActive
              ? AppColors.primary
              : AppColors.textSecondary;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(t),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(t), size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.cutoff,
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textTertiary,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2.5,
                    width: 26,
                    decoration: BoxDecoration(
                      color: isActive
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
