import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/dish_review_model.dart';
import '../../state/review_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/star_rating_bar.dart';
import 'merchant_review_display.dart';

/// 商家端查看菜品历史评价 BottomSheet
class MerchantDishReviewSheet extends StatelessWidget {
  final String dishName;
  final List<DishReview> reviews;

  const MerchantDishReviewSheet({
    super.key,
    required this.dishName,
    required this.reviews,
  });

  static Future<void> show(
    BuildContext context, {
    required String dishId,
    required String dishName,
    required String merchantId,
  }) {
    final reviewState = context.read<ReviewState>();
    final reviews = reviewState
        .reviewsForDish(dishId)
        .where((r) => r.merchantId == merchantId)
        .toList();

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: reviews.isEmpty ? 0.38 : 0.58,
        maxChildSize: 0.88,
        minChildSize: 0.32,
        expand: false,
        builder: (_, __) => MerchantDishReviewSheet(
          dishName: dishName,
          reviews: reviews,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '菜品评价',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dishName,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: reviews.isEmpty
              ? const Center(
                  child: Text(
                    '暂无评价',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: reviews.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = reviews[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                merchantEmployeeDisplayName(r.userId),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                df.format(r.createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          StarRatingBar(
                            rating: r.rating,
                            readOnly: true,
                            size: 18,
                          ),
                          if (r.comment.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              r.comment,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '订单 ${r.orderId}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: PrimaryActionButton(
            label: '关闭',
            letterSpacing: 2,
            height: 48,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
