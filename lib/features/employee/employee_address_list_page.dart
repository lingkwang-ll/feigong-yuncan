import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/address_model.dart';
import '../../models/map_pick_result.dart';
import '../../state/address_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../map/map_picker_page.dart';

/// 员工收货地址列表
class EmployeeAddressListPage extends StatelessWidget {
  const EmployeeAddressListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final addressState = context.watch<AddressState>();
    final list = addressState.addresses;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '收货地址',
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
      body: list.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '暂无收货地址',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlineAccentButton(
                    label: '新增地址',
                    onPressed: () => _openEditor(context),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _AddressCard(
                address: list[i],
                onEdit: () => _openEditor(context, address: list[i]),
                onDelete: () => _confirmDelete(context, list[i]),
                onSetDefault: () =>
                    context.read<AddressState>().setDefault(list[i].id),
              ),
            ),
      floatingActionButton: list.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                '新增地址',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
    );
  }

  Future<void> _openEditor(BuildContext context, {DeliveryAddress? address}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddressEditorSheet(address: address),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, DeliveryAddress address) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地址？'),
        content: const Text('删除后不可恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AddressState>().deleteAddress(address.id);
    }
  }
}

class _AddressCard extends StatelessWidget {
  final DeliveryAddress address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final locationLines = address.mapDisplayLines;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              Text(
                address.receiverName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                address.phone,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              if (address.isDefault) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '默认',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (locationLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...locationLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: line == locationLines.first ? 14 : 13,
                    fontWeight: line == locationLines.first
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!address.isDefault)
                TextButton(
                  onPressed: onSetDefault,
                  child: const Text(
                    '设为默认',
                    style: TextStyle(fontSize: 13, color: AppColors.primary),
                  ),
                ),
              TextButton(
                onPressed: onEdit,
                child: const Text(
                  '编辑',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: onDelete,
                child: const Text(
                  '删除',
                  style: TextStyle(fontSize: 13, color: AppColors.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressEditorSheet extends StatefulWidget {
  final DeliveryAddress? address;
  const _AddressEditorSheet({this.address});

  @override
  State<_AddressEditorSheet> createState() => _AddressEditorSheetState();
}

class _AddressEditorSheetState extends State<_AddressEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _detailCtrl;
  bool _isDefault = false;
  double? _latitude;
  double? _longitude;
  String _poiName = '';
  String _addressText = '';
  String _name = '';

  bool get _hasMapLocation =>
      _latitude != null &&
      _longitude != null &&
      (_name.isNotEmpty || _poiName.isNotEmpty || _addressText.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _nameCtrl = TextEditingController(text: a?.receiverName ?? '');
    _phoneCtrl = TextEditingController(text: a?.phone ?? '');
    _detailCtrl = TextEditingController(text: a?.detail ?? '');
    _isDefault = a?.isDefault ?? false;
    _latitude = a?.latitude;
    _longitude = a?.longitude;
    _poiName = a?.poiName ?? '';
    _addressText = a?.addressText ?? '';
    _name = a?.name.isNotEmpty == true ? a!.name : (a?.poiName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final receiverName = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final detail = _detailCtrl.text.trim();
    if (receiverName.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写收货人和手机号')),
      );
      return;
    }
    if (!_hasMapLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择地图定位地址')),
      );
      return;
    }
    final displayName = _name.isNotEmpty ? _name : _poiName;
    final state = context.read<AddressState>();
    if (widget.address == null) {
      await state.addAddress(
        receiverName: receiverName,
        phone: phone,
        parkArea: displayName,
        building: _poiName.isNotEmpty ? _poiName : displayName,
        floor: '',
        department: '',
        deskOrRoom: '',
        detail: detail,
        setDefault: _isDefault,
        latitude: _latitude,
        longitude: _longitude,
        poiName: _poiName,
        addressText: _addressText,
        name: _name,
      );
    } else {
      await state.updateAddress(widget.address!.copyWith(
        receiverName: receiverName,
        phone: phone,
        parkArea: displayName,
        building: _poiName.isNotEmpty ? _poiName : displayName,
        floor: '',
        department: '',
        deskOrRoom: '',
        detail: detail,
        isDefault: _isDefault,
        latitude: _latitude,
        longitude: _longitude,
        poiName: _poiName,
        addressText: _addressText,
        name: _name,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickOnMap() async {
    final result = await MapPickerPage.open(
      context,
      title: '收货地址选点',
      initial: _latitude != null && _longitude != null
          ? MapPickResult(
              addressText: _addressText,
              poiName: _poiName,
              name: _name,
              latitude: _latitude!,
              longitude: _longitude!,
            )
          : null,
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _poiName = result.poiName;
      _addressText = result.addressText;
      _name = result.displayName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      expand: false,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.address == null ? '新增地址' : '编辑地址',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  _field('收货人', _nameCtrl, '请输入收货人姓名'),
                  const SizedBox(height: 10),
                  _field('手机号', _phoneCtrl, '请输入手机号'),
                  const SizedBox(height: 10),
                  _mapLocationCard(),
                  const SizedBox(height: 10),
                  _field(
                    '详细补充说明',
                    _detailCtrl,
                    '例如：5楼前台 / 送到办公室 / 到了电话联系',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Switch(
                        value: _isDefault,
                        onChanged: (v) => setState(() => _isDefault = v),
                        activeTrackColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        activeThumbColor: AppColors.primary,
                      ),
                      const Text(
                        '设为默认地址',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PrimaryActionButton(
              label: '保存',
              letterSpacing: 2,
              height: 48,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapLocationCard() {
    final placeName = _name.isNotEmpty ? _name : _poiName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '地图定位地址',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasMapLocation) ...[
                if (placeName.isNotEmpty)
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.45,
                      ),
                      children: [
                        const TextSpan(
                          text: '地点：',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextSpan(
                          text: placeName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (_addressText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.45,
                      ),
                      children: [
                        const TextSpan(
                          text: '地址：',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextSpan(text: _addressText),
                      ],
                    ),
                  ),
                ],
              ] else
                const Text(
                  '请选择地图定位地址',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickOnMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(_hasMapLocation ? '重新地图选点' : '地图选点'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.background,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          ),
        ),
      ],
    );
  }
}

/// 确认订单页地址选择 BottomSheet
class AddressPickerSheet extends StatelessWidget {
  const AddressPickerSheet({super.key});

  static Future<DeliveryAddress?> show(BuildContext context) {
    return showModalBottomSheet<DeliveryAddress>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const AddressPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<AddressState>().addresses;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Text(
              '选择收货地址',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '暂无地址，请先新增',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...list.map(
                (a) {
                  final lines = a.mapDisplayLines;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined,
                        color: AppColors.primary),
                    title: Text(
                      lines.isNotEmpty ? lines.first : a.receiverName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: lines.length > 1
                        ? Text(
                            lines.sublist(1).join('\n'),
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: a.isDefault
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '默认',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.pop(context, a),
                  );
                },
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmployeeAddressListPage(),
                    ),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('管理收货地址'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
