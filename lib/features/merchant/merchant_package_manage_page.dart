import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/package_api.dart';
import '../../models/dish_model.dart';
import '../../models/package_model.dart';
import '../../state/merchant_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

/// 商家端"套餐管理"面板（嵌入 `MerchantDishManagePage` 的套餐 Tab）
///
/// 功能：拉取本商家全部套餐（含未启用） → 增 / 改 / 启停 / 删
class MerchantPackageManagePanel extends StatefulWidget {
  const MerchantPackageManagePanel({super.key});

  @override
  State<MerchantPackageManagePanel> createState() =>
      _MerchantPackageManagePanelState();
}

class _MerchantPackageManagePanelState
    extends State<MerchantPackageManagePanel> {
  bool _loading = true;
  List<MealPackage> _packages = const [];
  String? _error;

  late final PackageApi _api;

  @override
  void initState() {
    super.initState();
    _api = PackageApi(context.read<ApiClient>());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final merchantId = context.read<MerchantState>().currentMerchant.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listOwnPackages(merchantId: merchantId);
      if (!mounted) return;
      setState(() => _packages = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载套餐失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEditor({MealPackage? pkg}) {
    final merchantId = context.read<MerchantState>().currentMerchant.id;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // 限制最大高度，避免超过屏幕；键盘抬起时由内部 viewInsets padding 兜底
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _PackageEditorSheet(
          merchantId: merchantId,
          api: _api,
          existing: pkg,
          onSaved: _refresh,
        ),
      ),
    );
  }

  Future<void> _toggleEnabled(MealPackage pkg) async {
    try {
      await _api.setEnabled(pkg.id, !pkg.isEnabled);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$e')));
    }
  }

  Future<void> _delete(MealPackage pkg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确认删除套餐"${pkg.name}"？该操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deletePackage(pkg.id);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  String _employeeOrderHint(PackageRules r) {
    final parts = <String>[];
    if (r.meat > 0) parts.add('${r.meat} 个荤菜');
    if (r.vegetable > 0) parts.add('${r.vegetable} 个素菜');
    if (parts.isEmpty) return '';
    return '员工点餐时需选择 ${parts.join(' + ')}';
  }

  String _formatRules(PackageRules r) {
    // 业务简化：套餐只展示几荤几素；历史套餐若有 staple/soup/drink，则不再展示
    final parts = <String>[];
    if (r.meat > 0) parts.add('${r.meat}荤');
    if (r.vegetable > 0) parts.add('${r.vegetable}素');
    return parts.isEmpty ? '—' : parts.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '维护套餐规则（几荤几素 + 基础价）；加菜由员工点餐时自由选择',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增套餐'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : _packages.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无套餐，点击右上角新增',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _packages.length,
                            itemBuilder: (_, i) {
                              final p = _packages[i];
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 12, 14, 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '¥${p.basePrice.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '规则：${_formatRules(p.rules)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      if (_employeeOrderHint(p.rules)
                                          .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            _employeeOrderHint(p.rules),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.85),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      if (p.mealTypes.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 4),
                                          child: Text(
                                            '适用餐段：${p.mealTypes.map((m) => m.label).join('、')}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 4),
                                        child: Text(
                                          '状态：${p.isEnabled ? '启用' : '已停用'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          OutlinedButton(
                                            onPressed: () =>
                                                _openEditor(pkg: p),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  AppColors.primary,
                                              side: const BorderSide(
                                                  color: AppColors.primary),
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 12,
                                                  vertical: 4),
                                              minimumSize:
                                                  const Size(0, 32),
                                            ),
                                            child: const Text('编辑'),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            onPressed: () =>
                                                _toggleEnabled(p),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  AppColors.textSecondary,
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 12,
                                                  vertical: 4),
                                              minimumSize:
                                                  const Size(0, 32),
                                            ),
                                            child: Text(
                                              p.isEnabled ? '停用' : '启用',
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: () => _delete(p),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  Colors.redAccent,
                                            ),
                                            child: const Text('删除'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _PackageEditorSheet extends StatefulWidget {
  final String merchantId;
  final PackageApi api;
  final MealPackage? existing;
  final VoidCallback onSaved;
  const _PackageEditorSheet({
    required this.merchantId,
    required this.api,
    required this.existing,
    required this.onSaved,
  });

  @override
  State<_PackageEditorSheet> createState() => _PackageEditorSheetState();
}

class _PackageEditorSheetState extends State<_PackageEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _basePrice;
  late final TextEditingController _description;
  late int _meat;
  late int _vegetable;
  late Set<MealType> _mealTypes;
  late bool _isEnabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _basePrice =
        TextEditingController(text: p == null ? '' : p.basePrice.toString());
    _description = TextEditingController(text: p?.description ?? '');
    _meat = p?.rules.meat ?? 0;
    _vegetable = p?.rules.vegetable ?? 0;
    _mealTypes = Set.of(p?.mealTypes ?? const []);
    _isEnabled = p?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _basePrice.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final basePrice = double.tryParse(_basePrice.text.trim());
    if (name.isEmpty) {
      _err('请填写套餐名称');
      return;
    }
    if (basePrice == null || basePrice < 0) {
      _err('请输入正确的基础价格');
      return;
    }
    final ruleSum = _meat + _vegetable;
    if (ruleSum <= 0) {
      _err('套餐规则至少要选 1 个荤菜或素菜');
      return;
    }

    setState(() => _saving = true);
    try {
      // 仅写入 meat/vegetable，主食/汤/饮品/允许加菜不再参与新建套餐
      final rules = PackageRules(
        meat: _meat,
        vegetable: _vegetable,
      );
      if (widget.existing == null) {
        await widget.api.createPackage(
          merchantId: widget.merchantId,
          name: name,
          description: _description.text.trim(),
          basePrice: basePrice,
          mealTypes: _mealTypes.toList(),
          rules: rules,
          isEnabled: _isEnabled,
        );
      } else {
        await widget.api.updatePackage(
          widget.existing!.id,
          name: name,
          description: _description.text.trim(),
          basePrice: basePrice,
          mealTypes: _mealTypes.toList(),
          rules: rules,
          isEnabled: _isEnabled,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      _err('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _label(String text) => Padding(
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

  Widget _ruleField(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        InkWell(
          onTap: () => onChanged((value - 1).clamp(0, 20)),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.remove, size: 16),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        InkWell(
          onTap: () => onChanged((value + 1).clamp(0, 20)),
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              isEdit ? '编辑套餐' : '新增套餐',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            _label('套餐名称'),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                hintText: '例如：一荤两素套餐',
              ),
            ),
            const SizedBox(height: 12),
            _label('基础价格'),
            TextField(
              controller: _basePrice,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '例如：15',
                prefixText: '¥ ',
              ),
            ),
            const SizedBox(height: 12),
            _label('适用餐段（不勾选则全部餐段可用）'),
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
                          ? AppColors.primary
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: active ? Colors.white : AppColors.primary,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _label('套餐选择规则（只配置几荤几素，加菜在员工点餐时单独选）'),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _ruleField(
                    '荤菜', _meat, (v) => setState(() => _meat = v)),
                _ruleField(
                    '素菜', _vegetable, (v) => setState(() => _vegetable = v)),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _isEnabled,
              onChanged: (v) => setState(() => _isEnabled = v),
              title: const Text('启用'),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.primary,
            ),
            const SizedBox(height: 4),
            _label('套餐说明'),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration:
                  const InputDecoration(hintText: '介绍套餐内容（选填）'),
            ),
            const SizedBox(height: 22),
            PrimaryActionButton(
              label: _saving ? '保 存 中…' : '保 存',
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
