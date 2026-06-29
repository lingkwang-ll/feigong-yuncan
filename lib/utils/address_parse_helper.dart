import '../models/address_model.dart';
import '../models/map_pick_result.dart';
import 'address_options.dart';

/// 地图选点结果解析出的表单字段（null 表示保留当前值）
class AddressParseResult {
  final String? parkArea;
  final String? building;
  final String? detail;

  const AddressParseResult({
    this.parkArea,
    this.building,
    this.detail,
  });
}

/// 从地图选点结果解析园区、楼栋、详细备注，供地址编辑表单回填。
AddressParseResult parseAddressFromMapPickResult(
  MapPickResult result,
  DeliveryAddress? current,
) {
  final combined = _combinedText(result);
  final currentDetail = current?.detail ?? '';

  return AddressParseResult(
    parkArea: _matchParkArea(combined),
    building: _matchBuilding(combined, result),
    detail: currentDetail.isEmpty && result.addressText.trim().isNotEmpty
        ? result.addressText.trim()
        : null,
  );
}

String _combinedText(MapPickResult result) {
  return [
    result.addressText,
    result.poiName,
    result.name,
    result.displayName,
  ].where((s) => s.trim().isNotEmpty).join(' ');
}

String? _matchParkArea(String text) {
  if (text.isEmpty) return null;
  final patterns = [...AddressOptions.parkAreas]
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final pattern in patterns) {
    if (text.contains(pattern)) return pattern;
  }
  return null;
}

String? _matchBuilding(String text, MapPickResult result) {
  for (final b in AddressOptions.buildings) {
    if (text.contains(b)) return b;
  }
  final fromPoi = result.displayName;
  if (fromPoi.isNotEmpty) return fromPoi;
  if (result.poiName.trim().isNotEmpty) return result.poiName.trim();
  if (result.name.trim().isNotEmpty) return result.name.trim();
  return null;
}

/// 下拉选项：若当前值不在预设列表中，将其插入首位以便展示
List<String> dropdownItemsWithValue(String value, List<String> base) {
  if (value.isEmpty || base.contains(value)) return base;
  return [value, ...base];
}
