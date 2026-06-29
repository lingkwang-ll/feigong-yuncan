import 'api_client.dart';
import '../models/delivery_location_model.dart';
import '../models/dish_model.dart';

class DeliveryLocationApi {
  DeliveryLocationApi(this._client);

  final ApiClient _client;

  Future<DeliveryLocation?> getCurrent({
    required String date,
    required MealType mealType,
    required String merchantId,
  }) async {
    final data = await _client.get(
      '/delivery-location/current',
      query: {
        'date': date,
        'mealType': mealType.name,
        'merchantId': merchantId,
      },
    );
    if (data == null) return null;
    return DeliveryLocation.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<DeliveryLocation?> update({
    required String date,
    required MealType mealType,
    required String merchantId,
    required double latitude,
    required double longitude,
    String? addressText,
    String status = 'delivering',
  }) async {
    final data = await _client.post(
      '/delivery-location/update',
      body: {
        'date': date,
        'mealType': mealType.name,
        'merchantId': merchantId,
        'latitude': latitude,
        'longitude': longitude,
        if (addressText != null) 'addressText': addressText,
        'status': status,
      },
    );
    if (data == null) return null;
    return DeliveryLocation.fromJson((data as Map).cast<String, dynamic>());
  }
}
