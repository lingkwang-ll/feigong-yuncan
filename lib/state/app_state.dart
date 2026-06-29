import 'package:flutter/foundation.dart';

import '../models/employee_profile_model.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

/// 应用全局状态：当前登录用户、登录身份
class AppState extends ChangeNotifier {
  AppState({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  User? _currentUser;
  EmployeeProfile? _employeeProfile;
  EmployeeProfileStatus _employeeProfileStatus = EmployeeProfileStatus.unbound;
  String? _currentMerchantId;
  bool _initialized = false;
  String? _sessionExpiredMessage;

  User? get currentUser => _currentUser;
  EmployeeProfile? get employeeProfile => _employeeProfile;
  EmployeeProfileStatus get employeeProfileStatus => _employeeProfileStatus;
  bool get isLoggedIn => _currentUser != null;
  bool get isEmployeeBound =>
      _currentUser?.role != UserRole.employee ||
      _employeeProfileStatus == EmployeeProfileStatus.bound;
  UserRole? get currentRole => _currentUser?.role;
  bool get isInitialized => _initialized;
  String? get sessionExpiredMessage => _sessionExpiredMessage;

  String? get currentMerchantId => _currentMerchantId;

  void _applySession(AuthSession? session) {
    if (session == null) {
      _employeeProfile = null;
      _employeeProfileStatus = EmployeeProfileStatus.unbound;
      return;
    }
    _employeeProfile = session.employeeProfile;
    _employeeProfileStatus = session.employeeProfileStatus;
  }

  Future<void> handleUnauthorized() async {
    if (_currentUser == null) {
      await _authRepository.handleUnauthorized();
      return;
    }
    _currentUser = null;
    _employeeProfile = null;
    _employeeProfileStatus = EmployeeProfileStatus.unbound;
    _currentMerchantId = null;
    _sessionExpiredMessage = '登录已过期，请重新登录';
    await _authRepository.handleUnauthorized();
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final loaded = await _authRepository.loadCurrentUser();
    _currentUser = loaded.user;
    _applySession(loaded.session);
    if (loaded.user == null && loaded.sessionExpired) {
      _sessionExpiredMessage = '登录已过期，请重新登录';
    }
    _initialized = true;
    notifyListeners();
  }

  void clearSessionExpiredMessage() {
    _sessionExpiredMessage = null;
  }

  Future<void> sendLoginSmsCode(String phone) =>
      _authRepository.sendLoginSmsCode(phone);

  Future<User> loginWithCredentials({
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    _sessionExpiredMessage = null;
    final result = await _authRepository.login(
      phone: phone,
      password: password,
      role: role,
    );
    _currentUser = result.user;
    _applySession(result.session);
    notifyListeners();
    return result.user;
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _authRepository.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  Future<void> refreshAuthSession() async {
    final session = await _authRepository.refreshAuthSession();
    _applySession(session);
    notifyListeners();
  }

  Future<void> bindEmployeeProfile({
    required String employeeName,
    required String employeeNo,
    required String departmentId,
    required String departmentName,
  }) async {
    final session = await _authRepository.bindEmployeeProfile(
      employeeName: employeeName,
      employeeNo: employeeNo,
      departmentId: departmentId,
      departmentName: departmentName,
    );
    _applySession(session);
    await refreshAuthSession();
    notifyListeners();
  }

  Future<bool> uploadEmployeeAvatar(Uint8List bytes, String filename) async {
    final user = await _authRepository.uploadEmployeeAvatar(bytes, filename);
    if (user == null) return false;
    _currentUser = user;
    notifyListeners();
    return true;
  }

  Future<void> setCurrentUser(User user) async {
    _currentUser = user;
    await _authRepository.saveCurrentUser(user);
    notifyListeners();
  }

  void setCurrentMerchantId(String? id) {
    _currentMerchantId = id;
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUser = null;
    _employeeProfile = null;
    _employeeProfileStatus = EmployeeProfileStatus.unbound;
    _currentMerchantId = null;
    _sessionExpiredMessage = null;
    await _authRepository.clearCurrentUser();
    notifyListeners();
  }
}
