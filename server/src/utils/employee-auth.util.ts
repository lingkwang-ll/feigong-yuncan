import { UserRow } from '../models/types';

export const EMPLOYEE_APP_ROLES = ['employee', 'company_admin'] as const;

export type EmployeeAppRole = (typeof EMPLOYEE_APP_ROLES)[number];

export function isEmployeeAppRole(role: string): role is EmployeeAppRole {
  return (EMPLOYEE_APP_ROLES as readonly string[]).includes(role);
}

export function userCanOrder(user: UserRow): boolean {
  const raw = (user as UserRow & { can_order?: number }).can_order;
  if (raw === 0) return false;
  return true;
}

/** 员工端登录白名单校验（不自动建号） */
export function assertEmployeeAppLogin(user: UserRow | undefined): UserRow {
  if (!user) {
    throw new Error('EMPLOYEE_NOT_REGISTERED');
  }
  if (!isEmployeeAppRole(user.role)) {
    throw new Error('EMPLOYEE_ROLE_MISMATCH');
  }
  if ((user.status ?? 'active') !== 'active') {
    throw new Error('EMPLOYEE_DISABLED');
  }
  if (!user.company_id) {
    throw new Error('EMPLOYEE_NOT_REGISTERED');
  }
  if (!userCanOrder(user)) {
    throw new Error('EMPLOYEE_ORDER_FORBIDDEN');
  }
  return user;
}
