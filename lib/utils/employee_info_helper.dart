import '../models/user_model.dart';
import 'trial_run_policy.dart';

/// 员工姓名/部门解析（企业内部订餐，非手机号展示）
class EmployeeInfoHelper {
  EmployeeInfoHelper._();

  static ({String name, String department}) resolve({
    User? user,
    String? phone,
    String? address,
  }) {
    final normalized = LoginPhonePolicy.normalize(
      phone ?? user?.phone ?? '',
    );
    final mapped = LoginPhonePolicy.employeeInfoForPhone(normalized);
    if (mapped != null) {
      return mapped;
    }
    final name = (user?.name.isNotEmpty == true) ? user!.name : '员工';
    final dept = _departmentFromAddress(address) ?? '未填写部门';
    return (name: name, department: dept);
  }

  static String? _departmentFromAddress(String? address) {
    if (address == null || address.isEmpty) return null;
    for (final line in address.split('\n')) {
      final t = line.trim();
      if (t.contains('/') && !t.startsWith('备注')) {
        return t.split('/').first.trim();
      }
      if (t.contains('部') && !t.contains('·')) return t;
    }
    return null;
  }

  static String departmentDisplay({
    required String customerCompany,
    required String address,
  }) {
    if (customerCompany.isNotEmpty &&
        !customerCompany.contains('科技') &&
        !customerCompany.contains('公司') &&
        customerCompany.length <= 12) {
      return customerCompany;
    }
    return _departmentFromAddress(address) ?? customerCompany;
  }

  static String addressShort(String address) {
    if (address.isEmpty) return '—';
    final line = address.split('\n').first.trim();
    return line.replaceAll(' · ', '').replaceAll(' ', '');
  }
}
