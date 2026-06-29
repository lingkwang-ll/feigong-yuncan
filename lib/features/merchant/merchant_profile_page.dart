import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/payment_api.dart';
import '../../api/api_client.dart';
import '../../api/merchant_api.dart';
import '../../api/api_config.dart';
import '../../models/merchant_model.dart';
import '../../state/app_state.dart';
import '../../state/merchant_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import 'merchant_label_print_settings_sheet.dart';
import 'merchant_profile_sheets.dart';
import 'merchant_reviews_sheet.dart';
import '../../state/support_conversation_state.dart';
import '../chat/support_conversation_page.dart';
import 'merchant_coupon_manage_page.dart';

/// 商家"我的" / 收款码设置
class MerchantProfilePage extends StatefulWidget {
  const MerchantProfilePage({super.key});

  @override
  State<MerchantProfilePage> createState() => _MerchantProfilePageState();
}

class _MerchantProfilePageState extends State<MerchantProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshProfile());
  }

  Future<void> _refreshProfile() async {
    final userId = context.read<AppState>().currentUser?.id;
    if (userId == null) return;
    await context.read<MerchantState>().refreshMerchantProfile(userId);
  }

  @override
  Widget build(BuildContext context) {
    final merchantState = context.watch<MerchantState>();
    final m = merchantState.currentMerchant;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              left: 0,
              height: 120,
              child: Image.asset(
                'assets/images/ui/profile_hero_top.png',
                fit: BoxFit.cover,
                alignment: Alignment.topRight,
                filterQuality: FilterQuality.medium,
              ),
            ),
            ListView(
              padding: EdgeInsets.zero,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Center(
                    child: Text(
                      '商家端-我的 / 店铺设置',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _ShopHeader(
                    merchant: m,
                    onTap: () => showMerchantShopInfoSheet(context, m),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _BusinessStatusCard(merchant: m),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _RatingCard(
                    merchant: m,
                    onTap: m == null
                        ? null
                        : () => showMerchantReviewsSheet(
                              context,
                              merchantId: m.id,
                            ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _MenuRow(
                          label: '优惠券管理',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const MerchantCouponManagePage(),
                              ),
                            );
                          },
                        ),
                        _MenuRow(
                          label: '顾客评价',
                          onTap: () => showMerchantReviewsSheet(
                            context,
                            merchantId: m.id,
                          ),
                        ),
                        _MenuRow(
                          label: '我的钱包',
                          onTap: () => showMerchantWalletSheet(context, m.id),
                        ),
                        _MenuRow(
                          label: '我的收款码',
                          onTap: () => showMerchantPaymentQrSheet(context),
                        ),
                        _MenuRow(
                          label: '店铺信息',
                          onTap: () => showMerchantShopInfoSheet(context, m),
                        ),
                        _MenuRow(
                          label: '配送设置',
                          onTap: () => showMerchantDeliverySheet(context, m),
                        ),
                        _MenuRow(
                          label: '标签打印设置',
                          onTap: () => showMerchantLabelPrintSettingsSheet(context),
                        ),
                        _MenuRow(
                          label: '营业时间',
                          onTap: () =>
                              showMerchantBusinessHoursSheet(context, m),
                        ),
                        _MenuRow(
                          label: '联系客服',
                          unreadCount: context
                              .watch<SupportConversationState>()
                              .unreadCount,
                          onTap: () => SupportConversationPage.open(context),
                        ),
                        _MenuRow(
                          label: '设置',
                          onTap: () => showMerchantSettingsSheet(context),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  final Merchant merchant;
  final VoidCallback onTap;

  const _ShopHeader({required this.merchant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            MerchantBadgeLogo(
              seed: merchant.logo,
              size: 72,
              radius: 14,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: merchant.isOpen
                          ? AppColors.primaryLight
                          : const Color(0xFFF1F3F5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: merchant.isOpen
                              ? AppColors.primary
                              : AppColors.textTertiary,
                          size: 7,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          merchant.isOpen ? '营业中' : '休息中',
                          style: TextStyle(
                            fontSize: 13,
                            color: merchant.isOpen
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 24),
          ],
        ),
      ),
    );
  }
}

class _BusinessStatusCard extends StatelessWidget {
  final Merchant merchant;
  const _BusinessStatusCard({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '营业状态',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '休息中仍展示，但员工不可下单',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: merchant.isOpen,
            onChanged: (v) =>
                context.read<MerchantState>().setMerchantOpen(v),
            activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends StatefulWidget {
  final Merchant? merchant;
  final VoidCallback? onTap;
  const _RatingCard({required this.merchant, this.onTap});

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  MerchantHygieneStats? _hygiene;

  @override
  void initState() {
    super.initState();
    _loadHygiene();
  }

  Future<void> _loadHygiene() async {
    if (AppConfig.dataSourceMode != DataSourceMode.api) return;
    final merchant = widget.merchant;
    if (merchant == null) return;
    try {
      final stats = await MerchantApi(context.read<ApiClient>())
          .getHygieneStats(merchantId: merchant.id);
      if (mounted) setState(() => _hygiene = stats);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final merchant = widget.merchant;
    if (merchant == null) {
      return const SizedBox.shrink();
    }
    final h = _hygiene;
    final enough = h?.hasEnoughReviews ?? false;
    final grade = h?.hygieneGrade ?? merchant.hygieneGrade;
    final gradeLabel = h?.gradeLabel ?? '加载中…';
    final hygieneScore = h?.hygieneScore;
    final score30 = h?.hygieneScore30d;
    final reviewCount = h?.reviewCount ?? 0;
    final overallRating = h?.overallRating;
    final needsFix = h?.needsRemediation ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const AppLogo(size: 40, radius: 10),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '员工评分',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enough && overallRating != null
                          ? overallRating.toStringAsFixed(1)
                          : '—',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enough && overallRating != null
                          ? '共 $reviewCount 条评价'
                          : gradeLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (enough && overallRating != null)
                      Row(
                        children: List.generate(5, (i) {
                          final filled = i < overallRating.floor();
                          return Icon(
                            Icons.star,
                            size: 12,
                            color: filled
                                ? AppColors.primary
                                : AppColors.divider,
                          );
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(width: 1, height: 56, color: AppColors.divider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  const AppLogo(size: 40, radius: 10),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '卫生等级',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        enough && grade != '—' ? '$grade级' : '暂无',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: needsFix
                              ? AppColors.accent
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hygieneScore != null
                            ? '卫生评分 $hygieneScore · $reviewCount 条'
                            : gradeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (score30 != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '最近30天 $score30',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (needsFix)
                        const Text(
                          '需整改',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (widget.onTap != null)
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        ],
      ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool showDivider;
  final int unreadCount;

  const _MenuRow({
    required this.label,
    required this.onTap,
    this.showDivider = true,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const AppLogo(size: 28, radius: 7),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                const Icon(Icons.chevron_right,
                    color: AppColors.textTertiary, size: 18),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 56, endIndent: 16),
      ],
    );
  }
}
