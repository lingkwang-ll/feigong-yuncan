import '../../mock/mock_data.dart';

/// 商家端展示评价时，将 userId 映射为员工昵称（仅 UI 层，不改动数据层）
String merchantEmployeeDisplayName(String userId) {
  if (userId == MockData.employeeUser.id) {
    return MockData.employeeUser.name;
  }
  return '员工';
}
