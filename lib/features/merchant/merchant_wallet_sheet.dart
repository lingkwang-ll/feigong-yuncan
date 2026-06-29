import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/merchant_api.dart';
import '../../api/payment_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

void showMerchantWalletSheet(BuildContext context, String merchantId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.92,
    ),
    builder: (ctx) => _MerchantWalletSheet(merchantId: merchantId),
  );
}

class _MerchantWalletSheet extends StatefulWidget {
  final String merchantId;
  const _MerchantWalletSheet({required this.merchantId});

  @override
  State<_MerchantWalletSheet> createState() => _MerchantWalletSheetState();
}

class _MerchantWalletSheetState extends State<_MerchantWalletSheet> {
  Future<MerchantWalletSummary>? _walletFuture;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _reload();
    }
  }

  void _reload() {
    if (AppConfig.dataSourceMode != DataSourceMode.api) {
      _walletFuture = Future.value(
        const MerchantWalletSummary(
          withdrawableAmount: 0,
          pendingSettlementAmount: 0,
          withdrawingAmount: 0,
          withdrawnAmount: 0,
          settlementRuleText: '订单完成满7天后可提现',
        ),
      );
      return;
    }
    _walletFuture = MerchantApi(context.read<ApiClient>())
        .getWallet(merchantId: widget.merchantId);
  }

  void _refresh() {
    setState(() => _reload());
  }

  String _money(double v) => '¥${v.toStringAsFixed(2)}';

  Future<void> _showWithdrawDialog(MerchantWalletSummary wallet) async {
    final amountCtrl = TextEditingController(
      text: wallet.withdrawableAmount > 0
          ? wallet.withdrawableAmount.toStringAsFixed(2)
          : '',
    );
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: '银行卡');
    final noCtrl = TextEditingController();
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('申请提现'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '可提现金额：${_money(wallet.withdrawableAmount)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '本次提现金额',
                    hintText: '请输入提现金额',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '收款户名'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: '账户类型',
                    hintText: '如：银行卡 / 支付宝',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noCtrl,
                  decoration: const InputDecoration(labelText: '收款账号'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('提现金额必须大于 0')),
                        );
                        return;
                      }
                      if (amount > wallet.withdrawableAmount + 0.001) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('提现金额不能超过可提现金额')),
                        );
                        return;
                      }
                      setDialog(() => submitting = true);
                      try {
                        await MerchantApi(context.read<ApiClient>())
                            .createWithdrawal(
                          merchantId: widget.merchantId,
                          amount: amount,
                          accountName: nameCtrl.text.trim(),
                          accountType: typeCtrl.text.trim(),
                          accountNo: noCtrl.text.trim(),
                        );
                        if (!context.mounted) return;
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('提现申请已提交，等待平台审核')),
                        );
                        _refresh();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('提交失败：$e')),
                        );
                      } finally {
                        if (ctx.mounted) setDialog(() => submitting = false);
                      }
                    },
              child: Text(submitting ? '提交中…' : '提交申请'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawalsList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FutureBuilder<List<MerchantWithdrawalRecord>>(
        future: MerchantApi(context.read<ApiClient>())
            .listWithdrawals(merchantId: widget.merchantId),
        builder: (context, snap) {
          final list = snap.data ?? const [];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '提现记录',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '暂无提现记录',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = list[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_money(r.amount)),
                          subtitle: Text(r.createdAt),
                          trailing: Text(
                            r.statusLabel,
                            style: TextStyle(
                              color: r.status == 'rejected'
                                  ? AppColors.accent
                                  : AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettlementDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FutureBuilder<List<MerchantSettlementDetail>>(
        future: MerchantApi(context.read<ApiClient>())
            .listSettlementDetails(merchantId: widget.merchantId),
        builder: (context, snap) {
          final list = snap.data ?? const [];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '结算明细',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '暂无结算明细',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = list[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('订单 ${s.orderNo}'),
                          subtitle: Text(
                            '${s.statusLabel} · ${_money(s.merchantReceivableAmount)}',
                          ),
                          trailing: Text(
                            s.settlementEligibleAt != null
                                ? s.settlementEligibleAt!.substring(0, 10)
                                : '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _auxCard(String title, String value, String hint) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MerchantWalletSummary>(
      future: _walletFuture,
      builder: (context, snap) {
        if (_walletFuture == null ||
            snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                const SizedBox(height: 40),
                const CircularProgressIndicator(strokeWidth: 2),
              ],
            ),
          );
        }

        final w = snap.data;
        final canWithdraw = (w?.withdrawableAmount ?? 0) > 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              const Text(
                '我的钱包',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              if (w == null)
                const Expanded(
                  child: Center(
                    child: Text(
                      '暂无钱包数据',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '可提现金额',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _money(w.withdrawableAmount),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '当前已完成结算、可申请提现的金额',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PrimaryActionButton(
                          label: canWithdraw ? '申请提现' : '暂无可提现金额',
                          onPressed:
                              canWithdraw ? () => _showWithdrawDialog(w) : null,
                        ),
                        const SizedBox(height: 20),
                        _auxCard(
                          '待结算金额',
                          _money(w.pendingSettlementAmount),
                          '已完成订单，仍在结算期内，暂不可提现。',
                        ),
                        const SizedBox(height: 10),
                        _auxCard(
                          '结算中金额',
                          _money(w.withdrawingAmount),
                          '已申请提现，平台处理中。',
                        ),
                        const SizedBox(height: 10),
                        _auxCard(
                          '已提现金额',
                          _money(w.withdrawnAmount),
                          '历史已提现成功金额。',
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '结算说明',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '订单完成后，金额会进入结算期。结算完成后可申请提现。\n${w.settlementRuleText}，金额将自动进入可提现余额。',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _showWithdrawalsList,
                                child: const Text('提现记录'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _showSettlementDetails,
                                child: const Text('结算明细'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
