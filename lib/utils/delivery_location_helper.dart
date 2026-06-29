import '../models/order_model.dart';

/// 根据订单状态与地址动态生成交付/配送位置文案（不接地图）
class DeliveryLocationHelper {
  DeliveryLocationHelper._();

  static String statusLocationText(Order order) {
    switch (order.status) {
      case OrderStatus.pendingPayment:
      case OrderStatus.paymentSubmitted:
      case OrderStatus.pendingMerchantConfirm:
        return '等待商家确认订单';
      case OrderStatus.accepted:
        return '商家已接单，正在备餐';
      case OrderStatus.delivering:
        if (order.deliveryType == DeliveryType.selfPickup) {
          return '餐品已备好，请前往取餐';
        }
        final target = _buildingFloorTarget(order.address);
        return target.isEmpty
            ? '商家已出餐，正在配送中'
            : '商家已出餐，正在配送至「$target」';
      case OrderStatus.completed:
        return order.deliveryType == DeliveryType.selfPickup
            ? '订单已取餐 / 已完成'
            : '订单已送达 / 已完成';
      case OrderStatus.cancelled:
        return '订单已取消';
    }
  }

  /// 从订单地址首段提取「楼栋 + 楼层」
  static String _buildingFloorTarget(String address) {
    if (address.isEmpty) return '';
    final firstLine = address.split('\n').first.trim();
    final segments = firstLine.split('·').map((s) => s.trim()).toList();
    if (segments.length >= 2) {
      final building = segments[segments.length - 2];
      final floor = segments.length >= 3 ? segments.last : '';
      if (floor.isNotEmpty) return '$building $floor';
      return building;
    }
    return firstLine;
  }

  /// 将订单 address 格式化为商家多行展示
  static List<String> merchantAddressLines(Order order) {
    if (order.deliveryType == DeliveryType.selfPickup) return const [];
    return formatAddressLines(order.address);
  }

  static List<String> formatAddressLines(String rawAddress) {
    final raw = rawAddress.trim();
    if (raw.isEmpty) return const [];
    if (raw.contains('\n')) {
      return raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    }
    final parts = raw
        .split(' · ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const [];
    if (parts.length == 1) return parts;
    if (parts.length >= 4) {
      return [
        '${parts[0]} · ${parts[1]}',
        parts[2],
        parts[3].startsWith('备注：') ? parts[3] : '备注：${parts[3]}',
        ...parts
            .skip(4)
            .map((p) => p.startsWith('备注：') ? p : '备注：$p'),
      ];
    }
    if (parts.length == 3) {
      final last = parts[2];
      if (last.contains('/')) {
        return ['${parts[0]} · ${parts[1]}', last];
      }
      return [
        '${parts[0]} · ${parts[1]}',
        last.startsWith('备注：') ? last : '备注：$last',
      ];
    }
    if (parts.length == 2) {
      return ['${parts[0]} · ${parts[1]}'];
    }
    return parts;
  }
}
