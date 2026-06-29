/// 员工收货地址（企业内部定位，不含地图坐标）
class DeliveryAddress {
  final String id;
  final String receiverName;
  final String phone;
  final String parkArea;
  final String building;
  final String floor;
  final String department;
  final String deskOrRoom;
  /// 详细备注，如：到了电话联系 / 放前台
  final String detail;
  final bool isDefault;
  final double? latitude;
  final double? longitude;
  final String poiName;
  final String addressText;
  /// 地图选点地点名称（可与 poiName 相同）
  final String name;

  const DeliveryAddress({
    required this.id,
    required this.receiverName,
    required this.phone,
    this.parkArea = '',
    this.building = '',
    this.floor = '',
    this.department = '',
    this.deskOrRoom = '',
    this.detail = '',
    this.isDefault = false,
    this.latitude,
    this.longitude,
    this.poiName = '',
    this.addressText = '',
    this.name = '',
  });

  bool get hasStructuredLocation =>
      parkArea.isNotEmpty || building.isNotEmpty || floor.isNotEmpty;

  /// 第一行：科技园A区 · 综合楼A座 5楼
  String get locationLine1 {
    if (!hasStructuredLocation) {
      return _legacyPrimaryLine;
    }
    final parts = <String>[
      if (parkArea.isNotEmpty) parkArea,
      if (building.isNotEmpty) building,
      if (floor.isNotEmpty) floor,
    ];
    return parts.join(' · ');
  }

  /// 第二行：行政部 / 前台
  String get locationLine2 {
    if (department.isEmpty && deskOrRoom.isEmpty) return '';
    if (department.isNotEmpty && deskOrRoom.isNotEmpty) {
      return '$department / $deskOrRoom';
    }
    return department.isNotEmpty ? department : deskOrRoom;
  }

  /// 第三行：备注：到了电话联系
  String? get detailRemarkLine =>
      detail.isNotEmpty ? '备注：$detail' : null;

  /// 确认页/卡片多行展示
  List<String> get displayLines {
    if (!hasStructuredLocation && detail.isNotEmpty) {
      return [detail];
    }
    return [
      if (locationLine1.isNotEmpty) locationLine1,
      if (locationLine2.isNotEmpty) locationLine2,
      if (detailRemarkLine != null) detailRemarkLine!,
    ];
  }

  /// 写入订单 address 字段（商家端可见完整串）
  String get fullOrderAddress {
    final mapParts = _mapOrderParts();
    if (mapParts.isNotEmpty) return mapParts.join(' · ');
    if (!hasStructuredLocation && detail.isNotEmpty) return detail;
    final parts = <String>[
      if (locationLine1.isNotEmpty) locationLine1,
      if (locationLine2.isNotEmpty) locationLine2,
      if (detail.isNotEmpty) detail,
    ];
    return parts.join(' · ');
  }

  /// 多行格式（商家卡片展示）
  String get multilineOrderAddress {
    if (hasMapLocation) return mapDisplayLines.join('\n');
    if (!hasStructuredLocation && detail.isNotEmpty) return detail;
    return displayLines.join('\n');
  }

  String get _legacyPrimaryLine {
    if (detail.isEmpty) return '';
    final line = detail.split('\n').first.trim();
    return line;
  }

  DeliveryAddress copyWith({
    String? receiverName,
    String? phone,
    String? parkArea,
    String? building,
    String? floor,
    String? department,
    String? deskOrRoom,
    String? detail,
    bool? isDefault,
    double? latitude,
    double? longitude,
    String? poiName,
    String? addressText,
    String? name,
  }) {
    return DeliveryAddress(
      id: id,
      receiverName: receiverName ?? this.receiverName,
      phone: phone ?? this.phone,
      parkArea: parkArea ?? this.parkArea,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      department: department ?? this.department,
      deskOrRoom: deskOrRoom ?? this.deskOrRoom,
      detail: detail ?? this.detail,
      isDefault: isDefault ?? this.isDefault,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      poiName: poiName ?? this.poiName,
      addressText: addressText ?? this.addressText,
      name: name ?? this.name,
    );
  }

  bool get hasMapCoordinates =>
      latitude != null &&
      longitude != null &&
      (latitude != 0 || longitude != 0);

  /// 地图选点展示名
  String get locationDisplayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (poiName.trim().isNotEmpty) return poiName.trim();
    return '';
  }

  bool get hasMapLocation =>
      locationDisplayName.isNotEmpty || addressText.trim().isNotEmpty;

  /// 确认页/列表展示（地点名 + 详细地址 + 补充说明）
  List<String> get mapDisplayLines {
    final lines = <String>[];
    final dn = locationDisplayName;
    if (dn.isNotEmpty) lines.add(dn);
    final addr = addressText.trim();
    if (addr.isNotEmpty && addr != dn) lines.add(addr);
    if (detail.trim().isNotEmpty) lines.add(detail.trim());
    if (lines.isNotEmpty) return lines;
    return simplifiedDisplayLines;
  }

  /// 简化展示（无地图字段时回退旧结构化地址，不含「备注：」前缀）
  List<String> get simplifiedDisplayLines {
    if (hasMapLocation) return mapDisplayLines;
    final lines = <String>[];
    if (locationLine1.isNotEmpty) lines.add(locationLine1);
    if (locationLine2.isNotEmpty) lines.add(locationLine2);
    if (detail.trim().isNotEmpty) lines.add(detail.trim());
    return lines;
  }

  List<String> _mapOrderParts() {
    return [
      if (locationDisplayName.isNotEmpty) locationDisplayName,
      if (addressText.trim().isNotEmpty &&
          addressText.trim() != locationDisplayName)
        addressText.trim(),
      if (detail.trim().isNotEmpty) detail.trim(),
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'receiverName': receiverName,
        'phone': phone,
        'parkArea': parkArea,
        'building': building,
        'floor': floor,
        'department': department,
        'deskOrRoom': deskOrRoom,
        'detail': detail,
        'isDefault': isDefault,
        'latitude': latitude,
        'longitude': longitude,
        'poiName': poiName,
        'addressText': addressText,
        'name': name,
      };

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) =>
      DeliveryAddress(
        id: json['id'] as String,
        receiverName: json['receiverName'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        parkArea: json['parkArea'] as String? ?? '',
        building: json['building'] as String? ?? '',
        floor: json['floor'] as String? ?? '',
        department: json['department'] as String? ?? '',
        deskOrRoom: json['deskOrRoom'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        isDefault: (json['isDefault'] as bool?) ?? false,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        poiName: json['poiName'] as String? ?? '',
        addressText: json['addressText'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}
