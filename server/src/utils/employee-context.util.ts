import { getDb } from '../db/database';
import { isCorruptDisplayText } from './display-text.util';

const DEPT_ID_LABEL: Record<string, string> = {
  dept_admin: '行政部',
  dept_sales: '销售部',
  dept_prod: '生产部',
  dept_mfg: '生产部',
};

export interface ResolvedEmployeeContext {
  employeeName: string;
  departmentName: string;
  phone: string;
  employeeNo: string;
}

function isCorruptText(value?: string | null): boolean {
  return isCorruptDisplayText(value);
}

/**
 * 解析员工档案：优先 user_id，若部门/姓名为乱码则同手机号下选有效档案。
 */
export function resolveEmployeeContext(input: {
  userId?: string | null;
  userName?: string | null;
  phone?: string | null;
  userCompany?: string | null;
}): ResolvedEmployeeContext {
  const db = getDb();
  const userRow = input.userId
    ? db
        .prepare<[string], { name: string; phone: string }>(
          'SELECT name, phone FROM users WHERE id = ?',
        )
        .get(input.userId)
    : undefined;

  let phoneInput = (input.phone ?? '').trim();
  if (userRow?.phone && phoneInput && phoneInput !== userRow.phone) {
    phoneInput = '';
  }

  let profile = input.userId
    ? db
        .prepare<
          [string],
          {
            employee_name: string;
            employee_no: string;
            department_name: string;
            department_id: string | null;
            phone: string;
          }
        >(
          'SELECT employee_name, employee_no, department_name, department_id, phone FROM employee_profiles WHERE user_id = ?',
        )
        .get(input.userId)
    : undefined;

  const phone = phoneInput || profile?.phone || userRow?.phone || '';

  if (phone) {
    const candidates = db
      .prepare(
        'SELECT employee_name, employee_no, department_name, department_id, phone, user_id FROM employee_profiles WHERE phone = ?',
      )
      .all(phone) as {
      employee_name: string;
      employee_no: string;
      department_name: string;
      department_id: string | null;
      phone: string;
      user_id: string;
    }[];

    const valid = candidates.filter(
      (c) =>
        !isCorruptText(c.department_name) && !isCorruptText(c.employee_name),
    );
    if (valid.length > 0) {
      profile = valid.find((c) => c.user_id === input.userId) ?? valid[0]!;
    }
  }

  let departmentName =
    profile?.department_name?.trim() || (input.userCompany ?? '').trim();
  if (isCorruptText(departmentName) && profile?.department_id) {
    departmentName = DEPT_ID_LABEL[profile.department_id] ?? departmentName;
  }
  if (isCorruptText(departmentName)) {
    departmentName = (input.userCompany ?? '').trim();
  }

  let employeeName = profile?.employee_name?.trim() || '';
  if (isCorruptText(employeeName)) {
    employeeName = (input.userName ?? '').trim();
  }
  if (isCorruptText(employeeName)) {
    employeeName = (userRow?.name ?? '').trim();
  }

  let employeeNo = (profile?.employee_no ?? '').trim();
  if (isCorruptText(employeeNo)) {
    employeeNo = '';
  }

  return { employeeName, departmentName, phone, employeeNo };
}

export function resolveDepartmentForUser(userId?: string | null): string {
  return resolveEmployeeContext({ userId }).departmentName;
}

export function isCorruptEmployeeText(value?: string | null): boolean {
  return isCorruptText(value);
}
