import { UserRole } from '../models/types';

export const ALL_ROLES: UserRole[] = [
  'admin',
  'company_admin',
  'merchant',
  'employee',
];

export const ADMIN_ROLES: UserRole[] = ['admin', 'company_admin'];

/** 可登录管理后台的角色 */
export const BACKOFFICE_ROLES: UserRole[] = ['admin', 'company_admin', 'merchant'];

export const PLATFORM_ADMIN: UserRole = 'admin';

export const COMPANY_ADMIN: UserRole = 'company_admin';

export function isAdminRole(role: UserRole): boolean {
  return ADMIN_ROLES.includes(role);
}

export function roleRank(role: UserRole): number {
  switch (role) {
    case 'admin':
      return 4;
    case 'company_admin':
      return 3;
    case 'merchant':
      return 2;
    case 'employee':
      return 1;
    default:
      return 0;
  }
}
