import { getDb } from '../db/database';
import { UserRow } from '../models/types';

/** 默认企业（历史数据 / 试运行迁移） */
export const DEFAULT_COMPANY_ID = 'comp_default';

export function resolveCompanyScope(user: UserRow): {
  companyId: string | null;
  isPlatformAdmin: boolean;
} {
  const companyId = user.company_id ?? null;
  return {
    companyId,
    isPlatformAdmin: user.role === 'admin',
  };
}

/** 后台数据范围 */
export function resolveAdminScope(user: UserRow): {
  isPlatformAdmin: boolean;
  isCompanyAdmin: boolean;
  isMerchant: boolean;
  companyId: string | null;
  merchantId: string | null;
} {
  let merchantId: string | null = null;
  if (user.role === 'merchant') {
    const row = getDb()
      .prepare<[string], { id: string }>(
        'SELECT id FROM merchants WHERE user_id = ? LIMIT 1',
      )
      .get(user.id);
    merchantId = row?.id ?? null;
  }
  return {
    isPlatformAdmin: user.role === 'admin',
    isCompanyAdmin: user.role === 'company_admin',
    isMerchant: user.role === 'merchant',
    companyId: user.company_id ?? null,
    merchantId,
  };
}

/** 构建 SQL WHERE 片段：按企业隔离 */
export function companyFilterSql(
  user: UserRow,
  column = 'company_id',
): { clause: string; params: string[] } {
  const { companyId, isPlatformAdmin } = resolveCompanyScope(user);
  if (isPlatformAdmin) {
    return { clause: '1=1', params: [] };
  }
  if (companyId) {
    return { clause: `${column} = ?`, params: [companyId] };
  }
  return { clause: `${column} = ?`, params: [DEFAULT_COMPANY_ID] };
}

export function merchantFilterSql(
  user: UserRow,
  column = 'merchant_id',
): { clause: string; params: string[] } {
  const scope = resolveAdminScope(user);
  if (scope.isMerchant && scope.merchantId) {
    return { clause: `${column} = ?`, params: [scope.merchantId] };
  }
  return { clause: '1=1', params: [] };
}

export function assertMerchantAccess(user: UserRow, merchantId: string): void {
  const scope = resolveAdminScope(user);
  if (scope.isPlatformAdmin) return;
  if (scope.isMerchant && scope.merchantId === merchantId) return;
  if (scope.isCompanyAdmin) {
    const m = getDb()
      .prepare<[string], { company_id: string | null }>(
        'SELECT company_id FROM merchants WHERE id = ?',
      )
      .get(merchantId);
    if (m?.company_id === scope.companyId) return;
  }
  throw new Error('FORBIDDEN');
}

/** 查询 dish 所属 merchantId，找不到抛 NOT_FOUND */
export function getMerchantIdByDishId(dishId: string): string {
  const row = getDb()
    .prepare<[string], { merchant_id: string }>(
      'SELECT merchant_id FROM dishes WHERE id = ?',
    )
    .get(dishId);
  if (!row) throw new Error('NOT_FOUND');
  return row.merchant_id;
}

/**
 * 订单访问/操作权限判定
 *
 * - admin：放行
 * - company_admin：放行同公司订单
 * - merchant：放行自己店铺的订单
 * - employee：只能访问自己下单的订单
 * - 其它：FORBIDDEN
 */
export function assertOrderAccess(
  user: UserRow,
  order: { user_id: string | null; merchant_id: string; company_id: string | null },
): void {
  const scope = resolveAdminScope(user);
  if (scope.isPlatformAdmin) return;
  if (scope.isCompanyAdmin) {
    if (order.company_id && order.company_id === scope.companyId) return;
    throw new Error('FORBIDDEN');
  }
  if (scope.isMerchant) {
    if (scope.merchantId && scope.merchantId === order.merchant_id) return;
    throw new Error('FORBIDDEN');
  }
  if (user.role === 'employee') {
    if (order.user_id && order.user_id === user.id) return;
    throw new Error('FORBIDDEN');
  }
  throw new Error('FORBIDDEN');
}
