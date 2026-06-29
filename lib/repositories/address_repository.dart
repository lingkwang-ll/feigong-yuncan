import 'dart:convert';

import '../models/address_model.dart';
import 'local_storage.dart';

/// 员工收货地址本地持久化
class AddressRepository {
  AddressRepository(this._storage);

  final LocalStorage _storage;
  static const _keyAddresses = 'address.list';

  Future<List<DeliveryAddress>> loadAddresses() async {
    final raw = _storage.getString(_keyAddresses);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => DeliveryAddress.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAddresses(List<DeliveryAddress> addresses) async {
    final encoded =
        jsonEncode(addresses.map((e) => e.toJson()).toList());
    await _storage.setString(_keyAddresses, encoded);
  }
}
