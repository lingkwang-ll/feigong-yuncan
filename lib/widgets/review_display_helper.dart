import '../mock/mock_data.dart';

/// 评价列表展示时将 userId 映射为员工昵称（仅 UI 层）
String reviewEmployeeDisplayName(String userId) {
  if (userId == MockData.employeeUser.id) {
    return MockData.employeeUser.name;
  }
  return '员工';
}
