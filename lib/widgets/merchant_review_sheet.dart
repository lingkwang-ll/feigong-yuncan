import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/review_api.dart';
import '../api/api_config.dart';
import '../models/order_model.dart';
import '../models/review_model.dart';
import '../theme/app_theme.dart';
import '../utils/review_image_picker.dart';
import 'app_button.dart';
import 'star_rating_bar.dart';

class _ReviewImageDraft {
  final Uint8List bytes;
  final String filename;
  String? uploadedUrl;
  bool uploading;
  bool uploadFailed;

  _ReviewImageDraft({
    required this.bytes,
    required this.filename,
    this.uploadedUrl,
    this.uploading = false,
    this.uploadFailed = false,
  });
}

/// 商家评价弹窗（订单完成后，一单一评，对接后端 Review API）
class MerchantReviewSheet extends StatefulWidget {
  final Order order;

  const MerchantReviewSheet({super.key, required this.order});

  static Future<bool?> show(BuildContext context, {required Order order}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: MerchantReviewSheet(order: order),
      ),
    );
  }

  @override
  State<MerchantReviewSheet> createState() => _MerchantReviewSheetState();
}

class _MerchantReviewSheetState extends State<MerchantReviewSheet> {
  int _rating = 0;
  int _hygieneRating = 0;
  final _controller = TextEditingController();
  final List<_ReviewImageDraft> _images = [];
  bool _submitting = false;
  bool _isAnonymous = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addImage() async {
    if (_images.length >= kReviewImageMaxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多上传9张图片')),
      );
      return;
    }
    final picked = await pickReviewImage(context);
    if (picked == null || !mounted) return;
    setState(() {
      _images.add(_ReviewImageDraft(
        bytes: picked.bytes,
        filename: picked.filename,
      ));
    });
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  String _errorMessage(Object e) {
    if (e is ApiException) {
      if (e.code == 401) return '登录已过期，请重新登录';
      switch (e.errorCode) {
        case 'ORDER_NOT_COMPLETED':
          return '订单未完成，不能评价';
        case 'REVIEW_ALREADY_EXISTS':
          return '该订单已评价';
        case 'INVALID_RATING':
          return '请选择总体评分';
        case 'INVALID_HYGIENE_RATING':
          return '请选择卫生评分';
        case 'INVALID_IMAGE_COUNT':
          return '最多上传9张图片';
        case 'INVALID_IMAGE_URL':
          return '图片地址无效';
        case 'REVIEW_DISABLED':
          return '评价功能未开启';
        case 'UPLOAD_FAILED':
        case 'UPLOAD_FILE_REQUIRED':
          return '图片上传失败，请重新选择';
        default:
          break;
      }
      if (e.message.contains('图片')) return e.message;
      return e.message;
    }
    return e.toString();
  }

  void _logSubmitFailure(
    Object e, {
    required Map<String, dynamic> payload,
    String? responseBody,
  }) {
    debugPrint('[ReviewSubmit][FAIL] orderId=${widget.order.id}');
    debugPrint('[ReviewSubmit][FAIL] rating=$_rating hygieneRating=$_hygieneRating');
    debugPrint('[ReviewSubmit][FAIL] content=${_controller.text.trim()}');
    debugPrint('[ReviewSubmit][FAIL] images.length=${_images.length}');
    debugPrint('[ReviewSubmit][FAIL] isAnonymous=$_isAnonymous');
    debugPrint('[ReviewSubmit][FAIL] payload=$payload');
    if (e is ApiException) {
      debugPrint('[ReviewSubmit][FAIL] response statusCode=${e.code}');
      if (responseBody != null) {
        debugPrint('[ReviewSubmit][FAIL] response body=$responseBody');
      }
      debugPrint('[ReviewSubmit][FAIL] error.code=${e.errorCode}');
      debugPrint('[ReviewSubmit][FAIL] error.message=${e.message}');
    } else {
      debugPrint('[ReviewSubmit][FAIL] error=$e');
    }
  }

  Future<List<String>> _ensureImagesUploaded(ReviewApi api) async {
    final urls = <String>[];
    for (var i = 0; i < _images.length; i++) {
      final draft = _images[i];
      if (draft.uploadedUrl != null && draft.uploadedUrl!.isNotEmpty) {
        urls.add(draft.uploadedUrl!);
        continue;
      }
      setState(() {
        draft.uploading = true;
        draft.uploadFailed = false;
      });
      try {
        final url = await api.uploadReviewImage(
          orderId: widget.order.id,
          bytes: draft.bytes,
          filename: draft.filename,
        );
        draft.uploadedUrl = url;
        draft.uploadFailed = false;
        urls.add(url);
      } catch (e) {
        draft.uploadFailed = true;
        rethrow;
      } finally {
        if (mounted) {
          setState(() => draft.uploading = false);
        }
      }
    }
    return urls;
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择总体评分')),
      );
      return;
    }
    if (_hygieneRating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择卫生评分')),
      );
      return;
    }
    if (_images.length > kReviewImageMaxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多上传9张图片')),
      );
      return;
    }

    final pendingUpload = _images.where((d) => d.uploadedUrl == null).length;
    if (_images.isNotEmpty && pendingUpload > 0 && AppConfig.dataSourceMode != DataSourceMode.api) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片尚未上传成功，请删除图片后提交或重新选择')),
      );
      return;
    }

    setState(() => _submitting = true);
    List<String> imageUrls = [];
    final payload = <String, dynamic>{
      'orderId': widget.order.id,
      'rating': _rating,
      'hygieneRating': _hygieneRating,
      'content': _controller.text.trim(),
      'images': <String>[],
      'isAnonymous': _isAnonymous,
    };
    try {
      if (AppConfig.dataSourceMode == DataSourceMode.api) {
        final api = ReviewApi(context.read<ApiClient>());
        if (_images.isNotEmpty) {
          imageUrls = await _ensureImagesUploaded(api);
        }
        payload['images'] = imageUrls;
        await api.create(
          orderId: widget.order.id,
          rating: _rating,
          hygieneRating: _hygieneRating,
          content: _controller.text.trim(),
          images: imageUrls,
          isAnonymous: _isAnonymous,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      payload['images'] = imageUrls;
      _logSubmitFailure(e, payload: payload);
      if (!mounted) return;
      var msg = _errorMessage(e);
      if (_images.any((d) => d.uploadFailed)) {
        msg = '图片上传失败：$msg';
      } else if (_images.isNotEmpty &&
          imageUrls.isEmpty &&
          e is! ApiException) {
        msg = '图片尚未上传成功，请删除图片后提交或重新选择';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
            Text(
              '评价 ${widget.order.merchantName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Text('总体评分', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            StarRatingBar(
              rating: _rating,
              onChanged: (v) => setState(() => _rating = v),
              size: 36,
            ),
            const SizedBox(height: 12),
            const Text('卫生评分', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            StarRatingBar(
              rating: _hygieneRating,
              onChanged: (v) => setState(() => _hygieneRating = v),
              size: 28,
            ),
            const SizedBox(height: 16),
            const Text('评价方式', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('实名评价')),
                ButtonSegment(value: true, label: Text('匿名评价')),
              ],
              selected: {_isAnonymous},
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() => _isAnonymous = s.first),
            ),
            if (_isAnonymous)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '匿名后商家端将显示「匿名用户」',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '分享用餐体验（选填）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('图片（选填，最多9张）',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                if (_images.length < kReviewImageMaxCount)
                  TextButton(
                    onPressed: _submitting ? null : _addImage,
                    child: const Text('添加图片'),
                  ),
              ],
            ),
            if (_images.isEmpty)
              GestureDetector(
                onTap: _submitting ? null : _addImage,
                child: Container(
                  width: double.infinity,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text('添加图片',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _images.asMap().entries.map((entry) {
                  final draft = entry.value;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: draft.uploadFailed
                                ? Colors.red
                                : AppColors.divider,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: draft.uploading
                            ? const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : Image.memory(
                                draft.bytes,
                                fit: BoxFit.cover,
                                width: 72,
                                height: 72,
                              ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: _submitting ? null : () => _removeImage(entry.key),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppColors.textSecondary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),
            PrimaryActionButton(
              label: _submitting ? '提交中...' : '提交评价',
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
