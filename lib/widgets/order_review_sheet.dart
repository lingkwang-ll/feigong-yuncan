import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dish_review_model.dart';
import '../models/order_model.dart';
import '../state/app_state.dart';
import '../state/review_state.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'dish_card.dart';
import 'star_rating_bar.dart';

/// 员工端订单评价弹窗
class OrderReviewSheet extends StatefulWidget {
  final Order order;

  const OrderReviewSheet({super.key, required this.order});

  static Future<bool?> show(BuildContext context, {required Order order}) {
    return showModalBottomSheet<bool>(
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
        builder: (_, scroll) => OrderReviewSheet(order: order),
      ),
    );
  }

  @override
  State<OrderReviewSheet> createState() => _OrderReviewSheetState();
}

class _OrderReviewSheetState extends State<OrderReviewSheet> {
  late final List<_DishReviewDraft> _drafts;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _drafts = [];
    for (final item in widget.order.items) {
      if (seen.add(item.dish.id)) {
        _drafts.add(_DishReviewDraft(
          dishId: item.dish.id,
          dishName: item.dish.name,
          imageUrl: item.dish.image,
        ));
      }
    }
  }

  Future<void> _submit() async {
    final invalid = _drafts.where((d) => d.rating < 1).toList();
    if (invalid.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请为每道菜品选择星级评分')),
      );
      return;
    }

    final user = context.read<AppState>().currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await context.read<ReviewState>().submitOrderReviews(
            orderId: widget.order.id,
            merchantId: widget.order.merchantId,
            userId: user.id,
            items: _drafts
                .map((d) => DishReviewInput(
                      dishId: d.dishId,
                      dishName: d.dishName,
                      rating: d.rating,
                      comment: d.comment,
                    ))
                .toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                '订单评价',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.order.merchantName} · ${widget.order.displayOrderNo}',
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
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _drafts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _DishReviewCard(
              draft: _drafts[i],
              onRatingChanged: (v) => setState(() => _drafts[i].rating = v),
              onCommentChanged: (v) => setState(() => _drafts[i].comment = v),
            ),
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
            label: _submitting ? '提交中...' : '提交评价',
            onPressed: _submitting ? null : _submit,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _DishReviewDraft {
  final String dishId;
  final String dishName;
  final String? imageUrl;
  int rating = 0;
  String comment = '';

  _DishReviewDraft({
    required this.dishId,
    required this.dishName,
    this.imageUrl,
  });
}

class _DishReviewCard extends StatelessWidget {
  final _DishReviewDraft draft;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onCommentChanged;

  const _DishReviewCard({
    required this.draft,
    required this.onRatingChanged,
    required this.onCommentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DishImagePlaceholder(
                seed: draft.dishId,
                size: 52,
                imageUrl: draft.imageUrl,
                dishName: draft.dishName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  draft.dishName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '评分',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          StarRatingBar(
            rating: draft.rating,
            onChanged: onRatingChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onCommentChanged,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: '写下您的评价（选填）',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              counterStyle: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
