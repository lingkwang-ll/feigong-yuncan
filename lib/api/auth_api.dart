import 'dart:typed_data';

import '../models/employee_profile_model.dart';
import '../models/user_model.dart';
import 'api_client.dart';

/// 鉴权 API（与 `server/` 后端对齐）
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// POST /api/auth/password-login
  Future<({User user, String token, AuthSession session})> passwordLogin({
    required String phone,
    required String password,
    UserRole? role,
  }) async {
    final data = await _client.post(
      '/auth/password-login',
      body: {
        'phone': phone,
        'password': password,
        if (role != null) 'role': role.name,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    final token = map['token']?.toString() ?? '';
    final userMap = (map['user'] as Map).cast<String, dynamic>();
    final user = User.fromJson(userMap);
    final session = AuthSession(
      employeeProfileStatus: EmployeeProfile.parseStatus(
        userMap['employeeProfileStatus'] as String?,
      ),
    );
    _client.setAuthToken(token);
    _client.setAuthUser(user.id);
    return (user: user, token: token, session: session);
  }

  /// POST /api/auth/change-password
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _client.post(
      '/auth/change-password',
      body: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      },
    );
  }

  /// POST /api/auth/sms/send
  Future<void> sendSmsCode({
    required String phone,
    String scene = 'login',
  }) async {
    await _client.post(
      '/auth/sms/send',
      body: {
        'phone': phone,
        'scene': scene,
      },
    );
  }

  /// POST /api/auth/sms/login
  Future<({User user, String token, AuthSession session})> smsLogin({
    required String phone,
    required String code,
    UserRole? role,
  }) async {
    final data = await _client.post(
      '/auth/sms/login',
      body: {
        'phone': phone,
        'code': code,
        if (role != null) 'role': role.name,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    final token = map['token']?.toString() ?? '';
    final userMap = (map['user'] as Map).cast<String, dynamic>();
    final user = User.fromJson(userMap);
    final session = AuthSession(
      employeeProfileStatus: EmployeeProfile.parseStatus(
        userMap['employeeProfileStatus'] as String?,
      ),
    );
    _client.setAuthToken(token);
    _client.setAuthUser(user.id);
    return (user: user, token: token, session: session);
  }

  /// POST /api/auth/login（兼容旧流程 / 脚本）
  Future<({User user, AuthSession session})> login({
    required String phone,
    required String code,
    required UserRole role,
  }) async {
    final data = await _client.post(
      '/auth/login',
      body: {
        'phone': phone,
        'code': code,
        'role': role.name,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    final user = User.fromJson(map);
    final session = AuthSession(
      employeeProfileStatus: EmployeeProfile.parseStatus(
        map['employeeProfileStatus'] as String?,
      ),
    );
    _client.setAuthUser(user.id);
    return (user: user, session: session);
  }

  /// GET /api/auth/me（Bearer Token 校验会话）
  Future<({User user, AuthSession session})> fetchAuthSession() async {
    final data = await _client.get('/auth/me');
    final map = (data as Map).cast<String, dynamic>();
    final userMap = (map['user'] as Map).cast<String, dynamic>();
    final user = User.fromJson(userMap);
    final profileRaw = map['employeeProfile'];
    final session = AuthSession(
      employeeProfile: profileRaw is Map<String, dynamic>
          ? EmployeeProfile.fromJson(profileRaw)
          : null,
      employeeProfileStatus: EmployeeProfile.parseStatus(
        map['employeeProfileStatus'] as String?,
      ),
    );
    return (user: user, session: session);
  }

  /// POST /api/uploads/employee-avatar
  Future<User> uploadEmployeeAvatarBytes(
    List<int> bytes,
    String filename,
  ) async {
    final data = await _client.uploadBytes(
      '/uploads/employee-avatar',
      fieldName: 'file',
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      filename: filename,
    );
    final map = (data as Map).cast<String, dynamic>();
    final userMap = (map['user'] as Map).cast<String, dynamic>();
    return User.fromJson(userMap);
  }

  /// POST /api/auth/employee-profile/bind
  Future<AuthSession> bindEmployeeProfile({
    required String employeeName,
    required String employeeNo,
    required String departmentId,
    required String departmentName,
  }) async {
    final data = await _client.post(
      '/auth/employee-profile/bind',
      body: {
        'employeeName': employeeName,
        'employeeNo': employeeNo,
        'departmentId': departmentId,
        'departmentName': departmentName,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    final profileRaw = map['employeeProfile'];
    return AuthSession(
      employeeProfile: profileRaw is Map<String, dynamic>
          ? EmployeeProfile.fromJson(profileRaw)
          : null,
      employeeProfileStatus: EmployeeProfile.parseStatus(
        map['employeeProfileStatus'] as String?,
      ),
    );
  }

  /// POST /api/auth/logout
  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } finally {
      _client.setAuthUser(null);
      _client.setAuthToken(null);
    }
  }
}
