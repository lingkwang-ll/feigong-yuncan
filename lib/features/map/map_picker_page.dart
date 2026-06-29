import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../models/map_pick_result.dart';
import '../../theme/app_theme.dart';
import '../../utils/geolocation.dart';
import '../../widgets/app_button.dart';
import 'amap_picker_iframe.dart';

/// 地图选点页 — Web + 已配置 Key 时使用高德 H5 完整选点；否则降级手动填写
class MapPickerPage extends StatefulWidget {
  final MapPickResult? initial;
  final String title;

  const MapPickerPage({
    super.key,
    this.initial,
    this.title = '选择位置',
  });

  static Future<MapPickResult?> open(
    BuildContext context, {
    MapPickResult? initial,
    String title = '选择位置',
  }) {
    return Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(initial: initial, title: title),
      ),
    );
  }

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  @override
  Widget build(BuildContext context) {
    final useH5 = kIsWeb && MapConfig.isConfigured;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: useH5 ? Colors.white : AppColors.background,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: useH5
          ? AmapPickerIframe(
              initial: widget.initial,
              onConfirmed: (result) {
                if (mounted) Navigator.pop(context, result);
              },
            )
          : _FallbackPickerBody(initial: widget.initial),
    );
  }
}

/// Key 未配置或非 Web 时的降级选点
class _FallbackPickerBody extends StatefulWidget {
  final MapPickResult? initial;
  const _FallbackPickerBody({this.initial});

  @override
  State<_FallbackPickerBody> createState() => _FallbackPickerBodyState();
}

class _FallbackPickerBodyState extends State<_FallbackPickerBody> {
  final _manualCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  double _lat = 31.2304;
  double _lng = 121.4737;
  String? _locatingError;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && init.hasCoordinates) {
      _lat = init.latitude;
      _lng = init.longitude;
      _manualCtrl.text = init.addressText;
      _nameCtrl.text = init.displayName;
    }
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _locateMe() async {
    final unsupported = geolocationUnsupportedMessage();
    if (unsupported != null) {
      setState(() => _locatingError = unsupported);
      return;
    }
    setState(() => _locatingError = null);
    try {
      final pos = await getCurrentGeoPosition();
      if (pos == null || !mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _locatingError = geolocationErrorMessage(e));
      }
    }
  }

  void _confirm() {
    final address = _manualCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (address.isEmpty && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写地点名称或详细地址')),
      );
      return;
    }
    Navigator.pop(
      context,
      MapPickResult(
        addressText: address.isNotEmpty ? address : name,
        poiName: name,
        name: name,
        latitude: _lat,
        longitude: _lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accentLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            MapConfig.notConfiguredHint,
            style: const TextStyle(fontSize: 13, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: '地点名称',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: '详细地址',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _locateMe,
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('获取当前定位坐标'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
        ),
        if (_locatingError != null) ...[
          const SizedBox(height: 8),
          Text(_locatingError!,
              style: const TextStyle(fontSize: 12, color: AppColors.accent)),
        ],
        const SizedBox(height: 8),
        Text(
          '坐标：${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: PrimaryActionButton(
            label: '确认位置',
            letterSpacing: 2,
            height: 48,
            onPressed: _confirm,
          ),
        ),
      ],
    );
  }
}
