import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MealType } from '../models/types';

export interface OvertimeMealUsageRow {
  id: string;
  roster_id: string | null;
  employee_user_id: string;
  employee_phone: string;
  work_date: string;
  meal_type: string;
  merchant_id: string;
  order_id: string;
  used_at: string;
  created_at: string;
  company_pay_amount: number | null;
  employee_pay_amount: number | null;
  order_total_amount: number | null;
}

export interface OvertimeMealUsageDto {
  id: string;
  rosterId: string;
  employeeUserId: string;
  employeePhone: string;
  workDate: string;
  mealType: MealType;
  merchantId: string;
  merchantName: string;
  orderId: string;
  usedAt: string;
  companyPayAmount: number;
  employeePayAmount: number;
  orderTotalAmount: number;
}

function normalizePhone(phone: string): string {
  return phone.replace(/\s+/g, '').trim();
}

function resolveUsageAmounts(row: OvertimeMealUsageRow): {
  companyPayAmount: number;
  employeePayAmount: number;
  orderTotalAmount: number;
} {
  let companyPayAmount = Number(row.company_pay_amount ?? 0);
  let employeePayAmount = Number(row.employee_pay_amount ?? 0);
  let orderTotalAmount = Number(row.order_total_amount ?? 0);

  if (companyPayAmount <= 0 && row.order_id) {
    const order = getDb()
      .prepare<
        [string],
        {
          company_pay_amount: number | null;
          employee_pay_amount: number | null;
          final_amount: number | null;
          total_amount: number | null;
        }
      >(
        `SELECT company_pay_amount, employee_pay_amount, final_amount, total_amount
         FROM orders WHERE id = ?`,
      )
      .get(row.order_id);
    if (order) {
      companyPayAmount = Number(order.company_pay_amount ?? 0);
      employeePayAmount = Number(order.employee_pay_amount ?? 0);
      orderTotalAmount = Number(
        order.final_amount ?? order.total_amount ?? 0,
      );
    }
  }

  return { companyPayAmount, employeePayAmount, orderTotalAmount };
}

function rowToDto(row: OvertimeMealUsageRow): OvertimeMealUsageDto {
  const merchant = getDb()
    .prepare<[string], { name: string }>('SELECT name FROM merchants WHERE id = ?')
    .get(row.merchant_id);
  const amounts = resolveUsageAmounts(row);
  return {
    id: row.id,
    rosterId: row.roster_id ?? '',
    employeeUserId: row.employee_user_id,
    employeePhone: row.employee_phone,
    workDate: row.work_date,
    mealType: row.meal_type as MealType,
    merchantId: row.merchant_id,
    merchantName: merchant?.name ?? '',
    orderId: row.order_id,
    usedAt: row.used_at,
    ...amounts,
  };
}

export class OvertimeMealUsageService {
  /** 当天该餐段是否已使用过企业代付（下单资格判断，按员工+日期+餐段） */
  hasUsedCompanyPay(input: {
    workDate: string;
    mealType: MealType;
    userId?: string | null;
    phone?: string | null;
  }): boolean {
    return this.getActiveUsage(input) != null;
  }

  getActiveUsage(input: {
    workDate: string;
    mealType: MealType;
    userId?: string | null;
    phone?: string | null;
  }): OvertimeMealUsageRow | undefined {
    const db = getDb();
    const userId = (input.userId ?? '').trim();
    const phone = normalizePhone(input.phone ?? '');
    const mealType = input.mealType;

    if (userId) {
      const byUser = db
        .prepare<[string, string, string], OvertimeMealUsageRow>(
          `SELECT * FROM overtime_meal_usages
           WHERE work_date = ? AND employee_user_id = ? AND meal_type = ?
           LIMIT 1`,
        )
        .get(input.workDate, userId, mealType);
      if (byUser) return byUser;
    }

    if (phone) {
      return db
        .prepare<[string, string, string], OvertimeMealUsageRow>(
          `SELECT * FROM overtime_meal_usages
           WHERE work_date = ? AND employee_phone = ? AND meal_type = ?
           LIMIT 1`,
        )
        .get(input.workDate, phone, mealType);
    }

    return undefined;
  }

  listByWorkDate(workDate: string, mealType?: MealType | null): OvertimeMealUsageDto[] {
    let sql = `SELECT * FROM overtime_meal_usages WHERE work_date = ?`;
    const params: unknown[] = [workDate];
    if (mealType) {
      sql += ` AND meal_type = ?`;
      params.push(mealType);
    }
    sql += ` ORDER BY used_at DESC`;
    const rows = getDb().prepare(sql).all(...params) as OvertimeMealUsageRow[];
    return rows.map(rowToDto);
  }

  /**
   * 后台名单「使用状态」：仅 roster_id 精确匹配，不用手机号兜底。
   */
  getUsageForRoster(row: { id: string }): OvertimeMealUsageDto | null {
    const usage = getDb()
      .prepare<[string], OvertimeMealUsageRow>(
        `SELECT * FROM overtime_meal_usages WHERE roster_id = ? LIMIT 1`,
      )
      .get(row.id);
    if (!usage) return null;

    const amounts = resolveUsageAmounts(usage);
    if (amounts.companyPayAmount <= 0) return null;

    return rowToDto(usage);
  }

  recordUsage(input: {
    workDate: string;
    mealType: MealType;
    userId: string;
    phone: string;
    merchantId: string;
    orderId: string;
    rosterId: string;
    companyPayAmount: number;
    employeePayAmount: number;
    orderTotalAmount: number;
  }): OvertimeMealUsageRow {
    if (input.companyPayAmount <= 0) {
      throw new Error('COMPANY_PAY_AMOUNT_REQUIRED');
    }
    if (!input.rosterId?.trim()) {
      throw new Error('ROSTER_ID_REQUIRED');
    }

    const db = getDb();
    const phone = normalizePhone(input.phone);
    const existing = this.getActiveUsage({
      workDate: input.workDate,
      mealType: input.mealType,
      userId: input.userId,
      phone,
    });
    if (existing) {
      throw new Error('OVERTIME_USAGE_ALREADY_EXISTS');
    }

    const now = nowIso();
    const id = `omu_${nanoid(10)}`;
    db.prepare(
      `INSERT INTO overtime_meal_usages
         (id, roster_id, employee_user_id, employee_phone, work_date, meal_type,
          merchant_id, order_id, used_at, created_at,
          company_pay_amount, employee_pay_amount, order_total_amount)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.rosterId,
      input.userId,
      phone,
      input.workDate,
      input.mealType,
      input.merchantId,
      input.orderId,
      now,
      now,
      input.companyPayAmount,
      input.employeePayAmount,
      input.orderTotalAmount,
    );
    return db
      .prepare<[string], OvertimeMealUsageRow>(
        'SELECT * FROM overtime_meal_usages WHERE id = ?',
      )
      .get(id)!;
  }
}

export const overtimeMealUsageService = new OvertimeMealUsageService();
