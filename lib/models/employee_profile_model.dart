enum EmployeeProfileStatus { unbound, pending, bound, rejected }

class EmployeeProfile {
  final String id;
  final String userId;
  final String employeeName;
  final String employeeNo;
  final String phone;
  final String departmentId;
  final String departmentName;
  final String roleType;
  final EmployeeProfileStatus bindStatus;
  final String createdAt;
  final String updatedAt;

  const EmployeeProfile({
    required this.id,
    required this.userId,
    required this.employeeName,
    required this.employeeNo,
    required this.phone,
    required this.departmentId,
    required this.departmentName,
    required this.roleType,
    required this.bindStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'employeeName': employeeName,
        'employeeNo': employeeNo,
        'phone': phone,
        'departmentId': departmentId,
        'departmentName': departmentName,
        'roleType': roleType,
        'bindStatus': bindStatus.name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) =>
      EmployeeProfile(
        id: json['id'] as String,
        userId: json['userId'] as String,
        employeeName: json['employeeName'] as String,
        employeeNo: json['employeeNo'] as String,
        phone: json['phone'] as String,
        departmentId: json['departmentId'] as String? ?? '',
        departmentName: json['departmentName'] as String,
        roleType: json['roleType'] as String? ?? 'employee',
        bindStatus: _parseStatus(json['bindStatus'] as String?),
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );

  static EmployeeProfileStatus _parseStatus(String? raw) {
    return EmployeeProfileStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => EmployeeProfileStatus.unbound,
    );
  }

  static EmployeeProfileStatus parseStatus(String? raw) => _parseStatus(raw);
}

class AuthSession {
  final EmployeeProfile? employeeProfile;
  final EmployeeProfileStatus employeeProfileStatus;

  const AuthSession({
    this.employeeProfile,
    required this.employeeProfileStatus,
  });

  Map<String, dynamic> toJson() => {
        'employeeProfile': employeeProfile?.toJson(),
        'employeeProfileStatus': employeeProfileStatus.name,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final profileRaw = json['employeeProfile'];
    return AuthSession(
      employeeProfile: profileRaw is Map<String, dynamic>
          ? EmployeeProfile.fromJson(profileRaw)
          : null,
      employeeProfileStatus: EmployeeProfile.parseStatus(
        json['employeeProfileStatus'] as String?,
      ),
    );
  }
}

/// 部门选项（绑定页下拉）
class DepartmentOption {
  final String id;
  final String name;

  const DepartmentOption({required this.id, required this.name});
}

const kBindDepartmentOptions = [
  DepartmentOption(id: 'dept_admin', name: '行政部'),
  DepartmentOption(id: 'dept_sales', name: '销售部'),
  DepartmentOption(id: 'dept_prod', name: '生产部'),
  DepartmentOption(id: 'dept_mfg', name: '制造部'),
  DepartmentOption(id: 'dept_rd', name: '研发部'),
  DepartmentOption(id: 'dept_fin', name: '财务部'),
  DepartmentOption(id: 'dept_hr', name: '人力资源部'),
];
