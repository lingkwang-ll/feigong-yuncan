import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/employee_profile_model.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/section_card.dart';

/// 员工身份绑定页
class EmployeeBindPage extends StatefulWidget {
  const EmployeeBindPage({super.key, this.rejected = false});

  final bool rejected;

  @override
  State<EmployeeBindPage> createState() => _EmployeeBindPageState();
}

class _EmployeeBindPageState extends State<EmployeeBindPage> {
  final _nameCtrl = TextEditingController();
  final _noCtrl = TextEditingController();
  DepartmentOption? _department;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final no = _noCtrl.text.trim();
    if (name.isEmpty) {
      _toast('请输入姓名');
      return;
    }
    if (no.isEmpty) {
      _toast('请输入工号');
      return;
    }
    if (_department == null) {
      _toast('请选择部门');
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<AppState>().bindEmployeeProfile(
            employeeName: name,
            employeeNo: no,
            departmentId: _department!.id,
            departmentName: _department!.name,
          );
      if (!mounted) return;
      if (context.read<AppState>().employeeProfileStatus ==
          EmployeeProfileStatus.bound) {
        _toast('绑定成功');
      }
    } on StateError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 72)),
              const SizedBox(height: 20),
              const Text(
                '绑定员工身份',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '首次登录请填写企业内部信息，绑定后方可订餐',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (widget.rejected)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Text(
                    '上次绑定未通过审核，请核对信息后重新提交，或联系企业管理员。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FieldLabel('姓名'),
                    _TextField(
                      controller: _nameCtrl,
                      hint: '请输入真实姓名',
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel('工号'),
                    _TextField(
                      controller: _noCtrl,
                      hint: '请输入工号',
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel('部门'),
                    DropdownButtonFormField<DepartmentOption>(
                      initialValue: _department,
                      decoration: _inputDecoration('请选择部门'),
                      items: kBindDepartmentOptions
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(d.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _department = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              PrimaryActionButton(
                label: _submitting ? '提交中…' : '提交绑定',
                onPressed: _submitting ? null : _submit,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.read<AppState>().logout(),
                child: const Text(
                  '退出登录',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmployeeBindPendingPage extends StatelessWidget {
  const EmployeeBindPendingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const Spacer(),
              const Icon(
                Icons.hourglass_top_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 20),
              const Text(
                '身份审核中',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '您的员工身份绑定已提交，请等待管理员审核通过后使用订餐功能。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              PrimaryActionButton(
                label: '刷新状态',
                onPressed: () => context.read<AppState>().refreshAuthSession(),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.read<AppState>().logout(),
                child: const Text(
                  '退出登录',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _TextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: _inputDecoration(hint),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
    filled: true,
    fillColor: AppColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
  );
}
