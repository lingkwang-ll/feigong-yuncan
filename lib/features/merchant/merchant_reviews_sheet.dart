import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/review_api.dart';
import '../../models/review_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/order_time_util.dart';
import '../../widgets/star_rating_bar.dart';

enum MerchantReviewFilter { all, good, medium, bad, withImages }

extension on MerchantReviewFilter {
  String get apiValue {
    switch (this) {
      case MerchantReviewFilter.all:
        return 'all';
      case MerchantReviewFilter.good:
        return 'good';
      case MerchantReviewFilter.medium:
        return 'medium';
      case MerchantReviewFilter.bad:
        return 'bad';
      case MerchantReviewFilter.withImages:
        return 'with_images';
    }
  }

  String get label {
    switch (this) {
      case MerchantReviewFilter.all:
        return '全部';
      case MerchantReviewFilter.good:
        return '好评';
      case MerchantReviewFilter.medium:
        return '中评';
      case MerchantReviewFilter.bad:
        return '差评';
      case MerchantReviewFilter.withImages:
        return '有图';
    }
  }
}

Future<void> showMerchantReviewsSheet(
  BuildContext context, {
  required String merchantId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => _MerchantReviewsSheet(
        merchantId: merchantId,
        scrollController: scrollController,
      ),
    ),
  );
}

class _MerchantReviewsSheet extends StatefulWidget {
  final String merchantId;
  final ScrollController scrollController;

  const _MerchantReviewsSheet({
    required this.merchantId,
    required this.scrollController,
  });

  @override
  State<_MerchantReviewsSheet> createState() => _MerchantReviewsSheetState();
}

class _MerchantReviewsSheetState extends State<_MerchantReviewsSheet> {
  MerchantReviewFilter _filter = MerchantReviewFilter.all;
  MerchantReviewsPage? _page;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ReviewApi(context.read<ApiClient>()).listForMerchant(
        filter: _filter.apiValue,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _previewImages(List<String> urls, int initialIndex) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: urls.length,
              itemBuilder: (_, i) {
                final url = urls[i];
                return InteractiveViewer(
                  child: Image.network(
                    url.startsWith('http') ? url : '${apiBaseUrl.replaceAll('/api', '')}$url',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _page?.stats;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '顾客评价',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (stats != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _StatsHeader(stats: stats),
          ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: MerchantReviewFilter.values.map((f) {
              final selected = _filter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: selected,
                  onSelected: _loading
                      ? null
                      : (_) {
                          setState(() => _filter = f);
                          _load();
                        },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : (_page?.reviews.isEmpty ?? true)
                      ? const Center(child: Text('暂无评价'))
                      : ListView.builder(
                          controller: widget.scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _page!.reviews.length,
                          itemBuilder: (_, i) =>
                              _ReviewTile(
                            review: _page!.reviews[i],
                            onImageTap: _previewImages,
                          ),
                        ),
        ),
      ],
    );
  }
}

class _StatsHeader extends StatelessWidget {
  final MerchantHygieneStatsSummary stats;

  const _StatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    final enough = stats.hasEnoughReviews;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('员工评分', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(
                  enough && stats.overallRating != null
                      ? stats.overallRating!.toStringAsFixed(1)
                      : '—',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('卫生评分', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(
                  stats.hygieneScore?.toStringAsFixed(1) ?? '—',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('卫生等级', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(
                  enough && stats.hygieneGrade != '—'
                      ? '${stats.hygieneGrade}级'
                      : '暂无',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${stats.reviewCount} 条 · ${stats.gradeLabel}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final MerchantReview review;
  final void Function(List<String> urls, int index) onImageTap;

  const _ReviewTile({required this.review, required this.onImageTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                  review.userLine,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (review.isAnonymous)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('匿名', style: TextStyle(fontSize: 10, color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              StarRatingBar(rating: review.rating, readOnly: true, size: 16),
              const SizedBox(width: 8),
              Text(
                '卫生 ${review.hygieneRating} 星',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (review.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.content, style: const TextStyle(fontSize: 14)),
          ],
          if (review.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: review.images.asMap().entries.map((e) {
                final url = e.value;
                final full = url.startsWith('http')
                    ? url
                    : '${apiBaseUrl.replaceAll('/api', '')}$url';
                return GestureDetector(
                  onTap: () => onImageTap(review.images, e.key),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      full,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.divider,
                        child: const Icon(Icons.image_not_supported, size: 20),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '订单 ${review.orderNo.isNotEmpty ? '#${review.orderNo}' : review.orderId} · ${OrderTimeUtil.formatDisplay(review.createdAt)}',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
