import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/merchant_api.dart';
import '../../api/merchant_onboarding_api.dart';
import '../../models/merchant_onboarding_model.dart';
import '../../models/user_model.dart';
import '../../utils/phone_format.dart';
import '../../utils/device_info_util.dart';
import '../../utils/trial_run_policy.dart';
import '../../state/app_state.dart';
import '../../state/merchant_dish_state.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../legal/agreement_checkbox.dart';
import '../legal/legal_documents.dart';
import '../merchant/merchant_onboarding_page.dart';
import 'auth_entry_gate.dart';

/// 登录页 —— 严格按 design_reference/feigong_yuncan_ui/01_login.png 复刻
///
/// 视觉资源全部走 assets/images/ui/ 下的静态 PNG：
/// - login_bg_top.png         顶部叶子 + 城市 + 右上沙拉碗背景
/// - app_logo_large.png       中央大 P+ Logo
/// - employee_illustration.png  我是员工 卡片插画
/// - merchant_illustration.png  我是商家 卡片插画
///
/// 不再使用 CustomPainter 或 emoji 替代设计稿里的视觉元素。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  UserRole? _role;
  // 上线前合规要求：默认不勾选，需用户主动同意
  bool _agreed = false;
  bool _loggingIn = false;
  bool _obscurePassword = true;
  String? _merchantGateMessage;
  String? _merchantApplicationId;
  String? _merchantRejectReason;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (_loggingIn) return;
    if (_role == null) {
      _toast('请先选择身份：我是员工 / 我是商家');
      return;
    }
    if (!_agreed) {
      _toast(_role == UserRole.merchant
          ? '请先勾选《商家服务协议》《隐私政策》《食品安全承诺书》'
          : '请先勾选《用户服务协议》《隐私政策》《订餐及退款规则》');
      return;
    }
    final phoneText = _phoneCtrl.text.trim();
    final passwordText = _passwordCtrl.text;
    if (phoneText.isEmpty) {
      _toast('请输入手机号');
      return;
    }
    if (!isValidPhoneFormat(LoginPhonePolicy.normalize(phoneText))) {
      _toast('手机号格式不正确');
      return;
    }
    if (passwordText.isEmpty) {
      _toast('请输入密码');
      return;
    }

    final policyError = AppConfig.dataSourceMode != DataSourceMode.api
        ? LoginPhonePolicy.validate(phoneText, _role!)
        : null;
    if (policyError != null) {
      _toast(policyError);
      return;
    }

    final appState = context.read<AppState>();
    final orderState = context.read<OrderState>();
    final dishState = context.read<MerchantDishState>();
    final merchantState = context.read<MerchantState>();
    final apiClient = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _loggingIn = true);
    try {
      final user = await appState.loginWithCredentials(
        phone: phoneText,
        password: passwordText,
        role: _role!,
      );

      if (user.role == UserRole.merchant) {
        final m = await merchantState.refreshMerchantProfile(user.id);
        final merchantId = m?.id;
        if (merchantId != null) {
          appState.setCurrentMerchantId(merchantId);
          await Future.wait([
            dishState.refreshFor(merchantId),
            orderState.refreshForRole(
              role: UserRole.merchant,
              merchantId: merchantId,
            ),
          ]);
          if (AppConfig.dataSourceMode == DataSourceMode.api) {
            try {
              await MerchantApi(apiClient).signAgreement(
                merchantId: merchantId,
                agreementVersion: legalVersion,
                clientTime: agreementClientTimeIso(),
                deviceInfo: buildDeviceInfo(),
              );
            } catch (_) {
              // 签署记录失败不阻断登录
            }
          }
        }
      } else if (appState.isEmployeeBound) {
        await Future.wait([
          merchantState.refreshNearbyMerchants(),
          orderState.refreshForRole(
            role: UserRole.employee,
            userId: user.id,
          ),
        ]);
      }

      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthEntryGate()),
      );
    } on ApiException catch (e) {
      if (_role == UserRole.merchant) {
        await _handleMerchantLoginFailure(e.message);
      }
      messenger.showSnackBar(
        SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 3)),
      );
    } on StateError catch (e) {
      if (_role == UserRole.merchant) {
        await _handleMerchantLoginFailure(e.message);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content: Text('登录异常：$e'),
            duration: const Duration(seconds: 3)),
      );
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _handleMerchantLoginFailure(String message) async {
    setState(() => _merchantGateMessage = message);
    if (AppConfig.dataSourceMode != DataSourceMode.api) return;
    final phone = LoginPhonePolicy.normalize(_phoneCtrl.text.trim());
    if (phone.isEmpty) return;
    try {
      final api = MerchantOnboardingApi(context.read<ApiClient>());
      final status = await api.getStatus(phone);
      if (!mounted) return;
      setState(() {
        _merchantGateMessage = status.message.isNotEmpty ? status.message : message;
        _merchantApplicationId = status.merchantId;
        _merchantRejectReason = status.rejectReason;
      });
    } catch (_) {
      // 保留原始错误提示
    }
  }

  Future<void> _openMerchantOnboarding() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _toast('请先输入手机号');
      return;
    }
    if (!isValidPhoneFormat(LoginPhonePolicy.normalize(phone))) {
      _toast('手机号格式不正确');
      return;
    }
    if (AppConfig.dataSourceMode == DataSourceMode.api) {
      try {
        final api = MerchantOnboardingApi(context.read<ApiClient>());
        final status = await api.getStatus(phone);
        if (status.status == MerchantOnboardingPhoneStatus.pending) {
          _toast('入驻申请审核中，请耐心等待');
          setState(() => _merchantGateMessage = status.message);
          return;
        }
        if (status.status == MerchantOnboardingPhoneStatus.approved) {
          _toast('该手机号已审核通过，请直接登录');
          return;
        }
        _merchantApplicationId = status.merchantId;
        _merchantRejectReason = status.rejectReason;
      } catch (e) {
        _toast('查询状态失败：$e');
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantOnboardingPage(
          phone: phone,
          existingId: _merchantApplicationId,
          rejectReason: _merchantRejectReason,
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 设计基准宽度 430px，水平边距 36px（按设计图）
    const horizontalPadding = 36.0;
    const fieldHeight = 56.0;
    const buttonHeight = 56.0;
    const roleCardHeight = 120.0;
    const roleCardSpacing = 12.0;
    const heroHeight = 300.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部视觉区：login_bg_top.png 静态背景 + 居中 Logo + 标题 + 副标题
              SizedBox(
                height: heroHeight,
                child: Stack(
                  children: [
                    // 顶部背景图（包含叶子 / 城市 / 右上沙拉碗）
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/ui/login_bg_top.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    // 居中 Logo + 标题 + 副标题
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 8),
                          // 大 P+ Logo（设计图里约 96 见方）
                          const AppLogo(size: 96),
                          const SizedBox(height: 8),
                          const Text(
                            '非攻云餐',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const ThemeSlogan(fontSize: 15),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 输入区
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    _RoundedField(
                      controller: _phoneCtrl,
                      hint: '请输入手机号',
                      icon: Icons.phone_iphone,
                      keyboardType: TextInputType.phone,
                      height: fieldHeight,
                    ),
                    const SizedBox(height: 16),
                    _RoundedField(
                      controller: _passwordCtrl,
                      hint: '请输入密码',
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      height: fieldHeight,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 登录按钮
                    PrimaryActionButton(
                      label: _loggingIn ? '登 录 中…' : '登 录',
                      onPressed: _loggingIn ? null : _onLogin,
                      height: buttonHeight,
                      letterSpacing: 8,
                    ),
                    const SizedBox(height: 22),
                    // 双身份卡
                    SizedBox(
                      height: roleCardHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _RoleCard(
                              title: '我是员工',
                              subtitle1: '为自己订餐',
                              subtitle2: '享受企业福利',
                              accent: AppColors.primary,
                              bg: const Color(0xFFE9F5DF),
                              arrowBg: AppColors.primary,
                              selected: _role == UserRole.employee,
                              illustrationAsset:
                                  'assets/images/ui/employee_illustration.png',
                              onTap: () => setState(
                                  () => _role = UserRole.employee),
                            ),
                          ),
                          const SizedBox(width: roleCardSpacing),
                          Expanded(
                            child: _RoleCard(
                              title: '我是商家',
                              subtitle1: '管理店铺',
                              subtitle2: '服务企业客户',
                              accent: AppColors.accent,
                              bg: const Color(0xFFFFEFD7),
                              arrowBg: AppColors.accent,
                              selected: _role == UserRole.merchant,
                              illustrationAsset:
                                  'assets/images/ui/merchant_illustration.png',
                              onTap: () => setState(() {
                                _role = UserRole.merchant;
                                _merchantGateMessage = null;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_role == UserRole.merchant) ...[
                      const SizedBox(height: 14),
                      if (_merchantGateMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8F0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            _merchantGateMessage!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlineAccentButton(
                        label: '申请商家入驻',
                        onPressed: _openMerchantOnboarding,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: AgreementCheckboxRow(
                        agreed: _agreed,
                        onChanged: (v) => setState(() => _agreed = v),
                        documents: _role == UserRole.merchant
                            ? const [
                                legalMerchantService,
                                legalPrivacy,
                                legalFoodSafety,
                              ]
                            : const [
                                legalUserService,
                                legalPrivacy,
                                legalOrderRefund,
                              ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 白色圆角大输入框（手机号 / 验证码共用）
class _RoundedField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final Widget? suffix;
  final double height;
  final bool obscureText;

  const _RoundedField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.suffix,
    this.height = 56,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscureText,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 15,
                ),
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
          if (suffix != null)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.divider, width: 1),
                ),
              ),
              child: suffix,
            ),
        ],
      ),
    );
  }
}

/// 身份卡片（按 01_login.png 严格还原）
///
/// - 文字在左上：标题 + 两行副文案
/// - 插画在右下：employee_illustration.png / merchant_illustration.png
/// - 左下角圆形箭头（绿色 / 橙色）
class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle1;
  final String subtitle2;
  final Color accent;
  final Color bg;
  final Color arrowBg;
  final bool selected;
  final String illustrationAsset;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle1,
    required this.subtitle2,
    required this.accent,
    required this.bg,
    required this.arrowBg,
    required this.selected,
    required this.illustrationAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.6,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // 文案（左上）
            Positioned(
              left: 2,
              top: 2,
              right: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle1,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle2,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // 右侧插画（铺满右半部，按图严格用 PNG）
            Positioned(
              right: -8,
              top: 0,
              bottom: 0,
              width: 84,
              child: Image.asset(
                illustrationAsset,
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                filterQuality: FilterQuality.medium,
              ),
            ),
            // 左下角圆形箭头
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: arrowBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: arrowBg.withValues(alpha: 0.30),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.chevron_right,
                    color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 旧的 _AgreementRow 已迁移到 lib/features/legal/agreement_checkbox.dart，
// 在登录页改为按身份动态展示三份协议。
