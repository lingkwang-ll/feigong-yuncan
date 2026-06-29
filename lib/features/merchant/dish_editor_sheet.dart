import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/dish_tags.dart';
import '../../models/dish_model.dart';
import '../../state/merchant_dish_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pick_upload.dart';
import '../../widgets/app_button.dart';
import '../../widgets/dish_card.dart';

/// 新增/编辑菜品的底部弹窗
class DishEditorSheet extends StatefulWidget {
  final Dish? dish;
  final DishCategory? presetCategory;
  const DishEditorSheet({super.key, this.dish, this.presetCategory});

  static Future<void> show(
    BuildContext context, {
    Dish? dish,
    DishCategory? presetCategory,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // 自适应屏幕高度，避免内容超出整个屏幕；键盘弹起时用 viewInsets 抬起内容
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (ctx) => DishEditorSheet(
        dish: dish,
        presetCategory: presetCategory,
      ),
    );
  }

  @override
  State<DishEditorSheet> createState() => _DishEditorSheetState();
}

class _DishEditorSheetState extends State<DishEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _extraPrice;
  late final TextEditingController _description;
  late MealType _mealType;
  late Set<MealType> _mealTypes;
  late DishCategory _category;
  late Set<String> _tags;
  late String _image;
  bool _imageUploading = false;

  final _customTagCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.dish;
    _name = TextEditingController(text: d?.name ?? '');
    _extraPrice = TextEditingController(
      text: d == null || d.extraPrice == 0 ? '' : d.extraPrice.toString(),
    );
    _description = TextEditingController(text: d?.description ?? '');
    _mealType = (d?.mealType ?? MealType.lunch).normalizedForOrdering;
    _mealTypes = Set<MealType>.of(
      (d?.mealTypes ?? const <MealType>[])
          .where((m) => m.isOrderMealType),
    );
    _category = d?.category ?? widget.presetCategory ?? DishCategory.none;
    _tags = Set.of(d?.tags ?? []);
    _image = d?.image ?? 'dish';
  }

  @override
  void dispose() {
    _name.dispose();
    _extraPrice.dispose();
    _description.dispose();
    _customTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    if (_imageUploading) return;
    final bytes = await pickImageBytes(context);
    if (bytes == null || !mounted) return;

    setState(() => _imageUploading = true);
    try {
      final url = await context
          .read<MerchantDishState>()
          .uploadDishImageBytes(bytes, 'dish_${DateTime.now().millisecondsSinceEpoch}.png');
      if (url == null || url.isEmpty) {
        throw StateError('empty url');
      }
      if (!mounted) return;
      setState(() => _image = url);
    } catch (e) {
      debugPrint('[DishEditor][UPLOAD][FAIL] error=$e');
      if (mounted) {
        _err('图片上传失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _imageUploading = false);
    }
  }

  void _addCustomTag() {
    final t = _customTagCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _tags.add(t);
      _customTagCtrl.clear();
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final extraPriceText = _extraPrice.text.trim();
    final extraPrice = extraPriceText.isEmpty
        ? 0.0
        : double.tryParse(extraPriceText);
    // 普通菜品默认价格为 0；编辑时保留已有 price，不在 UI 中展示
    final price = widget.dish?.price ?? 0.0;
    if (name.isEmpty) {
      _err('请输入菜品名称');
      return;
    }
    // 加菜分类必须填写加菜价格
    if (_category == DishCategory.extra) {
      if (extraPrice == null || extraPrice <= 0) {
        _err('加菜分类必须填写加菜价格');
        return;
      }
    }
    final state = context.read<MerchantDishState>();
    if (widget.dish == null) {
      await state.addDish(
        name: name,
        price: price,
        description: _description.text.trim(),
        mealType: _mealType,
        tags: _tags.toList(),
        image: _image,
        category: _category,
        extraPrice: extraPrice ?? 0,
        mealTypes: _mealTypes.toList(),
      );
    } else {
      await state.updateDish(
        widget.dish!.copyWith(
          name: name,
          price: price,
          description: _description.text.trim(),
          mealType: _mealType,
          tags: _tags.toList(),
          image: _image,
          category: _category,
          extraPrice: extraPrice ?? 0,
          mealTypes: _mealTypes.toList(),
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.dish == null ? '菜品已新增' : '菜品已保存'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.dish != null;
    // 键盘弹起时把内容/按钮整体抬起，避免遮挡
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsetsBottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 固定头部：拖拽条 + 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isEdit ? '编辑菜品' : '新增菜品',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // 中间可滚动表单
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _buildForm(),
              ),
            ),
            // 固定底部保存按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PrimaryActionButton(
                label: '保 存',
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: GestureDetector(
            onTap: _imageUploading ? null : _pickAndUploadImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                DishImagePlaceholder(
                  seed: _image,
                  size: 88,
                  radius: 12,
                  imageUrl: _image,
                ),
                if (_imageUploading)
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 14),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _label('菜品名称'),
        TextField(
          controller: _name,
          decoration: const InputDecoration(hintText: '请输入菜品名称'),
        ),
        const SizedBox(height: 12),
        _label('菜品分类'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            DishCategory.meat,
            DishCategory.vegetable,
            DishCategory.staple,
            DishCategory.soup,
            DishCategory.drink,
            DishCategory.extra,
          ].map((c) {
            final active = c == _category;
            return GestureDetector(
              onTap: () => setState(() => _category = c),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? Colors.white : AppColors.primary,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_category == DishCategory.extra) ...[
          _label('加菜价格（必填）'),
          TextField(
            controller: _extraPrice,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '例如：6',
              prefixText: '¥ ',
            ),
          ),
          const SizedBox(height: 12),
        ],
        _label('菜品描述'),
        TextField(
          controller: _description,
          maxLines: 2,
          decoration: const InputDecoration(
              hintText: '描述菜品口味、原料等（选填）'),
        ),
        const SizedBox(height: 12),
        _label('主餐段'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kOrderMealTypes.map((t) {
            final active = t == _mealType;
            return GestureDetector(
              onTap: () => setState(() => _mealType = t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? Colors.white : AppColors.primary,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _label('适用餐段（多选，留空按主餐段）'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kOrderMealTypes.map((t) {
            final active = _mealTypes.contains(t);
            return GestureDetector(
              onTap: () => setState(() {
                if (active) {
                  _mealTypes.remove(t);
                } else {
                  _mealTypes.add(t);
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent
                      : AppColors.accentLight,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? Colors.white : AppColors.accent,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _label('标签'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kBuiltinDishTags.map((t) {
            final active = _tags.contains(t);
            return GestureDetector(
              onTap: () => setState(() {
                if (active) {
                  _tags.remove(t);
                } else {
                  _tags.add(t);
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent
                      : AppColors.accentLight,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? Colors.white : AppColors.accent,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_tags.any((t) => !kBuiltinDishTags.contains(t))) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags
                .where((t) => !kBuiltinDishTags.contains(t))
                .map((t) => InputChip(
                      label: Text(t),
                      onDeleted: () => setState(() => _tags.remove(t)),
                      deleteIconColor: AppColors.primary,
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customTagCtrl,
                decoration: const InputDecoration(
                  hintText: '自定义标签',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _addCustomTag,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
              child: const Text('添加'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
