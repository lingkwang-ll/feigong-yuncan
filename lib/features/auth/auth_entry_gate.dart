import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/employee_profile_model.dart';
import '../../models/user_model.dart';
import '../../state/app_state.dart';
import '../employee/employee_shell.dart';
import '../merchant/merchant_shell.dart';
import 'employee_bind_page.dart';

/// 根据登录身份与员工档案状态分发入口
class AuthEntryGate extends StatelessWidget {
  const AuthEntryGate({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    if (user == null) return const SizedBox.shrink();

    if (user.role == UserRole.merchant) {
      return const MerchantShell();
    }

    switch (appState.employeeProfileStatus) {
      case EmployeeProfileStatus.bound:
        return const EmployeeShell();
      case EmployeeProfileStatus.pending:
        return const EmployeeBindPendingPage();
      case EmployeeProfileStatus.rejected:
        return const EmployeeBindPage(rejected: true);
      case EmployeeProfileStatus.unbound:
        return const EmployeeBindPage();
    }
  }
}
