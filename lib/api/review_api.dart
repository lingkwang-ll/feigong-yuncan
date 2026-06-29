import 'dart:typed_data';

import '../models/review_model.dart';
import 'api_client.dart';

/// 商家评价 API
class ReviewApi {
  ReviewApi(this._client);

  final ApiClient _client;

  Future<MerchantReview?> getByOrder(String orderId) async {
    final data = await _client.get('/reviews/order/$orderId');
    if (data == null) return null;
    return MerchantReview.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<String> uploadReviewImage({
    required String orderId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final data = await _client.uploadBytes(
      '/uploads/review-images',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      extraFields: {'orderId': orderId},
    );
    final map = (data as Map).cast<String, dynamic>();
    final url = map['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw ApiException(message: '图片上传失败，未返回地址');
    }
    return url;
  }

  Future<MerchantReview> create({
    required String orderId,
    required int rating,
    int? hygieneRating,
    String content = '',
    List<String> images = const [],
    bool isAnonymous = false,
  }) async {
    final payload = <String, dynamic>{
      'orderId': orderId,
      'rating': rating,
      if (hygieneRating != null) 'hygieneRating': hygieneRating,
      'content': content,
      'images': images,
      'isAnonymous': isAnonymous,
    };
    final data = await _client.post('/reviews', body: payload);
    return MerchantReview.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<MerchantReviewsPage> listForMerchant({
    String filter = 'all',
  }) async {
    final data = await _client.get(
      '/merchant/reviews',
      query: {'filter': filter},
    );
    return MerchantReviewsPage.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }
}
