import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../utils/label_print_settings.dart';
import '../../widgets/app_button.dart';

Future<LabelPrintSettings?> showMerchantLabelPrintSettingsSheet(
  BuildContext context, {
  LabelPrintSettings? initial,
}) {
  return showModalBottomSheet<LabelPrintSettings>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MerchantLabelPrintSettingsSheet(initial: initial),
  );
}

class MerchantLabelPrintSettingsSheet extends StatefulWidget {
  final LabelPrintSettings? initial;

  const MerchantLabelPrintSettingsSheet({super.key, this.initial});

  @override
  State<MerchantLabelPrintSettingsSheet> createState() =>
      _MerchantLabelPrintSettingsSheetState();
}

class _MerchantLabelPrintSettingsSheetState
    extends State<MerchantLabelPrintSettingsSheet> {
  late LabelPrintSettings _settings;
  late TextEditingController _widthCtrl;
  late TextEditingController _heightCtrl;

  @override
  void initState() {
    super.initState();
    _settings = (widget.initial ?? LabelPrintSettings.current).copy();
    _widthCtrl = TextEditingController(
      text: _formatNum(_settings.labelWidthMm),
    );
    _heightCtrl = TextEditingController(
      text: _formatNum(_settings.labelHeightMm),
    );
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  double? _parseMm(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v < 20 || v > 120) return null;
    return v;
  }

  void _applyWidth(String raw) {
    final v = _parseMm(raw);
    if (v != null) setState(() => _settings.labelWidthMm = v);
  }

  void _applyHeight(String raw) {
    final v = _parseMm(raw);
    if (v != null) setState(() => _settings.labelHeightMm = v);
  }

  Future<void> _save() async {
    _applyWidth(_widthCtrl.text);
    _applyHeight(_heightCtrl.text);
    await _settings.persist();
    if (!mounted) return;
    Navigator.pop(context, _settings);
  }

  Future<void> _reset() async {
    final d = LabelPrintSettings.defaults();
    setState(() {
      _settings = d.copy();
      _widthCtrl.text = _formatNum(d.labelWidthMm);
      _heightCtrl.text = _formatNum(d.labelHeightMm);
    });
    await d.persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复默认标签打印设置')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 12),
            const Center(
              child: Text(
                '标签打印设置',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '标签纸宽度 (mm)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in LabelPrintSettings.widthPresets)
                  _PresetChip(
                    label: '${w.toInt()}',
                    selected: _settings.labelWidthMm == w,
                    onTap: () {
                      setState(() => _settings.labelWidthMm = w);
                      _widthCtrl.text = _formatNum(w);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _widthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,1})?')),
              ],
              decoration: const InputDecoration(
                hintText: '自定义宽度 (20–120mm)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: _applyWidth,
            ),
            const SizedBox(height: 16),
            const Text(
              '标签纸高度 (mm)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in LabelPrintSettings.heightPresets)
                  _PresetChip(
                    label: '${h.toInt()}',
                    selected: _settings.labelHeightMm == h,
                    onTap: () {
                      setState(() => _settings.labelHeightMm = h);
                      _heightCtrl.text = _formatNum(h);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _heightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,1})?')),
              ],
              decoration: const InputDecoration(
                hintText: '自定义高度 (20–120mm)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: _applyHeight,
            ),
            const SizedBox(height: 16),
            const Text(
              '字体大小',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<LabelFontScale>(
              segments: LabelFontScale.values
                  .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                  .toList(),
              selected: {_settings.fontScale},
              onSelectionChanged: (v) =>
                  setState(() => _settings.fontScale = v.first),
            ),
            const SizedBox(height: 16),
            const Text(
              '打印内容',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示套餐'),
              value: _settings.showPackage,
              onChanged: (v) => setState(() => _settings.showPackage = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示荤菜'),
              value: _settings.showMeat,
              onChanged: (v) => setState(() => _settings.showMeat = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示素菜'),
              value: _settings.showVegetable,
              onChanged: (v) => setState(() => _settings.showVegetable = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示加菜'),
              value: _settings.showExtra,
              onChanged: (v) => setState(() => _settings.showExtra = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示备注'),
              value: _settings.showRemark,
              onChanged: (v) => setState(() => _settings.showRemark = v),
            ),
            const SizedBox(height: 8),
            const Text(
              '打印份数',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 份')),
                ButtonSegment(value: 2, label: Text('2 份')),
              ],
              selected: {_settings.labelCopies},
              onSelectionChanged: (v) =>
                  setState(() => _settings.labelCopies = v.first),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _reset,
              child: const Text('恢复默认'),
            ),
            const SizedBox(height: 8),
            const Text(
              '请在系统打印设置中选择与标签纸一致的尺寸。当前设置仅控制标签内容排版。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            PrimaryActionButton(
              label: '保存',
              letterSpacing: 1,
              height: 48,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$label mm'),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? AppColors.accent : AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
