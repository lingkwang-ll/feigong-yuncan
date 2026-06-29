import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/order_api.dart';
import '../../models/address_model.dart';
import '../../models/cart_item_model.dart';
import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../state/address_state.dart';
import '../../state/app_state.dart';
import '../../state/cart_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/employee_info_helper.dart';
import '../../utils/trial_run_policy.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/coupon_checkout_section.dart';
import '../../widgets/dish_card.dart';
import '../../widgets/section_card.dart';
import 'employee_address_list_page.dart';
import 'order_payment_page.dart';
import '../map/map_picker_page.dart';
import '../../models/map_pick_result.dart';

/// 员工端确认订单页 - 参考 03_employee_confirm_order.png
class EmployeeConfirmOrderPage extends StatefulWidget {
  const EmployeeConfirmOrderPage({super.key});

  @override
  State<EmployeeConfirmOrderPage> createState() =>
      _EmployeeConfirmOrderPageState();
}

class _EmployeeConfirmOrderPageState
    extends State<EmployeeConfirmOrderPage> {
  DeliveryType _deliveryType = DeliveryType.delivery;
  final TextEditingController _remarkCtrl = TextEditingController();
  final TextEditingController _collectorRemarkCtrl = TextEditingController();
  DeliveryAddress? _selectedAddress;
  bool _isMealCollector = false;
  String? _couponClaimId;
  CouponPreviewAmounts? _couponPreview;

  @override
  void dispose() {
    _remarkCtrl.dispose();
    _collectorRemarkCtrl.dispose();
    super.dispose();
  }

  void _onMealCollectorChanged(bool value) {
    setState(() {
      _isMealCollector = value;
      if (value && _selectedAddress == null) {
        _selectedAddress = context.read<AddressState>().defaultAddress;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final merchant = cart.merchant;
    final items = cart.items;
    final goodsAmount = cart.goodsAmount;
    final deliveryFee =
        _deliveryType == DeliveryType.delivery ? (merchant?.deliveryFee ?? 0) : 0;
    final total = goodsAmount + deliveryFee;
    final preview = _couponPreview;
    final employeePay = preview?.employeePayAmount ?? total;
    // 按当前购物车所属商家的截止时间判断；商家未配置时回退全局默认。
    final cartHasClosedMeal = cart.items.any(
      (i) => MealOrderDeadline.isClosedFor(
        i.dish.mealType,
        merchant: merchant,
      ),
    );
    final collectorReady = !_isMealCollector ||
        (_selectedAddress != null &&
            _selectedAddress!.phone.trim().isNotEmpty);
    final canSubmit = !cartHasClosedMeal && collectorReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '确认订单',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      backgroundColor: AppColors.background,
      body: cart.isEmpty || merchant == null
          ? const Center(
              child: Text('购物车为空',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            MerchantBadgeLogo(
                                seed: merchant.logo, size: 44, radius: 11),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    merchant.name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const ThemeSlogan(fontSize: 12),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentLight,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: AppColors.accent
                                                .withValues(alpha: 0.35),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Text('企业食堂',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.accent,
                                                fontWeight:
                                                    FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ...items.map((item) =>
                          _CartItemTile(item: item)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _DeliveryRow(
                        value: _deliveryType,
                        onChanged: (v) =>
                            setState(() => _deliveryType = v),
                      ),
                      const Divider(
                          height: 1, indent: 14, endIndent: 14),
                      _RemarkRow(controller: _remarkCtrl),
                      const Divider(
                          height: 1, indent: 14, endIndent: 14),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '统一取餐信息',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '仅当天统一取餐人填写，其他员工无需填写',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _MealCollectorSwitchRow(
                        value: _isMealCollector,
                        onChanged: _onMealCollectorChanged,
                      ),
                      if (_isMealCollector) ...[
                        const Divider(
                            height: 1, indent: 14, endIndent: 14),
                        const _CollectorNameRow(),
                        const Divider(
                            height: 1, indent: 14, endIndent: 14),
                        _AddressSelectRow(
                          address: _selectedAddress,
                          label: '统一取餐地点',
                          onTap: _pickAddress,
                        ),
                        if (_selectedAddress != null)
                          const Divider(
                              height: 1, indent: 14, endIndent: 14),
                        if (_selectedAddress != null)
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: '联系电话',
                            value: _selectedAddress!.phone,
                            onTap: null,
                          ),
                        const Divider(
                            height: 1, indent: 14, endIndent: 14),
                        _CollectorRemarkRow(
                            controller: _collectorRemarkCtrl),
                      ] else
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '普通员工只需点餐，不需要填写取餐地址和电话',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (merchant != null && items.isNotEmpty)
                  CouponCheckoutSection(
                    merchantId: merchant.id,
                    mealType: items.first.dish.mealType,
                    orderTotal: total,
                    onClaimIdChanged: (id) =>
                        setState(() => _couponClaimId = id),
                    onPreviewChanged: (p) =>
                        setState(() => _couponPreview = p),
                  ),
                SectionCard(
                  child: Column(
                    children: [
                      _AmountRow(
                          label: '订单总额',
                          value: '¥${total.toStringAsFixed(2)}',
                          color: AppColors.textPrimary),
                      if (preview != null && preview.companyPayAmount > 0) ...[
                        const SizedBox(height: 10),
                        _AmountRow(
                          label: '企业代付',
                          value: '-¥${preview.companyPayAmount.toStringAsFixed(2)}',
                          color: AppColors.textSecondary,
                        ),
                      ],
                      if (preview != null && preview.couponDiscountAmount > 0) ...[
                        const SizedBox(height: 10),
                        _AmountRow(
                          label: '优惠券抵扣',
                          value: '-¥${preview.couponDiscountAmount.toStringAsFixed(2)}',
                          color: AppColors.primary,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('配送费',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textPrimary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.info_outline,
                              size: 14, color: AppColors.textTertiary),
                          const Spacer(),
                          Text(
                            '¥${deliveryFee.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _AmountRow(
                        label: '您需支付',
                        value: '¥${employeePay.toStringAsFixed(2)}',
                        color: AppColors.accent,
                        valueFontSize: 22,
                        valueBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    const Text('合计：',
                        style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary)),
                    Text(
                      '¥${employeePay.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 150,
                      height: 50,
                      child: PrimaryActionButton(
                        label: '去付款',
                        letterSpacing: 4,
                        height: 50,
                        onPressed: canSubmit
                            ? () => _submitOrderAndPay(
                                  goodsAmount: goodsAmount,
                                  deliveryFee: deliveryFee.toDouble(),
                                  total: total,
                                )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _submitOrderAndPay({
    required double goodsAmount,
    required double deliveryFee,
    required double total,
  }) async {
    if (_isMealCollector && _selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择统一取餐地点')),
      );
      return;
    }
    if (_isMealCollector &&
        (_selectedAddress?.phone.trim().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写联系电话')),
      );
      return;
    }

    final cart = context.read<CartState>();
    final merchant = cart.merchant;
    if (cart.isEmpty || merchant == null) return;

    final user = context.read<AppState>().currentUser;
    final info = EmployeeInfoHelper.resolve(
      user: user,
      phone: user?.phone,
      address: _selectedAddress?.multilineOrderAddress ?? '',
    );

    var collectorAddress = '';
    if (_isMealCollector && _selectedAddress != null) {
      collectorAddress = _selectedAddress!.multilineOrderAddress;
      final note = _collectorRemarkCtrl.text.trim();
      if (note.isNotEmpty) {
        collectorAddress = '$collectorAddress\n备注：$note';
      }
    }

    final localOrderId =
        'O${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';
    final order = Order(
      id: localOrderId,
      merchantId: merchant.id,
      merchantName: merchant.name,
      customerName: info.name,
      customerCompany: info.department,
      items: List.of(cart.items),
      deliveryType: _deliveryType,
      address: '',
      phone: '',
      remark: _remarkCtrl.text.trim(),
      goodsAmount: goodsAmount,
      deliveryFee: deliveryFee,
      totalAmount: total,
      status: OrderStatus.pendingPayment,
      createdAt: DateTime.now(),
      isMealCollector: _isMealCollector,
      collectorName: _isMealCollector ? info.name : '',
      collectorPhone:
          _isMealCollector ? (_selectedAddress?.phone ?? '') : '',
      collectorAddress: collectorAddress,
      collectorLatitude: _selectedAddress?.latitude,
      collectorLongitude: _selectedAddress?.longitude,
      collectorPoiName: _selectedAddress?.locationDisplayName ??
          _selectedAddress?.poiName ??
          '',
      collectorAddressText: _selectedAddress?.addressText.isNotEmpty == true
          ? _selectedAddress!.addressText
          : (_selectedAddress?.locationDisplayName.isNotEmpty == true
              ? _selectedAddress!.locationDisplayName
              : ''),
    );

    try {
      final created = await OrderApi(context.read<ApiClient>())
          .createOrder(order, userId: user?.id, couponClaimId: _couponClaimId);
      if (user != null) {
        await context.read<OrderState>().refreshForRole(
              role: UserRole.employee,
              userId: user.id,
            );
      }
      cart.clear();
      if (!mounted) return;

      if (created.employeePayAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('订单已提交，等待商家确认')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      if (created.status == OrderStatus.pendingPayment &&
          created.employeePayAmount > 0) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OrderPaymentPage(order: created),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('订单已提交')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下单失败：$e')),
      );
    }
  }

  Future<void> _pickAddress() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined, color: AppColors.primary),
              title: const Text('地图选点'),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.list_alt_outlined, color: AppColors.primary),
              title: const Text('从地址列表选择'),
              onTap: () => Navigator.pop(ctx, 'list'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'list') {
      final picked = await AddressPickerSheet.show(context);
      if (picked != null && mounted) {
        setState(() => _selectedAddress = picked);
      }
      return;
    }
    final mapResult = await MapPickerPage.open(
      context,
      title: '统一取餐地点',
      initial: _selectedAddress?.hasMapCoordinates == true
          ? MapPickResult(
              addressText: _selectedAddress!.addressText.isNotEmpty
                  ? _selectedAddress!.addressText
                  : _selectedAddress!.fullOrderAddress,
              poiName: _selectedAddress!.poiName,
              name: _selectedAddress!.locationDisplayName,
              latitude: _selectedAddress!.latitude!,
              longitude: _selectedAddress!.longitude!,
            )
          : null,
    );
    if (mapResult == null || !mounted) return;
    final base = _selectedAddress ?? context.read<AddressState>().defaultAddress;
    setState(() {
      _selectedAddress = (base ??
              DeliveryAddress(
                id: 'map_${DateTime.now().millisecondsSinceEpoch}',
                receiverName:
                    context.read<AppState>().currentUser?.name ?? '取餐人',
                phone: '',
              ))
          .copyWith(
        addressText: mapResult.addressText,
        poiName: mapResult.poiName,
        name: mapResult.displayName,
        latitude: mapResult.latitude,
        longitude: mapResult.longitude,
        detail: mapResult.addressText.isNotEmpty
            ? mapResult.addressText
            : mapResult.displayName,
      );
    });
  }
}

class _MealCollectorSwitchRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _MealCollectorSwitchRow({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Row(
        children: [
          const Icon(Icons.person_outline,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '我负责今天统一取餐',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CollectorNameRow extends StatelessWidget {
  const _CollectorNameRow();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final name = (user?.name.isNotEmpty == true) ? user!.name : '取餐人';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          const Text(
            '取餐人姓名',
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          const Spacer(),
          Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectorRemarkRow extends StatelessWidget {
  final TextEditingController controller;
  const _CollectorRemarkRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.sticky_note_2_outlined,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          const Text('备注',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textPrimary)),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: '取餐说明（选填）',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressSelectRow extends StatelessWidget {
  final DeliveryAddress? address;
  final String label;
  final VoidCallback onTap;

  const _AddressSelectRow({
    required this.address,
    required this.onTap,
    this.label = '收货地址',
  });

  static List<Widget> _addressDisplayWidgets(DeliveryAddress address) {
    final lines = address.mapDisplayLines;
    return lines
        .map(
          (line) => Text(
            line,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: line == lines.first &&
                      address.locationDisplayName.isNotEmpty
                  ? 14
                  : 13,
              fontWeight: line == lines.first &&
                      address.locationDisplayName.isNotEmpty
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: address == null
                  ? const Text(
                      '请选择统一取餐地点',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _addressDisplayWidgets(address!),
                    ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DishImagePlaceholder(
            seed: item.dish.id,
            size: 76,
            imageUrl: item.dish.image,
            dishName: item.dish.name,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.dish.name,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  item.dish.description,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥${item.dish.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 12),
              _QuantitySelector(
                quantity: item.quantity,
                onAdd: () => context
                    .read<CartState>()
                    .addDish(item.dish, context.read<CartState>().merchant!),
                onRemove: () =>
                    context.read<CartState>().removeOne(item.dish),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuantitySelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _QuantitySelector({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleBtn(Icons.remove, onRemove),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary),
          ),
        ),
        _circleBtn(Icons.add, onAdd),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 1.4),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: AppColors.primary),
        ),
      );
}

class _DeliveryRow extends StatelessWidget {
  final DeliveryType value;
  final ValueChanged<DeliveryType> onChanged;
  const _DeliveryRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          const Text('配送方式',
              style: TextStyle(
                  fontSize: 15, color: AppColors.textPrimary)),
          const Spacer(),
          _Seg(
            label: '配送',
            active: value == DeliveryType.delivery,
            onTap: () => onChanged(DeliveryType.delivery),
            side: _SegSide.left,
          ),
          _Seg(
            label: '自取',
            active: value == DeliveryType.selfPickup,
            onTap: () => onChanged(DeliveryType.selfPickup),
            side: _SegSide.right,
          ),
        ],
      ),
    );
  }
}

enum _SegSide { left, right }

class _Seg extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final _SegSide side;

  const _Seg({
    required this.label,
    required this.active,
    required this.onTap,
    required this.side,
  });

  @override
  Widget build(BuildContext context) {
    final radius = side == _SegSide.left
        ? const BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(6),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : const Color(0xFFF2F4F6),
          borderRadius: radius,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _RemarkRow extends StatelessWidget {
  final TextEditingController controller;
  const _RemarkRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.sticky_note_2_outlined,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          const Text('备注',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textPrimary)),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: '口味、偏好等要求（选填）',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                filled: false,
              ),
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final double valueFontSize;
  final bool valueBold;

  const _AmountRow({
    required this.label,
    required this.value,
    required this.color,
    this.valueFontSize = 14,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: valueFontSize,
            color: color,
            fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
