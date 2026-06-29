import 'package:flutter/foundation.dart';



import '../models/address_model.dart';

import '../repositories/address_repository.dart';



/// 员工收货地址状态

class AddressState extends ChangeNotifier {

  AddressState({required AddressRepository addressRepository})

      : _repo = addressRepository;



  final AddressRepository _repo;

  List<DeliveryAddress> _addresses = [];

  bool _initialized = false;



  bool get isInitialized => _initialized;

  List<DeliveryAddress> get addresses => List.unmodifiable(_addresses);



  DeliveryAddress? get defaultAddress {

    for (final a in _addresses) {

      if (a.isDefault) return a;

    }

    return _addresses.isNotEmpty ? _addresses.first : null;

  }



  Future<void> initialize() async {

    if (_initialized) return;

    _addresses = await _repo.loadAddresses();

    _initialized = true;

    notifyListeners();

  }



  Future<void> _persist() async {

    await _repo.saveAddresses(_addresses);

    notifyListeners();

  }



  Future<void> addAddress({

    required String receiverName,

    required String phone,

    required String parkArea,

    required String building,

    required String floor,

    required String department,

    required String deskOrRoom,

    required String detail,

    bool setDefault = false,

    double? latitude,

    double? longitude,

    String poiName = '',

    String addressText = '',

    String name = '',

  }) async {

    final id = 'addr_${DateTime.now().millisecondsSinceEpoch}';

    if (setDefault || _addresses.isEmpty) {

      _addresses = _addresses

          .map((a) => a.copyWith(isDefault: false))

          .toList();

    }

    _addresses.add(DeliveryAddress(

      id: id,

      receiverName: receiverName,

      phone: phone,

      parkArea: parkArea,

      building: building,

      floor: floor,

      department: department,

      deskOrRoom: deskOrRoom,

      detail: detail,

      isDefault: setDefault || _addresses.isEmpty,

      latitude: latitude,

      longitude: longitude,

      poiName: poiName,

      addressText: addressText,

      name: name,

    ));

    await _persist();

  }



  Future<void> updateAddress(DeliveryAddress updated) async {

    final i = _addresses.indexWhere((a) => a.id == updated.id);

    if (i < 0) return;

    if (updated.isDefault) {

      _addresses = _addresses

          .map((a) => a.id == updated.id

              ? updated

              : a.copyWith(isDefault: false))

          .toList();

    } else {

      _addresses[i] = updated;

    }

    await _persist();

  }



  Future<void> deleteAddress(String id) async {

    final removed = _addresses.where((a) => a.id == id).toList();

    _addresses.removeWhere((a) => a.id == id);

    if (removed.isNotEmpty &&

        removed.first.isDefault &&

        _addresses.isNotEmpty) {

      _addresses[0] = _addresses[0].copyWith(isDefault: true);

    }

    await _persist();

  }



  Future<void> setDefault(String id) async {

    _addresses = _addresses

        .map((a) => a.copyWith(isDefault: a.id == id))

        .toList();

    await _persist();

  }

}


