import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/auth_api.dart';
import '../mock/mock_data.dart';
import '../models/employee_profile_model.dart';
import '../models/user_model.dart';
import '../utils/jwt_util.dart';
import '../utils/phone_format.dart';
import '../utils/trial_run_policy.dart';
import 'local_storage.dart';

/// 登录身份持久化
class AuthRepository {
  AuthRepository(
    this._storage, {
    AuthApi? authApi,
    ApiClient? apiClient,
  })  : _api = authApi,
        _apiClient = apiClient;

  final LocalStorage _storage;
  final AuthApi? _api;
  final ApiClient? _apiClient;

  static const _keyUser = 'auth.current_user';
  static const _keyToken = 'auth.access_token';
  static const _keySession = 'auth.session';

  bool get _useApi =>
      AppConfig.dataSourceMode == DataSourceMode.api && _api != null;

  /// 启动恢复登录（API 模式会校验 token 与服务端会话）
  Future<({User? user, AuthSession? session, bool sessionExpired})>
      loadCurrentUser() async {
    final raw = _storage.getString(_keyUser);
    if (raw == null || raw.isEmpty) {
      return (user: null, session: null, sessionExpired: false);
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cached = User.fromJson(json);
      final cachedSession = _loadCachedSession();

      if (!_useApi) {
        final session = _localSessionForUser(cached);
        await _saveSession(session);
        return (user: cached, session: session, sessionExpired: false);
      }

      final token = _storage.getString(_keyToken);
      if (token == null || token.isEmpty || JwtUtil.isExpired(token)) {
        await _clearLocalOnly();
        return (user: null, session: null, sessionExpired: true);
      }

      _apiClient?.setAuthToken(token);
      _apiClient?.setAuthUser(cached.id);

      try {
        final remote = await _api!.fetchAuthSession();
        final user = remote.user.copyWith(phone: remote.user.phone);
        await _storage.setString(_keyUser, jsonEncode(user.toJson()));
        await _storage.setString(_keyToken, token);
        await _saveSession(remote.session);
        return (user: user, session: remote.session, sessionExpired: false);
      } on ApiException catch (e) {
        if (e.code == 401) {
          await _clearLocalOnly();
          return (user: null, session: null, sessionExpired: true);
        }
        if (cached.role == UserRole.employee) {
          final allowed = LoginPhonePolicy.roleForPhone(cached.phone);
          if (allowed == null || allowed != cached.role) {
            await _clearLocalOnly();
            return (user: null, session: null, sessionExpired: false);
          }
        }
        return (user: cached, session: cachedSession, sessionExpired: false);
      }
    } catch (_) {
      await _clearLocalOnly();
      return (user: null, session: null, sessionExpired: false);
    }
  }

  AuthSession? _loadCachedSession() {
    final raw = _storage.getString(_keySession);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AuthSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(AuthSession session) async {
    await _storage.setString(_keySession, jsonEncode(session.toJson()));
  }

  AuthSession _localSessionForUser(User user) {
    if (user.role != UserRole.employee) {
      return const AuthSession(employeeProfileStatus: EmployeeProfileStatus.unbound);
    }
    final info = LoginPhonePolicy.employeeInfoForPhone(user.phone);
    if (info == null) {
      return const AuthSession(employeeProfileStatus: EmployeeProfileStatus.unbound);
    }
    return AuthSession(
      employeeProfileStatus: EmployeeProfileStatus.bound,
      employeeProfile: EmployeeProfile(
        id: 'local_${user.id}',
        userId: user.id,
        employeeName: info.name,
        employeeNo: '001',
        phone: user.phone,
        departmentId: 'dept_local',
        departmentName: info.department,
        roleType: 'employee',
        bindStatus: EmployeeProfileStatus.bound,
        createdAt: '',
        updatedAt: '',
      ),
    );
  }

  /// 账号密码登录
  Future<({User user, AuthSession session})> login({
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    final normalizedPhone = LoginPhonePolicy.normalize(phone);
    if (!isValidPhoneFormat(normalizedPhone)) {
      throw StateError('手机号格式不正确');
    }

    if (_useApi) {
      try {
        final result = await _api!.passwordLogin(
          phone: normalizedPhone,
          password: password,
          role: role,
        );
        final fixed = result.user.copyWith(phone: normalizedPhone);
        await saveCurrentUser(fixed, token: result.token, session: result.session);
        return (user: fixed, session: result.session);
      } on ApiException {
        rethrow;
      }
    }
    final allowedRole = LoginPhonePolicy.roleForPhone(phone);
    if (allowedRole == null) {
      throw StateError(LoginPhonePolicy.unsupportedHint);
    }
    if (password != '123456') {
      throw StateError('密码错误');
    }
    final base = allowedRole == UserRole.employee
        ? MockData.employeeUser
        : MockData.merchantUser;
    final user = User(
      id: base.id,
      name: base.name,
      phone: normalizedPhone,
      role: allowedRole,
    );
    final session = _localSessionForUser(user);
    await saveCurrentUser(user, session: session);
    return (user: user, session: session);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_useApi) {
      await _api!.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      return;
    }
    if (oldPassword != '123456') {
      throw StateError('原密码错误');
    }
    if (newPassword.length < 6) {
      throw StateError('新密码至少 6 位');
    }
  }

  /// 发送登录短信验证码（保留，UI 不再使用）
  Future<void> sendLoginSmsCode(String phone) async {
    final normalizedPhone = LoginPhonePolicy.normalize(phone);
    if (!isValidPhoneFormat(normalizedPhone)) {
      throw StateError('手机号格式不正确');
    }
    if (_useApi) {
      await _api!.sendSmsCode(phone: normalizedPhone, scene: 'login');
    }
  }

  /// 短信验证码登录（保留兼容）
  Future<({User user, AuthSession session})> smsLogin({
    required String phone,
    required String code,
    required UserRole role,
  }) async {
    final normalizedPhone = LoginPhonePolicy.normalize(phone);
    if (!isValidPhoneFormat(normalizedPhone)) {
      throw StateError('手机号格式不正确');
    }

    if (_useApi) {
      try {
        final result = await _api!.smsLogin(
          phone: normalizedPhone,
          code: code,
          role: role,
        );
        final fixed = result.user.copyWith(phone: normalizedPhone);
        await saveCurrentUser(fixed, token: result.token, session: result.session);
        return (user: fixed, session: result.session);
      } on ApiException {
        rethrow;
      }
    }
    if (code != '123456') {
      throw StateError('密码错误');
    }
    return login(phone: phone, password: code, role: role);
  }

  Future<AuthSession> refreshAuthSession() async {
    if (!_useApi) {
      final raw = _storage.getString(_keyUser);
      if (raw == null) {
        return const AuthSession(
          employeeProfileStatus: EmployeeProfileStatus.unbound,
        );
      }
      final user = User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final session = _localSessionForUser(user);
      await _saveSession(session);
      return session;
    }
    final token = _storage.getString(_keyToken);
    if (token != null && token.isNotEmpty) {
      _apiClient?.setAuthToken(token);
    }
    final remote = await _api!.fetchAuthSession();
    await _saveSession(remote.session);
    final user = remote.user;
    await _storage.setString(_keyUser, jsonEncode(user.toJson()));
    if (token != null && token.isNotEmpty) {
      await _storage.setString(_keyToken, token);
    }
    return remote.session;
  }

  Future<AuthSession> bindEmployeeProfile({
    required String employeeName,
    required String employeeNo,
    required String departmentId,
    required String departmentName,
  }) async {
    if (_useApi) {
      final session = await _api!.bindEmployeeProfile(
        employeeName: employeeName,
        employeeNo: employeeNo,
        departmentId: departmentId,
        departmentName: departmentName,
      );
      await _saveSession(session);
      return session;
    }
    final raw = _storage.getString(_keyUser);
    if (raw == null) throw StateError('未登录');
    final user = User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final session = AuthSession(
      employeeProfileStatus: EmployeeProfileStatus.bound,
      employeeProfile: EmployeeProfile(
        id: 'local_${user.id}',
        userId: user.id,
        employeeName: employeeName,
        employeeNo: employeeNo,
        phone: user.phone,
        departmentId: departmentId,
        departmentName: departmentName,
        roleType: 'employee',
        bindStatus: EmployeeProfileStatus.bound,
        createdAt: '',
        updatedAt: '',
      ),
    );
    await _saveSession(session);
    return session;
  }

  Future<User?> uploadEmployeeAvatar(Uint8List bytes, String filename) async {
    if (_useApi) {
      try {
        final user = await _api!.uploadEmployeeAvatarBytes(bytes, filename);
        await saveCurrentUser(user);
        return user;
      } on ApiException {
        return null;
      }
    }
    final raw = _storage.getString(_keyUser);
    if (raw == null) return null;
    final current = User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final dataUrl =
        'data:image/jpeg;base64,${base64Encode(bytes)}';
    final user = current.copyWith(avatarUrl: dataUrl);
    await saveCurrentUser(user);
    return user;
  }

  Future<void> saveCurrentUser(
    User user, {
    String? token,
    AuthSession? session,
  }) async {
    await _storage.setString(_keyUser, jsonEncode(user.toJson()));
    if (session != null) {
      await _saveSession(session);
    }
    if (_useApi) {
      _apiClient?.setAuthUser(user.id);
      if (token != null && token.isNotEmpty) {
        await _storage.setString(_keyToken, token);
        _apiClient?.setAuthToken(token);
      }
    }
  }

  Future<void> clearCurrentUser() async {
    if (_useApi) {
      try {
        await _api!.logout();
      } catch (_) {}
    }
    await _clearLocalOnly();
  }

  Future<void> handleUnauthorized() async {
    await _clearLocalOnly();
  }

  Future<void> _clearLocalOnly() async {
    _apiClient?.setAuthUser(null);
    _apiClient?.setAuthToken(null);
    await _storage.remove(_keyUser);
    await _storage.remove(_keyToken);
    await _storage.remove(_keySession);
  }
}
