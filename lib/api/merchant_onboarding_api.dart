import 'dart:typed_data';

import '../models/merchant_onboarding_model.dart';
import 'api_client.dart';

class MerchantOnboardingApi {
  MerchantOnboardingApi(this._client);

  final ApiClient _client;

  Future<MerchantOnboardingStatusInfo> getStatus(String phone) async {
    final data = await _client.get(
      '/merchant-onboarding/status',
      query: {'phone': phone},
    );
    return MerchantOnboardingStatusInfo.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<MerchantOnboardingApplication> apply(
    MerchantOnboardingApplication app,
  ) async {
    final data = await _client.post(
      '/merchant-onboarding/apply',
      body: app.toJson(),
    );
    return MerchantOnboardingApplication.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<MerchantOnboardingApplication> resubmit(
    String id,
    MerchantOnboardingApplication app,
  ) async {
    final data = await _client.put(
      '/merchant-onboarding/$id/resubmit',
      body: app.toJson(),
    );
    return MerchantOnboardingApplication.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<String> uploadQr(Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/merchant-qr-code',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return _extractUrl(data);
  }

  Future<String> uploadBusinessLicense(Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/merchant-license',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return _extractUrl(data);
  }

  Future<String> uploadFoodLicense(Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/merchant-license',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return _extractUrl(data);
  }

  Future<String> uploadStorePhoto(Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/store-photo',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return _extractUrl(data);
  }

  /// 后厨/操作间照片：与门店照片复用同一上传通道（/uploads/store-photo）
  Future<String> uploadKitchenPhoto(Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/store-photo',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return _extractUrl(data);
  }

  /// 健康证：与许可证复用同一上传通道（/uploads/merchant-license）
  Future<String> uploadHealthCertificate(
      Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/merchant-license',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return _extractUrl(data);
  }

  String _extractUrl(dynamic data) {
    final url = (data as Map)['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw ApiException(message: '上传响应缺少 url');
    }
    return url;
  }
}
