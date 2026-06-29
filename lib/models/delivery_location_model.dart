import '../models/dish_model.dart';

/// 商家实时配送位置
class DeliveryLocation {
  final double? latitude;
  final double? longitude;
  final String addressText;
  final String status;
  final DateTime? updatedAt;
  final String date;
  final MealType mealType;
  final String merchantId;

  const DeliveryLocation({
    this.latitude,
    this.longitude,
    this.addressText = '',
    this.status = 'delivering',
    this.updatedAt,
    this.date = '',
    this.mealType = MealType.lunch,
    this.merchantId = '',
  });

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      (latitude != 0 || longitude != 0);

  factory DeliveryLocation.fromJson(Map<String, dynamic> json) {
    final lat = json['latitude'];
    final lng = json['longitude'];
    return DeliveryLocation(
      latitude: lat == null ? null : (lat as num).toDouble(),
      longitude: lng == null ? null : (lng as num).toDouble(),
      addressText: (json['addressText'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'delivering',
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
      date: (json['date'] as String?) ?? '',
      mealType: MealType.values.firstWhere(
        (m) => m.name == json['mealType'],
        orElse: () => MealType.lunch,
      ),
      merchantId: (json['merchantId'] as String?) ?? '',
    );
  }
}
