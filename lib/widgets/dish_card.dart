import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dish_model.dart';
import '../theme/app_theme.dart';
import 'dish_asset_image.dart';

/// 菜品图占位（保持旧签名以避免改动其他页面 import）
///
/// 内部全部委托给 [DishAssetImage]——优先级：
/// 1. `imageUrl` 是网络地址 → Image.network
/// 2. 通过 `dishName` 命中 `assets/images/dishes/*.png`
/// 3. 通用空白瓷盘占位（纯色 + 圆形阴影，**不再使用任何 emoji**）
class DishImagePlaceholder extends StatelessWidget {
  final double size;
  final String seed; // 历史参数，保留以兼容旧调用
  final double radius;
  final String? imageUrl;
  final String? dishName;
  final double? width;
  final double? height;

  const DishImagePlaceholder({
    super.key,
    this.size = 70,
    required this.seed,
    this.radius = 10,
    this.imageUrl,
    this.dishName,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return DishAssetImage(
      imageUrl: imageUrl,
      dishName: dishName,
      width: width ?? size,
      height: height ?? size,
      radius: radius,
    );
  }
}

/// 员工端首页菜品卡片（右侧列表）—— 严格还原 02_employee_home.png
///
/// 视觉规范：
/// - 菜品图 92x72，圆角 10
/// - 菜名 15pt 黑色
/// - 标签胶囊：浅绿底 + 绿色文字
/// - 价格 17pt 橙色 ¥
/// - 右侧 - / 数量输入 / + 控件（高度 30）
class DishCard extends StatefulWidget {
  final Dish dish;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantitySet;
  final bool disabled;
  final String? disabledHint;
  /// 展示价（如首页加菜优先 extraPrice）；未设置则用 dish.price。
  final double? displayPrice;

  const DishCard({
    super.key,
    required this.dish,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onQuantitySet,
    this.disabled = false,
    this.disabledHint,
    this.displayPrice,
  });

  @override
  State<DishCard> createState() => _DishCardState();
}

class _DishCardState extends State<DishCard> {
  late final TextEditingController _qtyController;
  static const double _controlSize = 30;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: _displayText(widget.quantity));
  }

  @override
  void didUpdateWidget(covariant DishCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity) {
      final next = _displayText(widget.quantity);
      if (_qtyController.text != next) {
        _qtyController.text = next;
      }
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  String _displayText(int cartQty) => cartQty > 0 ? '$cartQty' : '1';

  String _formatPrice(double p) {
    if (p % 1 == 0) return p.toStringAsFixed(0);
    if ((p * 10) % 1 == 0) return p.toStringAsFixed(1);
    return p.toStringAsFixed(2);
  }

  int _parseInput(String raw) {
    final v = int.tryParse(raw.trim()) ?? 1;
    return v.clamp(1, 999);
  }

  void _commitInput() {
    final qty = _parseInput(_qtyController.text);
    _qtyController.text = '$qty';
    widget.onQuantitySet(qty);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            children: [
              DishAssetImage(
                imageUrl: widget.dish.image,
                dishName: widget.dish.name,
                width: 92,
                height: 72,
                radius: 10,
              ),
              if (widget.disabled)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.disabledHint ?? '不可选',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.dish.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (widget.dish.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: widget.dish.tags
                        .take(2)
                        .map((tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500),
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '¥${_formatPrice(widget.displayPrice ?? widget.dish.price)}',
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _RoundIconButton(
            icon: Icons.remove,
            onTap: widget.disabled ? null : widget.onRemove,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            height: _controlSize,
            child: TextField(
              controller: _qtyController,
              enabled: !widget.disabled,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onSubmitted: (_) => _commitInput(),
              onEditingComplete: _commitInput,
              onTapOutside: (_) => _commitInput(),
            ),
          ),
          const SizedBox(width: 6),
          _RoundIconButton(
            icon: Icons.add,
            onTap: widget.disabled ? null : widget.onAdd,
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final inactive = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: inactive
              ? AppColors.divider
              : AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: inactive ? AppColors.textTertiary : Colors.white,
          size: 18,
        ),
      ),
    );
  }
}
