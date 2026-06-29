import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/merchant_onboarding_api.dart';
import '../../models/dish_model.dart';
import '../../models/merchant_onboarding_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_format.dart';
import '../../utils/trial_run_policy.dart';
import '../../utils/zh_time_picker.dart';
import '../../widgets/app_button.dart';
import '../legal/agreement_checkbox.dart';
import '../legal/legal_documents.dart';
import '../../utils/device_info_util.dart';

/// 入驻页支持的图片上传槽位（每个槽位均为多张图片）
enum _UploadKind {
  wechatPaymentQr,
  alipayPaymentQr,
  businessLicense,
  foodLicense,
  storePhoto,
  kitchenPhoto,
  healthCertificate,
}

/// 配送方式：delivery / selfPickup / both
enum _DeliveryModeOption { delivery, selfPickup, both }

/// 收款方式（多选）：微信 / 支付宝
enum _PaymentMethodOption { wechat, alipay }

const _weekdayCodes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class MerchantOnboardingPage extends StatefulWidget {
  const MerchantOnboardingPage({
    super.key,
    required this.phone,
    this.existingId,
    this.rejectReason,
  });

  final String phone;
  final String? existingId;
  final String? rejectReason;

  @override
  State<MerchantOnboardingPage> createState() =>
      _MerchantOnboardingPageState();
}

class _MerchantOnboardingPageState extends State<MerchantOnboardingPage> {
  // 基础信息（已去掉"商家名称""所属企业/服务企业"）
  final _storeDisplayNameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _customerServicePhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // 经营信息
  final _mealSelected = <MealType>{MealType.lunch};
  _DeliveryModeOption _deliveryMode = _DeliveryModeOption.both;
  final _businessDays = <String>{'mon', 'tue', 'wed', 'thu', 'fri'};
  final Map<String, TimeOfDay> _mealStartTimes = {
    'breakfast': const TimeOfDay(hour: 7, minute: 0),
    'lunch': const TimeOfDay(hour: 11, minute: 0),
    'dinner': const TimeOfDay(hour: 17, minute: 0),
    'overtime': const TimeOfDay(hour: 17, minute: 30),
  };
  final Map<String, TimeOfDay> _mealEndTimes = {
    'breakfast': const TimeOfDay(hour: 9, minute: 0),
    'lunch': const TimeOfDay(hour: 13, minute: 0),
    'dinner': const TimeOfDay(hour: 19, minute: 0),
    'overtime': const TimeOfDay(hour: 20, minute: 0),
  };

  // 收款信息（已去掉对公转账、收款主体类型、收款主体名称、开户名/开户行/账号）
  final _paymentMethods = <_PaymentMethodOption>{_PaymentMethodOption.wechat};
  final _receiverCtrl = TextEditingController();

  // 资质信息（已去掉营业执照主体名称、统一社会信用代码、营业执照有效期、
  //          食品经营许可证编号、食品经营许可证有效期、许可经营项目）
  final _remarkCtrl = TextEditingController();

  bool _submitting = false;
  bool _agreedToMerchantPolicies = false;
  bool _committedTruthful = false;

  /// 每个槽位的多图状态
  final Map<_UploadKind, _MultiUploadController> _uploads = {
    for (final k in _UploadKind.values) k: _MultiUploadController(),
  };

  late final MerchantOnboardingApi _api;

  @override
  void initState() {
    super.initState();
    _contactPhoneCtrl.text = LoginPhonePolicy.normalize(widget.phone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = MerchantOnboardingApi(context.read<ApiClient>());
  }

  @override
  void dispose() {
    _storeDisplayNameCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _customerServicePhoneCtrl.dispose();
    _addressCtrl.dispose();
    _receiverCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  List<String> _urlsOf(_UploadKind kind) => _uploads[kind]!.urls;
  String _firstOf(_UploadKind kind) {
    final list = _urlsOf(kind);
    return list.isEmpty ? '' : list.first;
  }

  List<String> get _deliveryModes {
    switch (_deliveryMode) {
      case _DeliveryModeOption.delivery:
        return const ['delivery'];
      case _DeliveryModeOption.selfPickup:
        return const ['selfPickup'];
      case _DeliveryModeOption.both:
        return const ['delivery', 'selfPickup'];
    }
  }

  String _paymentMethodKey(_PaymentMethodOption option) {
    switch (option) {
      case _PaymentMethodOption.wechat:
        return 'wechat';
      case _PaymentMethodOption.alipay:
        return 'alipay';
    }
  }

  bool _isValidUploadUrl(String url) {
    if (url.isEmpty) return false;
    return url.startsWith('/uploads/') || url.startsWith('http');
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> _mealOpeningHoursPayload() {
    final out = <String, dynamic>{};
    for (final m in _mealSelected) {
      final key = m.name;
      final start = _mealStartTimes[key]!;
      final end = _mealEndTimes[key]!;
      final startStr = _formatTimeOfDay(start);
      final endStr = _formatTimeOfDay(end);
      out[key] = {
        'enabled': true,
        'start': startStr,
        'end': endStr,
        'hours': '$startStr-$endStr',
      };
    }
    return out;
  }

  MerchantOnboardingApplication _buildPayload() {
    final displayName = _storeDisplayNameCtrl.text.trim();
    final paymentMethods =
        _paymentMethods.map(_paymentMethodKey).toList(growable: false);
    return MerchantOnboardingApplication(
      id: widget.existingId,
      // 兼容旧接口：merchantName 始终使用"店铺显示名称"
      merchantName: displayName,
      shortName: displayName,
      contactName: _contactNameCtrl.text.trim(),
      contactPhone: LoginPhonePolicy.normalize(_contactPhoneCtrl.text.trim()),
      address: _addressCtrl.text.trim(),
      supportedMealTypes: _mealSelected.map((m) => m.name).toList(),
      deliveryModes: _deliveryModes,
      // 旧 payment_method 字段：取多选数组第一项做兼容
      paymentMethod: paymentMethods.isNotEmpty ? paymentMethods.first : '',
      // 旧 paymentQr 字段：优先取微信，否则支付宝
      paymentQr: _firstOf(_UploadKind.wechatPaymentQr).isNotEmpty
          ? _firstOf(_UploadKind.wechatPaymentQr)
          : _firstOf(_UploadKind.alipayPaymentQr),
      paymentReceiverName: _receiverCtrl.text.trim(),
      // 兼容旧单图字段：每类取第一张
      businessLicenseUrl: _firstOf(_UploadKind.businessLicense),
      foodLicenseUrl: _firstOf(_UploadKind.foodLicense),
      storePhotoUrl: _firstOf(_UploadKind.storePhoto),
      kitchenPhotoUrl: _firstOf(_UploadKind.kitchenPhoto),
      healthCertificateUrl: _firstOf(_UploadKind.healthCertificate),
      remark: _remarkCtrl.text.trim(),
      // 企业级商家审核扩展字段
      storeDisplayName: displayName,
      customerServicePhone:
          LoginPhonePolicy.normalize(_customerServicePhoneCtrl.text.trim()),
      businessDays: _weekdayCodes.where(_businessDays.contains).toList(),
      mealOpeningHours: _mealOpeningHoursPayload(),
      // 多图 / 多选字段
      paymentMethods: paymentMethods,
      wechatPaymentQrUrls: _urlsOf(_UploadKind.wechatPaymentQr),
      alipayPaymentQrUrls: _urlsOf(_UploadKind.alipayPaymentQr),
      businessLicenseUrls: _urlsOf(_UploadKind.businessLicense),
      foodLicenseUrls: _urlsOf(_UploadKind.foodLicense),
      kitchenPhotoUrls: _urlsOf(_UploadKind.kitchenPhoto),
      healthCertificateUrls: _urlsOf(_UploadKind.healthCertificate),
      storePhotoUrls: _urlsOf(_UploadKind.storePhoto),
      agreementVersion: legalVersion,
      clientTime: agreementClientTimeIso(),
      deviceInfo: buildDeviceInfo(),
    );
  }

  String _defaultFilename(_UploadKind kind, String? pickedName) {
    if (pickedName != null && pickedName.isNotEmpty) return pickedName;
    switch (kind) {
      case _UploadKind.wechatPaymentQr:
        return 'wechat_qr.png';
      case _UploadKind.alipayPaymentQr:
        return 'alipay_qr.png';
      case _UploadKind.businessLicense:
        return 'business_license.png';
      case _UploadKind.foodLicense:
        return 'food_license.png';
      case _UploadKind.storePhoto:
        return 'store_photo.png';
      case _UploadKind.kitchenPhoto:
        return 'kitchen_photo.png';
      case _UploadKind.healthCertificate:
        return 'health_certificate.png';
    }
  }

  String _uploadPath(_UploadKind kind) {
    switch (kind) {
      case _UploadKind.wechatPaymentQr:
      case _UploadKind.alipayPaymentQr:
        return '/uploads/merchant-qr-code';
      case _UploadKind.businessLicense:
      case _UploadKind.foodLicense:
      case _UploadKind.healthCertificate:
        return '/uploads/merchant-license';
      case _UploadKind.storePhoto:
      case _UploadKind.kitchenPhoto:
        return '/uploads/store-photo';
    }
  }

  void _logUploadFailure(_UploadKind kind, Object error) {
    final path = _uploadPath(kind);
    if (error is ApiException) {
      debugPrint(
        '[MerchantOnboarding][UPLOAD][FAIL] path=$path '
        'status=${error.code} message=${error.message}',
      );
    } else {
      debugPrint('[MerchantOnboarding][UPLOAD][FAIL] path=$path error=$error');
    }
  }

  Future<String> _doUpload(
      _UploadKind kind, Uint8List bytes, String filename) {
    switch (kind) {
      case _UploadKind.wechatPaymentQr:
      case _UploadKind.alipayPaymentQr:
        return _api.uploadQr(bytes, filename);
      case _UploadKind.businessLicense:
        return _api.uploadBusinessLicense(bytes, filename);
      case _UploadKind.foodLicense:
        return _api.uploadFoodLicense(bytes, filename);
      case _UploadKind.storePhoto:
        return _api.uploadStorePhoto(bytes, filename);
      case _UploadKind.kitchenPhoto:
        return _api.uploadKitchenPhoto(bytes, filename);
      case _UploadKind.healthCertificate:
        return _api.uploadHealthCertificate(bytes, filename);
    }
  }

  Future<void> _pickAndUploadMany(_UploadKind kind) async {
    final controller = _uploads[kind]!;
    if (controller.busy) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => controller.busy = true);
    try {
      for (final picked in result.files) {
        final bytes = picked.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        try {
          final url = await _doUpload(
            kind,
            bytes,
            _defaultFilename(kind, picked.name),
          );
          if (!_isValidUploadUrl(url)) continue;
          if (!mounted) return;
          setState(() {
            if (!controller.urls.contains(url)) controller.urls.add(url);
          });
        } catch (e) {
          _logUploadFailure(kind, e);
          if (mounted) {
            _toast('${picked.name} 上传失败');
          }
        }
      }
    } finally {
      if (mounted) setState(() => controller.busy = false);
    }
  }

  void _removeUploaded(_UploadKind kind, int index) {
    final controller = _uploads[kind]!;
    if (index < 0 || index >= controller.urls.length) return;
    setState(() => controller.urls.removeAt(index));
  }

  Future<void> _pickTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showZhTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) onPicked(picked);
  }

  String? _validateBeforeSubmit() {
    if (_storeDisplayNameCtrl.text.trim().isEmpty) return '请填写店铺显示名称';
    if (_contactNameCtrl.text.trim().isEmpty) return '请填写联系人姓名';
    final contactPhone =
        LoginPhonePolicy.normalize(_contactPhoneCtrl.text.trim());
    if (!isValidPhoneFormat(contactPhone)) return '联系人手机号格式不正确';
    final servicePhoneText = _customerServicePhoneCtrl.text.trim();
    if (servicePhoneText.isEmpty) return '请填写客服电话';
    if (!isValidPhoneFormat(LoginPhonePolicy.normalize(servicePhoneText))) {
      return '客服电话格式不正确';
    }
    if (_addressCtrl.text.trim().isEmpty) return '请填写店铺地址';

    if (_mealSelected.isEmpty) return '请至少选择一个餐段';
    if (_deliveryModes.isEmpty) return '请选择配送方式';
    if (_businessDays.isEmpty) return '请至少选择一个营业日';
    for (final m in _mealSelected) {
      final start = _mealStartTimes[m.name]!;
      final end = _mealEndTimes[m.name]!;
      final startMin = start.hour * 60 + start.minute;
      final endMin = end.hour * 60 + end.minute;
      if (startMin == endMin) {
        return '开始与结束时间不能相同';
      }
      if (endMin < startMin && m != MealType.overtime) {
        return '结束时间必须晚于开始时间';
      }
    }

    if (_paymentMethods.isEmpty) return '请至少选择一种收款方式';
    if (_receiverCtrl.text.trim().isEmpty) return '请填写收款人姓名';
    if (_paymentMethods.contains(_PaymentMethodOption.wechat) &&
        _urlsOf(_UploadKind.wechatPaymentQr).isEmpty) {
      return '请上传微信收款码（至少 1 张）';
    }
    if (_paymentMethods.contains(_PaymentMethodOption.alipay) &&
        _urlsOf(_UploadKind.alipayPaymentQr).isEmpty) {
      return '请上传支付宝收款码（至少 1 张）';
    }

    if (_urlsOf(_UploadKind.businessLicense).isEmpty) {
      return '请上传营业执照（至少 1 张）';
    }
    if (_urlsOf(_UploadKind.foodLicense).isEmpty) {
      return '请上传食品经营许可证（至少 1 张）';
    }
    if (_urlsOf(_UploadKind.kitchenPhoto).isEmpty) {
      return '请上传后厨/操作间照片（至少 1 张）';
    }
    if (_urlsOf(_UploadKind.healthCertificate).isEmpty) {
      return '请上传健康证（至少 1 张）';
    }
    if (_urlsOf(_UploadKind.storePhoto).isEmpty) {
      return '请上传门店照片（至少 1 张）';
    }

    if (!_agreedToMerchantPolicies) {
      return '请先勾选《商家服务协议》《食品安全承诺书》';
    }
    if (!_committedTruthful) {
      return '请先勾选"上传资料真实有效"承诺';
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validateBeforeSubmit();
    if (err != null) {
      _toast(err);
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = _buildPayload();
      if (widget.existingId != null) {
        await _api.resubmit(widget.existingId!, payload);
      } else {
        await _api.apply(payload);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提交成功'),
          content: const Text(
              '入驻申请已提交，平台将在 1-3 个工作日内完成审核，审核通过后可进入商家后台维护菜品和接单。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '商家入驻申请',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.rejectReason != null && widget.rejectReason!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                '上次驳回原因：${widget.rejectReason}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          _SectionCard(
            title: '基础信息',
            children: [
              _Field(
                label: '店铺显示名称',
                controller: _storeDisplayNameCtrl,
                hint: '用户端列表展示用',
              ),
              _Field(label: '联系人姓名', controller: _contactNameCtrl),
              _Field(
                label: '联系人手机号',
                controller: _contactPhoneCtrl,
                keyboardType: TextInputType.phone,
              ),
              _Field(
                label: '客服电话',
                controller: _customerServicePhoneCtrl,
                keyboardType: TextInputType.phone,
                hint: '用户售后/咨询电话',
              ),
              _Field(label: '店铺地址', controller: _addressCtrl, maxLines: 2),
            ],
          ),
          _SectionCard(
            title: '经营信息',
            children: [
              const _SubLabel(text: '支持餐段'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MealType.values.map((m) {
                  final selected = _mealSelected.contains(m);
                  return FilterChip(
                    label: Text(_mealLabelFromEnum(m)),
                    selected: selected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _mealSelected.add(m);
                        } else {
                          _mealSelected.remove(m);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const _SubLabel(text: '配送方式'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _DeliveryModeChip(
                    label: '配送',
                    option: _DeliveryModeOption.delivery,
                    groupValue: _deliveryMode,
                    onChanged: (v) => setState(() => _deliveryMode = v),
                  ),
                  _DeliveryModeChip(
                    label: '自取',
                    option: _DeliveryModeOption.selfPickup,
                    groupValue: _deliveryMode,
                    onChanged: (v) => setState(() => _deliveryMode = v),
                  ),
                  _DeliveryModeChip(
                    label: '都支持',
                    option: _DeliveryModeOption.both,
                    groupValue: _deliveryMode,
                    onChanged: (v) => setState(() => _deliveryMode = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SubLabel(text: '营业日'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_weekdayCodes.length, (i) {
                  final code = _weekdayCodes[i];
                  final selected = _businessDays.contains(code);
                  return FilterChip(
                    label: Text(_weekdayLabels[i]),
                    selected: selected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _businessDays.add(code);
                        } else {
                          _businessDays.remove(code);
                        }
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              const _SubLabel(text: '营业时间'),
              const SizedBox(height: 4),
              Text(
                '各餐段营业结束时间将作为员工订餐截止时间。',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              ..._mealSelected.map(_buildMealHoursRow),
            ],
          ),
          _SectionCard(
            title: '收款信息',
            children: [
              const _SubLabel(text: '收款方式（可多选）'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('微信'),
                    selected: _paymentMethods.contains(_PaymentMethodOption.wechat),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _paymentMethods.add(_PaymentMethodOption.wechat);
                      } else {
                        _paymentMethods.remove(_PaymentMethodOption.wechat);
                      }
                    }),
                  ),
                  FilterChip(
                    label: const Text('支付宝'),
                    selected: _paymentMethods.contains(_PaymentMethodOption.alipay),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _paymentMethods.add(_PaymentMethodOption.alipay);
                      } else {
                        _paymentMethods.remove(_PaymentMethodOption.alipay);
                      }
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Field(label: '收款人姓名', controller: _receiverCtrl),
              if (_paymentMethods.contains(_PaymentMethodOption.wechat))
                _MultiImageUploadRow(
                  label: '微信收款码',
                  controller: _uploads[_UploadKind.wechatPaymentQr]!,
                  onPickMore: () =>
                      _pickAndUploadMany(_UploadKind.wechatPaymentQr),
                  onRemove: (i) =>
                      _removeUploaded(_UploadKind.wechatPaymentQr, i),
                ),
              if (_paymentMethods.contains(_PaymentMethodOption.alipay))
                _MultiImageUploadRow(
                  label: '支付宝收款码',
                  controller: _uploads[_UploadKind.alipayPaymentQr]!,
                  onPickMore: () =>
                      _pickAndUploadMany(_UploadKind.alipayPaymentQr),
                  onRemove: (i) =>
                      _removeUploaded(_UploadKind.alipayPaymentQr, i),
                ),
            ],
          ),
          _SectionCard(
            title: '资质信息',
            children: [
              _MultiImageUploadRow(
                label: '营业执照',
                controller: _uploads[_UploadKind.businessLicense]!,
                onPickMore: () =>
                    _pickAndUploadMany(_UploadKind.businessLicense),
                onRemove: (i) =>
                    _removeUploaded(_UploadKind.businessLicense, i),
              ),
              _MultiImageUploadRow(
                label: '食品经营许可证',
                controller: _uploads[_UploadKind.foodLicense]!,
                onPickMore: () => _pickAndUploadMany(_UploadKind.foodLicense),
                onRemove: (i) => _removeUploaded(_UploadKind.foodLicense, i),
              ),
              _MultiImageUploadRow(
                label: '后厨/操作间照片',
                controller: _uploads[_UploadKind.kitchenPhoto]!,
                onPickMore: () => _pickAndUploadMany(_UploadKind.kitchenPhoto),
                onRemove: (i) => _removeUploaded(_UploadKind.kitchenPhoto, i),
              ),
              _MultiImageUploadRow(
                label: '健康证',
                controller: _uploads[_UploadKind.healthCertificate]!,
                onPickMore: () =>
                    _pickAndUploadMany(_UploadKind.healthCertificate),
                onRemove: (i) =>
                    _removeUploaded(_UploadKind.healthCertificate, i),
              ),
              _MultiImageUploadRow(
                label: '门店照片',
                controller: _uploads[_UploadKind.storePhoto]!,
                onPickMore: () => _pickAndUploadMany(_UploadKind.storePhoto),
                onRemove: (i) => _removeUploaded(_UploadKind.storePhoto, i),
              ),
              _Field(label: '备注说明（选填）', controller: _remarkCtrl, maxLines: 3),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AgreementCheckboxRow(
                  agreed: _agreedToMerchantPolicies,
                  onChanged: (v) =>
                      setState(() => _agreedToMerchantPolicies = v),
                  centered: false,
                  documents: const [legalMerchantService, legalFoodSafety],
                ),
                const SizedBox(height: 10),
                _PlainCheckboxRow(
                  agreed: _committedTruthful,
                  onChanged: (v) => setState(() => _committedTruthful = v),
                  text: '我承诺上传资料真实有效，且餐品经营范围与许可证一致。',
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '提交后平台将在 1-3 个工作日内完成审核，审核通过后可进入商家后台维护菜品和接单。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          PrimaryActionButton(
            label: _submitting ? '提交中…' : '提交入驻申请',
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildMealHoursRow(MealType m) {
    final key = m.name;
    final label = _mealLabelFromEnum(m);
    final start = _mealStartTimes[key]!;
    final end = _mealEndTimes[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _TimeFieldButton(
                  label: '开始时间',
                  value: start,
                  onPick: () => _pickTime(
                    initial: start,
                    onPicked: (t) => setState(() => _mealStartTimes[key] = t),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeFieldButton(
                  label: '结束时间',
                  value: end,
                  onPick: () => _pickTime(
                    initial: end,
                    onPicked: (t) => setState(() => _mealEndTimes[key] = t),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _mealLabelFromEnum(MealType m) {
    switch (m) {
      case MealType.breakfast:
        return '早餐';
      case MealType.lunch:
        return '中餐';
      case MealType.dinner:
        return '晚餐';
      case MealType.overtime:
        return '加班餐';
    }
  }
}

/// 多图上传状态
class _MultiUploadController {
  final List<String> urls = [];
  bool busy = false;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary));
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: _inputDecoration(label, hint: hint),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFFAFAF8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

/// 多图上传 + 预览 + 删除
class _MultiImageUploadRow extends StatelessWidget {
  const _MultiImageUploadRow({
    required this.label,
    required this.controller,
    required this.onPickMore,
    required this.onRemove,
  });

  final String label;
  final _MultiUploadController controller;
  final VoidCallback onPickMore;
  final ValueChanged<int> onRemove;

  String _displayUrl(String u) => resolveAssetUrl(u) ?? u;

  void _preview(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.network(_displayUrl(url),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 48),
                      ),
                    )),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = controller.urls.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '已上传 $count 张',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...List.generate(controller.urls.length, (i) {
                final url = controller.urls[i];
                return _ThumbTile(
                  url: _displayUrl(url),
                  onPreview: () => _preview(context, url),
                  onRemove: () => onRemove(i),
                );
              }),
              _AddTile(busy: controller.busy, onTap: onPickMore),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.url,
    required this.onPreview,
    required this.onRemove,
  });
  final String url;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onPreview,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.broken_image,
                    color: AppColors.textTertiary, size: 24),
              ),
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAF8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: busy ? AppColors.textTertiary : AppColors.accent,
            style: BorderStyle.solid,
          ),
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add, color: AppColors.accent, size: 22),
                  SizedBox(height: 2),
                  Text('添加',
                      style:
                          TextStyle(color: AppColors.accent, fontSize: 12)),
                ],
              ),
      ),
    );
  }
}

class _DeliveryModeChip extends StatelessWidget {
  const _DeliveryModeChip({
    required this.label,
    required this.option,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final _DeliveryModeOption option;
  final _DeliveryModeOption groupValue;
  final ValueChanged<_DeliveryModeOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = groupValue == option;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      onSelected: (_) => onChanged(option),
    );
  }
}

class _TimeFieldButton extends StatelessWidget {
  const _TimeFieldButton({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onPick;

  String _format(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    const color = AppColors.textPrimary;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAF8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value == null ? label : _format(value!),
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

/// 普通承诺勾选行（不带链接）
class _PlainCheckboxRow extends StatelessWidget {
  const _PlainCheckboxRow({
    required this.agreed,
    required this.onChanged,
    required this.text,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!agreed),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: agreed ? AppColors.primary : Colors.white,
                  border: Border.all(
                    color: agreed
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: agreed
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
