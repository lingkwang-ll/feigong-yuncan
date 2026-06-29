import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MealType } from '../models/types';
import { overtimeMealUsageService } from './overtime-meal-usage.service';
import { COMPANY_PAY_SUBSIDY_CAP } from '../constants/company-pay.constants';

export interface OvertimeRosterRow {
  id: string;
  work_date: string;
  meal_type: string;
  employee_name: string;
  phone: string;
  department: string;
  employee_no: string | null;
  is_enabled: number;
  source: string;
  created_at: string;
  updated_at: string;
}

export type CompanyPayStatus = 'eligible' | 'used' | 'expired';

export interface OvertimeRosterDto {
  id: string;
  workDate: string;
  mealType: MealType;
  employeeName: string;
  phone: string;
  department: string;
  employeeNo: string;
  isEnabled: boolean;
  source: string;
  createdAt: string;
  updatedAt: string;
  usageStatus?: 'unused' | 'used';
  companyPayStatus?: CompanyPayStatus;
  companyPaySubsidyCap?: number;
  usageMerchantName?: string;
  usageOrderId?: string;
  usageAt?: string;
  usageCompanyPayAmount?: number;
  usageEmployeePayAmount?: number;
  usageOrderTotalAmount?: number;
}

export interface OvertimeRosterInput {
  workDate: string;
  mealType: MealType;
  employeeName: string;
  phone: string;
  department: string;
  employeeNo?: string;
  isEnabled?: boolean;
  source?: string;
}

export interface ImportResult {
  successCount: number;
  failCount: number;
  failures: { row: number; reason: string }[];
}

const ROSTER_MEAL_TYPES: MealType[] = ['breakfast', 'lunch', 'dinner'];

const MEAL_TYPE_ALIASES: Record<string, MealType> = {
  breakfast: 'breakfast',
  lunch: 'lunch',
  dinner: 'dinner',
  早餐: 'breakfast',
  中餐: 'lunch',
  午餐: 'lunch',
  晚餐: 'dinner',
};

export function parseRosterMealType(raw?: string | null): MealType | null {
  const t = (raw ?? '').trim();
  if (!t) return null;
  return MEAL_TYPE_ALIASES[t] ?? MEAL_TYPE_ALIASES[t.toLowerCase()] ?? null;
}

export function mealTypeLabel(mealType: MealType): string {
  switch (mealType) {
    case 'breakfast':
      return '早餐';
    case 'lunch':
      return '中餐';
    case 'dinner':
      return '晚餐';
    default:
      return mealType;
  }
}

function normalizePhone(phone: string): string {
  return phone.replace(/\s+/g, '').trim();
}

function isCorruptText(value?: string | null): boolean {
  const t = (value ?? '').trim();
  if (!t) return true;
  if (/^\?+$/.test(t)) return true;
  if (t.includes('???')) return true;
  return false;
}

function rosterToDto(row: OvertimeRosterRow): OvertimeRosterDto {
  return {
    id: row.id,
    workDate: row.work_date,
    mealType: (row.meal_type as MealType) || 'lunch',
    employeeName: row.employee_name,
    phone: row.phone,
    department: row.department,
    employeeNo: row.employee_no ?? '',
    isEnabled: !!row.is_enabled,
    source: row.source,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function attachUsageMeta(row: OvertimeRosterRow): OvertimeRosterDto {
  const dto = rosterToDto(row);
  const usage = overtimeMealUsageService.getUsageForRoster(row);
  return {
    ...dto,
    usageStatus: usage ? 'used' : 'unused',
    companyPayStatus: dto.isEnabled ? 'eligible' : 'expired',
    companyPaySubsidyCap: COMPANY_PAY_SUBSIDY_CAP,
    usageMerchantName: usage?.merchantName ?? '',
    usageOrderId: usage?.orderId ?? '',
    usageAt: usage?.usedAt ?? '',
    usageCompanyPayAmount: usage?.companyPayAmount ?? 0,
    usageEmployeePayAmount: usage?.employeePayAmount ?? 0,
    usageOrderTotalAmount: usage?.orderTotalAmount ?? 0,
  };
}

export interface RosterMatchInput {
  workDate: string;
  mealType: MealType;
  userId?: string | null;
  phone?: string | null;
  employeeNo?: string | null;
  employeeName?: string | null;
  department?: string | null;
}

function normalizeEmployeeNo(value?: string | null): string {
  return (value ?? '').trim();
}

function namesMatch(rosterName: string, inputName: string): boolean {
  const a = rosterName.trim();
  const b = inputName.trim();
  if (!a || !b) return false;
  if (isCorruptText(a) || isCorruptText(b)) return false;
  return a === b;
}

function departmentsMatch(rosterDept: string, inputDept: string): boolean {
  const a = rosterDept.trim();
  const b = inputDept.trim();
  if (!a || !b) return false;
  if (isCorruptText(a) || isCorruptText(b)) return false;
  return a === b;
}

export class OvertimeRosterService {
  listByDate(workDate: string, mealType?: MealType | null): OvertimeRosterDto[] {
    let sql = `SELECT * FROM overtime_rosters WHERE work_date = ?`;
    const params: unknown[] = [workDate];
    if (mealType) {
      sql += ` AND meal_type = ?`;
      params.push(mealType);
    }
    sql += ` ORDER BY meal_type ASC, created_at ASC`;
    const rows = getDb().prepare(sql).all(...params) as OvertimeRosterRow[];
    return rows.map(attachUsageMeta);
  }

  create(input: OvertimeRosterInput): OvertimeRosterDto {
    const db = getDb();
    const phone = normalizePhone(input.phone);
    if (!phone) throw new Error('PHONE_REQUIRED');
    if (!ROSTER_MEAL_TYPES.includes(input.mealType)) {
      throw new Error('INVALID_MEAL_TYPE');
    }
    const existing = db
      .prepare<[string, string, string], { id: string }>(
        `SELECT id FROM overtime_rosters
         WHERE work_date = ? AND phone = ? AND meal_type = ?`,
      )
      .get(input.workDate, phone, input.mealType);
    if (existing) throw new Error('ROSTER_DUPLICATE');

    const now = nowIso();
    const id = `otr_${nanoid(10)}`;
    db.prepare(
      `INSERT INTO overtime_rosters
         (id, work_date, meal_type, employee_name, phone, department, employee_no,
          is_enabled, source, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.workDate,
      input.mealType,
      input.employeeName.trim(),
      phone,
      input.department.trim(),
      input.employeeNo?.trim() || null,
      input.isEnabled === false ? 0 : 1,
      input.source ?? 'manual',
      now,
      now,
    );
    return attachUsageMeta(this.getById(id)!);
  }

  getById(id: string): OvertimeRosterRow | undefined {
    return getDb()
      .prepare<[string], OvertimeRosterRow>(
        'SELECT * FROM overtime_rosters WHERE id = ?',
      )
      .get(id);
  }

  setEnabled(id: string, enabled: boolean): OvertimeRosterDto {
    const row = this.getById(id);
    if (!row) throw new Error('NOT_FOUND');
    const now = nowIso();
    getDb()
      .prepare(
        'UPDATE overtime_rosters SET is_enabled = ?, updated_at = ? WHERE id = ?',
      )
      .run(enabled ? 1 : 0, now, id);
    return attachUsageMeta(this.getById(id)!);
  }

  delete(id: string): void {
    const r = getDb()
      .prepare('DELETE FROM overtime_rosters WHERE id = ?')
      .run(id);
    if (r.changes === 0) throw new Error('NOT_FOUND');
  }

  /**
   * 按登录员工身份匹配名单（优先级：手机号 → 员工编号 → 姓名+部门）。
   */
  findMatchingRoster(input: RosterMatchInput): OvertimeRosterRow | null {
    if (!ROSTER_MEAL_TYPES.includes(input.mealType)) return null;

    const rows = getDb()
      .prepare<[string, string], OvertimeRosterRow>(
        `SELECT * FROM overtime_rosters
         WHERE work_date = ? AND meal_type = ? AND is_enabled = 1`,
      )
      .all(input.workDate, input.mealType);

    const phone = normalizePhone(input.phone ?? '');
    const employeeNo = normalizeEmployeeNo(input.employeeNo);
    const employeeName = (input.employeeName ?? '').trim();
    const department = (input.department ?? '').trim();

    if (phone) {
      const byPhone = rows.find((r) => normalizePhone(r.phone) === phone);
      if (byPhone) return byPhone;
    }

    if (employeeNo) {
      const byNo = rows.find(
        (r) => normalizeEmployeeNo(r.employee_no) === employeeNo,
      );
      if (byNo) return byNo;
    }

    if (employeeName && department) {
      const byNameDept = rows.find(
        (r) =>
          namesMatch(r.employee_name, employeeName) &&
          departmentsMatch(r.department, department),
      );
      if (byNameDept) return byNameDept;
    }

    return null;
  }

  /**
   * 判定员工是否在指定日期+餐段名单内（启用且匹配）。
   */
  isOnRoster(input: RosterMatchInput): boolean {
    return this.findMatchingRoster(input) != null;
  }

  findRosterId(input: RosterMatchInput): string | null {
    return this.findMatchingRoster(input)?.id ?? null;
  }

  importText(content: string, defaultDate?: string): ImportResult {
    const lines = content
      .replace(/^\uFEFF/, '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l.length > 0);

    const result: ImportResult = { successCount: 0, failCount: 0, failures: [] };
    if (lines.length === 0) return result;

    let startIdx = 0;
    const header = lines[0]!.toLowerCase();
    if (
      header.includes('手机') ||
      header.includes('phone') ||
      header.includes('姓名') ||
      header.includes('餐段')
    ) {
      startIdx = 1;
    }

    const db = getDb();
    const insert = db.prepare(
      `INSERT INTO overtime_rosters
         (id, work_date, meal_type, employee_name, phone, department, employee_no,
          is_enabled, source, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 1, 'import', ?, ?)`,
    );
    const existsStmt = db.prepare<[string, string, string], { id: string }>(
      `SELECT id FROM overtime_rosters WHERE work_date = ? AND phone = ? AND meal_type = ?`,
    );

    const tx = db.transaction(() => {
      for (let i = startIdx; i < lines.length; i++) {
        const rowNum = i + 1;
        const parts = lines[i]!.split(/[,;\t]/).map((p) => p.trim());
        if (parts.length < 4) {
          result.failCount++;
          result.failures.push({
            row: rowNum,
            reason: '列数不足（需日期/餐段/姓名/手机号/部门）',
          });
          continue;
        }

        let workDate: string;
        let mealTypeRaw: string;
        let employeeName: string;
        let phone: string;
        let department: string;
        let employeeNo = '';

        if (/^\d{4}-\d{2}-\d{2}$/.test(parts[0]!)) {
          if (parts.length >= 6) {
            [workDate, mealTypeRaw, employeeName, phone, department] = parts as [
              string,
              string,
              string,
              string,
              string,
            ];
            employeeNo = parts[5] ?? '';
          } else {
            result.failCount++;
            result.failures.push({ row: rowNum, reason: '含日期行需餐段/姓名/手机号/部门' });
            continue;
          }
        } else if (parts.length >= 5) {
          workDate = defaultDate ?? '';
          [mealTypeRaw, employeeName, phone, department] = parts.slice(0, 4) as [
            string,
            string,
            string,
            string,
          ];
          employeeNo = parts[4] ?? '';
        } else {
          workDate = defaultDate ?? '';
          mealTypeRaw = 'lunch';
          [employeeName, phone, department] = parts.slice(0, 3) as [
            string,
            string,
            string,
          ];
          employeeNo = parts[3] ?? '';
        }

        if (!workDate) {
          result.failCount++;
          result.failures.push({ row: rowNum, reason: '缺少日期' });
          continue;
        }

        const mealType = parseRosterMealType(mealTypeRaw);
        if (!mealType) {
          result.failCount++;
          result.failures.push({ row: rowNum, reason: '餐段无效（早餐/中餐/晚餐）' });
          continue;
        }

        phone = normalizePhone(phone);
        if (!phone || (!employeeName && !phone)) {
          result.failCount++;
          result.failures.push({ row: rowNum, reason: '姓名/手机号至少一项可识别' });
          continue;
        }
        if (!department) {
          result.failCount++;
          result.failures.push({ row: rowNum, reason: '部门不能为空' });
          continue;
        }

        if (existsStmt.get(workDate, phone, mealType)) {
          result.failCount++;
          result.failures.push({
            row: rowNum,
            reason: '同一天同餐段同员工已存在',
          });
          continue;
        }

        const now = nowIso();
        try {
          insert.run(
            `otr_${nanoid(10)}`,
            workDate,
            mealType,
            employeeName || phone,
            phone,
            department,
            employeeNo || null,
            now,
            now,
          );
          result.successCount++;
        } catch {
          result.failCount++;
          result.failures.push({ row: rowNum, reason: '写入失败' });
        }
      }
    });
    tx();
    return result;
  }
}

export const overtimeRosterService = new OvertimeRosterService();
