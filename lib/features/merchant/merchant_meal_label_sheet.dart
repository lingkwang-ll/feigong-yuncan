import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/merchant_api.dart';
import '../../models/dish_model.dart';
import '../../models/order_model.dart';
import '../../state/merchant_conversation_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/browser_print.dart';
import '../../utils/label_print_html.dart';
import '../../utils/label_print_settings.dart';
import '../../utils/meal_batch_aggregator.dart';
import '../../utils/meal_label_print_status.dart';
import '../../widgets/app_button.dart';
import '../../widgets/merchant_order_chat_action.dart';
import 'merchant_label_print_settings_sheet.dart';

/// 餐盒标签预览 / 打印（支持已打印状态筛选）
class MerchantMealLabelSheet extends StatefulWidget {
  final MealBatchSummary batch;

  const MerchantMealLabelSheet({super.key, required this.batch});

  static Future<void> show(
    BuildContext context, {
    required MealBatchSummary batch,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scroll) => MerchantMealLabelSheet(batch: batch),
      ),
    );
  }

  @override
  State<MerchantMealLabelSheet> createState() => _MerchantMealLabelSheetState();
}

class _MerchantMealLabelSheetState extends State<MerchantMealLabelSheet> {
  LabelPrintSettings _settings = LabelPrintSettings.current;
  MealLabelPrintFilter _filter = MealLabelPrintFilter.unprinted;
  List<MealLabelGroup> _groups = [];
  bool _loadingStatus = false;

  @override
  void initState() {
    super.initState();
    _groups = widget.batch.printableLabelGroups;
    _loadSettings();
    _loadPrintStatus();
  }

  Future<void> _loadSettings() async {
    await LabelPrintSettings.load();
    if (!mounted) return;
    setState(() => _settings = LabelPrintSettings.current.copy());
  }

  Future<void> _loadPrintStatus() async {
    if (AppConfig.dataSourceMode != DataSourceMode.api) return;
    setState(() => _loadingStatus = true);
    try {
      final api = MerchantApi(context.read<ApiClient>());
      final items = await api.getMealLabelPrintStatus(
        businessDate: formatBusinessDate(widget.batch.date),
        mealType: widget.batch.mealType.name,
        merchantId: widget.batch.merchantId,
      );
      final map = parseMealLabelPrintStatusMap(items);
      if (!mounted) return;
      setState(() {
        _groups = applyMealLabelPrintStatus(
          widget.batch.printableLabelGroups,
          map,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _groups = widget.batch.printableLabelGroups);
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  List<MealLabelGroup> get _filteredGroups =>
      filterMealLabelGroups(_groups, _filter);

  int get _totalPrintPages {
    final copies = _settings.labelCopies.clamp(1, 2);
    return _filteredGroups.length * copies;
  }

  Order? _orderForGroup(MealLabelGroup group) {
    if (group.orderId.isEmpty) return null;
    for (final o in widget.batch.sourceOrders) {
      if (o.id == group.orderId) return o;
    }
    return null;
  }

  Future<void> _printAll() async {
    final targets = _filteredGroups;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前筛选下暂无可打印标签')),
      );
      return;
    }

    if (_filter != MealLabelPrintFilter.unprinted &&
        targets.any((g) => g.isLabelPrinted)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重复打印提示'),
          content: const Text('包含已打印标签，可能造成重复打印，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续打印'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final html = LabelPrintHtml.buildDocument(targets, _settings);
    openPrintHtmlDocument(html);

    if (!mounted || AppConfig.dataSourceMode != DataSourceMode.api) return;
    final mark = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标记已打印'),
        content: Text('是否将本次 ${targets.length} 张标签标记为已打印？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不标记'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('标记已打印'),
          ),
        ],
      ),
    );
    if (mark != true || !mounted) return;

    try {
      final api = MerchantApi(context.read<ApiClient>());
      await api.markMealLabelsPrinted(
        businessDate: formatBusinessDate(widget.batch.date),
        mealType: widget.batch.mealType.name,
        merchantId: widget.batch.merchantId,
        labels: targets
            .map(
              (g) => {
                'orderId': g.orderId,
                'labelCode': g.labelCode,
                'employeeName': g.employeeName,
                'department': g.department,
                'packageName': g.primaryPackageName,
              },
            )
            .toList(),
      );
      await _loadPrintStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已标记为已打印')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记失败：$e')),
      );
    }
  }

  Future<void> _openSettings() async {
    final next = await showMerchantLabelPrintSettingsSheet(
      context,
      initial: _settings,
    );
    if (next != null && mounted) {
      setState(() => _settings = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final filtered = _filteredGroups;
    final unprintedCount =
        filterMealLabelGroups(_groups, MealLabelPrintFilter.unprinted).length;

    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Text(
                '餐盒标签预览',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (_loadingStatus)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              Text(
                '${widget.batch.mealType.label} · ${df.format(widget.batch.date)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text(
                '共 $_totalPrintPages 张标签 · 未打印 $unprintedCount 张',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '标签尺寸：${_settings.sizeLabel}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<MealLabelPrintFilter>(
            segments: const [
              ButtonSegment(
                value: MealLabelPrintFilter.unprinted,
                label: Text('未打印'),
              ),
              ButtonSegment(
                value: MealLabelPrintFilter.printed,
                label: Text('已打印'),
              ),
              ButtonSegment(
                value: MealLabelPrintFilter.all,
                label: Text('全部'),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _filter == MealLabelPrintFilter.unprinted
                        ? '暂无未打印标签'
                        : '当前筛选下暂无标签',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filtered
                        .map(
                          (g) => _MiniLabelCard(
                            group: g,
                            order: _orderForGroup(g),
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlineAccentButton(
                  label: '标签设置',
                  onPressed: _openSettings,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryActionButton(
                  label: _filter == MealLabelPrintFilter.unprinted
                      ? '打印全部标签'
                      : '打印当前列表',
                  letterSpacing: 1,
                  height: 48,
                  onPressed: filtered.isEmpty ? null : _printAll,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniLabelCard extends StatelessWidget {
  final MealLabelGroup group;
  final Order? order;

  const _MiniLabelCard({
    required this.group,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<MerchantConversationState>().unreadForOrder(
          group.orderId,
        );
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  group.labelCode,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const Spacer(),
                _PrintStatusChip(group: group),
                if (unread > 0) ...[
                  const SizedBox(width: 4),
                  MerchantUnreadBadge(count: unread, size: 14),
                ] else if (order != null && unread > 0)
                  MerchantOrderChatAction(
                    order: order!,
                    iconOnly: true,
                    unreadCount: unread,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...group.displayLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: line.contains('｜') ? 15 : 13,
                    fontWeight:
                        line.contains('｜') ? FontWeight.w700 : FontWeight.w400,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
            ),
            if (group.remark.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '备注：${group.remark.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrintStatusChip extends StatelessWidget {
  final MealLabelGroup group;

  const _PrintStatusChip({required this.group});

  @override
  Widget build(BuildContext context) {
    final printed = group.isLabelPrinted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: printed
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        printed
            ? '已打印 x${group.labelPrintCount}'
            : '未打印',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: printed ? const Color(0xFF2E7D32) : AppColors.accent,
        ),
      ),
    );
  }
}
