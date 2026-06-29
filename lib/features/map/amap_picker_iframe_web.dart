import 'dart:async';
import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../models/map_pick_result.dart';

/// 嵌入高德 H5 选点页（web/map_picker.html），通过 postMessage 回传结果
class AmapPickerIframe extends StatefulWidget {
  final MapPickResult? initial;
  final ValueChanged<MapPickResult> onConfirmed;

  const AmapPickerIframe({
    super.key,
    this.initial,
    required this.onConfirmed,
  });

  @override
  State<AmapPickerIframe> createState() => _AmapPickerIframeState();
}

class _AmapPickerIframeState extends State<AmapPickerIframe> {
  late final String _viewType;
  StreamSubscription<html.MessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();
    _viewType = _registerIframe();
    _messageSub = html.window.onMessage.listen(_onMessage);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  String _registerIframe() {
    final lat = widget.initial?.latitude ?? 31.230416;
    final lng = widget.initial?.longitude ?? 121.473701;
    final query = Uri(queryParameters: {
      'key': MapConfig.amapWebKey,
      if (MapConfig.amapSecurityCode.isNotEmpty)
        'security': MapConfig.amapSecurityCode,
      'lat': lat.toString(),
      'lng': lng.toString(),
    }).query;

    final viewId = 'amap-picker-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) {
      final iframe = html.IFrameElement()
        ..src = '/map_picker.html?$query'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..allow = 'geolocation';
      return iframe;
    });
    return viewId;
  }

  void _onMessage(html.MessageEvent event) {
    final raw = event.data;
    if (raw is! String) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['source'] != 'feigong_map_picker') return;
      if (map['action'] != 'confirm') return;
      final p = (map['payload'] as Map).cast<String, dynamic>();
      widget.onConfirmed(
        MapPickResult(
          latitude: (p['latitude'] as num).toDouble(),
          longitude: (p['longitude'] as num).toDouble(),
          poiName: (p['poiName'] ?? '').toString(),
          addressText: (p['addressText'] ?? '').toString(),
          name: (p['name'] ?? p['poiName'] ?? '').toString(),
        ),
      );
    } catch (_) {
      // ignore malformed messages
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
