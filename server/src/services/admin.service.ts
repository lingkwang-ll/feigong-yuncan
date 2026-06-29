import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso, userToDto, dishToDto } from '../models/mappers';
import {
  DishRow,
  EmployeeProfileRow,
  DishCategory,
  MealType,
  OrderRow,
  UserRow,
} from '../models/types';
import { companyFilterSql, DEFAULT_COMPANY_ID, resolveAdminScope, assertMerchantAccess, getMerchantIdByDishId } from '../utils/company-scope.util';
import { suggestDishCategory } from '../utils/dish-category-suggest.util';
import { userCanOrder } from '../utils/employee-auth.util';
import { isValidPhone, normalizePhone } from '../utils/phone.util';
import { defaultPasswordHash } from '../utils/password.util';
import { passwordAuthService } from './password-auth.service';
import { signUserToken } from './jwt.service';
import { orderService } from './order.service';
import { systemConfigService } from './system-config.service';
import { dishService } from './dish.service';

export interface AdminEmployeeDto {
  id: string;
  name: string;
  phone: string;
  role: string;
  status: string;
  companyId: string | null;
  companyName: string;
  departmentName: string;
  employeeNo: string;
  canOrder: boolean;
  createdAt: string;
}

function employeeToDto(
  user: UserRow,
  profile?: EmployeeProfileRow,
  companyName?: string,
): AdminEmployeeDto {
  return {
    id: user.id,
    name: profile?.employee_name ?? user.name,
    phone: user.phone,
    role: user.role,
    status: user.status ?? 'active',
    companyId: user.company_id ?? null,
    companyName: companyName ?? user.company_id ?? '—',
    departmentName: profile?.department_name ?? '—',
    employeeNo: profile?.employee_no ?? '—',
    canOrder: userCanOrder(user),
    createdAt: user.created_at,
  };
}

export class AdminService {
  listUsers(user: UserRow, role?: string): UserRow[] {
    const db = getDb();
    const { clause, params } = companyFilterSql(user, 'company_id');
    if (role) {
      return db
        .prepare(
          `SELECT * FROM users WHERE role = ? AND ${clause} ORDER BY created_at DESC`,
        )
        .all(role, ...params) as UserRow[];
    }
    return db
      .prepare(`SELECT * FROM users WHERE ${clause} ORDER BY created_at DESC`)
      .all(...params) as UserRow[];
  }

  setUserStatus(
    operator: UserRow,
    userId: string,
    status: 'active' | 'disabled',
  ): UserRow {
    const db = getDb();
    const target = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId);
    if (!target) throw new Error('NOT_FOUND');

    if (operator.role === 'company_admin') {
      if (target.company_id !== operator.company_id) {
        throw new Error('FORBIDDEN');
      }
      if (target.role === 'admin') {
        throw new Error('FORBIDDEN');
      }
    } else if (operator.role !== 'admin') {
      throw new Error('FORBIDDEN');
    }

    db.prepare('UPDATE users SET status = ?, updated_at = ? WHERE id = ?').run(
      status,
      nowIso(),
      userId,
    );
    return db.prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?').get(userId)!;
  }

  listOrdersSummary(
    user: UserRow,
    opts: { companyId?: string; mealType?: MealType; date?: string },
  ) {
    const db = getDb();
    const { clause, params } = companyFilterSql(user, 'o.company_id');
    let sql = `
      SELECT o.* FROM orders o
      INNER JOIN order_items oi ON oi.order_id = o.id
      WHERE ${clause}
    `;
    const bind: unknown[] = [...params];
    if (opts.companyId && user.role === 'admin') {
      sql += ' AND o.company_id = ?';
      bind.push(opts.companyId);
    }
    if (opts.mealType) {
      sql += ' AND oi.meal_type = ?';
      bind.push(opts.mealType);
    }
    if (opts.date) {
      sql += " AND date(o.created_at) = date(?)";
      bind.push(opts.date);
    }
    sql += ' GROUP BY o.id ORDER BY o.created_at DESC';
    const rows = db.prepare(sql).all(...bind) as OrderRow[];
    return rows.map((o) =>
      orderService.toDisplayDto(o),
    );
  }

  listOrdersForLabels(user: UserRow, date?: string) {
    return this.listOrdersSummary(user, { date });
  }

  listEmployees(user: UserRow): AdminEmployeeDto[] {
    if (resolveAdminScope(user).isMerchant) {
      throw new Error('FORBIDDEN');
    }
    const db = getDb();
    const { clause, params } = companyFilterSql(user, 'u.company_id');
    const rows = db
      .prepare(
        `SELECT u.* FROM users u
         WHERE u.role IN ('employee', 'company_admin') AND ${clause}
         ORDER BY u.created_at DESC`,
      )
      .all(...params) as UserRow[];
    const getProfile = db.prepare<[string], EmployeeProfileRow>(
      'SELECT * FROM employee_profiles WHERE user_id = ?',
    );
    const getCompany = db.prepare<[string], { company_name: string }>(
      'SELECT company_name FROM companies WHERE id = ?',
    );
    return rows.map((u) => {
      const c = u.company_id ? getCompany.get(u.company_id) : undefined;
      return employeeToDto(u, getProfile.get(u.id), c?.company_name);
    });
  }

  createEmployee(
    user: UserRow,
    input: {
      name: string;
      phone: string;
      departmentName: string;
      employeeNo?: string;
      role?: 'employee' | 'company_admin';
      companyId?: string;
      canOrder?: boolean;
      status?: 'active' | 'disabled';
    },
  ): AdminEmployeeDto {
    if (resolveAdminScope(user).isMerchant) throw new Error('FORBIDDEN');
    const phone = normalizePhone(input.phone);
    if (!isValidPhone(phone)) throw new Error('INVALID_PHONE');
    const db = getDb();
    const exists = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(phone);
    if (exists) throw new Error('PHONE_EXISTS');

    const companyId =
      user.role === 'admin'
        ? input.companyId ?? DEFAULT_COMPANY_ID
        : user.company_id ?? DEFAULT_COMPANY_ID;
    const now = nowIso();
    const userId = `u_${nanoid(8)}`;
    const role = input.role ?? 'employee';
    const name = input.name.trim();
    const status = input.status ?? 'active';
    const canOrder = input.canOrder !== false ? 1 : 0;
    const pwdHash = defaultPasswordHash();

    db.prepare(
      `INSERT INTO users
         (id, name, nickname, phone, role, status, company_id, can_order, password_hash, password_updated_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(userId, name, name, phone, role, status, companyId, canOrder, pwdHash, now, now, now);

    const profileId = `ep_${nanoid(8)}`;
    db.prepare(
      `INSERT INTO employee_profiles
         (id, user_id, employee_name, employee_no, phone, department_id, department_name,
          role_type, bind_status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'employee', 'bound', ?, ?)`,
    ).run(
      profileId,
      userId,
      name,
      input.employeeNo?.trim() || phone.slice(-4),
      phone,
      `dept_${nanoid(4)}`,
      input.departmentName.trim() || '未分配',
      now,
      now,
    );

    const created = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId)!;
    const profile = db
      .prepare<[string], EmployeeProfileRow>(
        'SELECT * FROM employee_profiles WHERE user_id = ?',
      )
      .get(userId)!;
    return employeeToDto(created, profile);
  }

  updateEmployee(
    user: UserRow,
    userId: string,
    patch: {
      name?: string;
      phone?: string;
      departmentName?: string;
      employeeNo?: string;
      role?: 'employee' | 'company_admin';
      status?: 'active' | 'disabled';
      canOrder?: boolean;
    },
  ): AdminEmployeeDto {
    if (resolveAdminScope(user).isMerchant) throw new Error('FORBIDDEN');
    const db = getDb();
    const target = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId);
    if (!target) throw new Error('NOT_FOUND');
    if (
      user.role === 'company_admin' &&
      target.company_id !== user.company_id
    ) {
      throw new Error('FORBIDDEN');
    }

    const now = nowIso();
    if (patch.phone) {
      const phone = normalizePhone(patch.phone);
      if (!isValidPhone(phone)) throw new Error('INVALID_PHONE');
      const other = db
        .prepare<[string, string], UserRow>(
          'SELECT * FROM users WHERE phone = ? AND id != ?',
        )
        .get(phone, userId);
      if (other) throw new Error('PHONE_EXISTS');
      db.prepare('UPDATE users SET phone = ?, updated_at = ? WHERE id = ?').run(
        phone,
        now,
        userId,
      );
    }
    if (patch.name) {
      db.prepare(
        'UPDATE users SET name = ?, nickname = ?, updated_at = ? WHERE id = ?',
      ).run(patch.name.trim(), patch.name.trim(), now, userId);
    }
    if (patch.role) {
      db.prepare('UPDATE users SET role = ?, updated_at = ? WHERE id = ?').run(
        patch.role,
        now,
        userId,
      );
    }
    if (patch.status) {
      db.prepare('UPDATE users SET status = ?, updated_at = ? WHERE id = ?').run(
        patch.status,
        now,
        userId,
      );
    }
    if (patch.canOrder !== undefined) {
      db.prepare('UPDATE users SET can_order = ?, updated_at = ? WHERE id = ?').run(
        patch.canOrder ? 1 : 0,
        now,
        userId,
      );
    }

    const profile = db
      .prepare<[string], EmployeeProfileRow>(
        'SELECT * FROM employee_profiles WHERE user_id = ?',
      )
      .get(userId);
    if (profile) {
      const fields: string[] = [];
      const vals: unknown[] = [];
      if (patch.name) {
        fields.push('employee_name = ?');
        vals.push(patch.name.trim());
      }
      if (patch.departmentName) {
        fields.push('department_name = ?');
        vals.push(patch.departmentName.trim());
      }
      if (patch.employeeNo) {
        fields.push('employee_no = ?');
        vals.push(patch.employeeNo.trim());
      }
      if (patch.phone) {
        fields.push('phone = ?');
        vals.push(normalizePhone(patch.phone));
      }
      if (fields.length) {
        fields.push('updated_at = ?');
        vals.push(now, profile.id);
        db.prepare(
          `UPDATE employee_profiles SET ${fields.join(', ')} WHERE id = ?`,
        ).run(...(vals as never[]));
      }
    }

    const updated = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId)!;
    const prof = db
      .prepare<[string], EmployeeProfileRow>(
        'SELECT * FROM employee_profiles WHERE user_id = ?',
      )
      .get(userId);
    return employeeToDto(updated, prof);
  }

  importEmployees(
    user: UserRow,
    rows: {
      name: string;
      phone: string;
      departmentName?: string;
      department?: string;
      employeeNo?: string;
      role?: 'employee' | 'company_admin' | string;
      canOrder?: boolean | string | number;
      status?: 'active' | 'disabled' | string;
      companyId?: string;
    }[],
  ): { created: number; updated: number; skipped: number } {
    if (resolveAdminScope(user).isMerchant) throw new Error('FORBIDDEN');
    let created = 0;
    let updated = 0;
    let skipped = 0;
    for (const row of rows) {
      try {
        const result = this.upsertEmployeeFromImport(user, row);
        if (result === 'created') created++;
        else updated++;
      } catch (e) {
        const code = (e as Error).message;
        if (
          code === 'INVALID_PHONE' ||
          code === 'PHONE_NOT_EMPLOYEE' ||
          code === 'FORBIDDEN'
        ) {
          skipped++;
        } else {
          throw e;
        }
      }
    }
    return { created, updated, skipped };
  }

  /** 导入时按手机号 upsert：已存在则更新姓名与部门 */
  private upsertEmployeeFromImport(
    user: UserRow,
    row: {
      name: string;
      phone: string;
      departmentName?: string;
      department?: string;
      employeeNo?: string;
      role?: 'employee' | 'company_admin' | string;
      canOrder?: boolean | string | number;
      status?: 'active' | 'disabled' | string;
      companyId?: string;
    },
  ): 'created' | 'updated' {
    const phone = normalizePhone(row.phone);
    if (!isValidPhone(phone)) throw new Error('INVALID_PHONE');
    const name = (row.name ?? '').trim();
    if (!name) throw new Error('INVALID_PHONE');

    const departmentName =
      row.departmentName?.trim() || row.department?.trim() || '未分配';

    const db = getDb();
    const existing = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(phone);

    if (existing) {
      if (!['employee', 'company_admin'].includes(existing.role)) {
        throw new Error('PHONE_NOT_EMPLOYEE');
      }
      if (
        user.role === 'company_admin' &&
        existing.company_id !== user.company_id
      ) {
        throw new Error('FORBIDDEN');
      }
      this.updateEmployee(user, existing.id, { name, departmentName });
      return 'updated';
    }

    const role =
      row.role === 'company_admin' ? 'company_admin' : 'employee';
    const status =
      row.status === 'disabled' || row.status === '停用' ? 'disabled' : 'active';
    let canOrder = true;
    if (
      row.canOrder === false ||
      row.canOrder === 0 ||
      row.canOrder === '0' ||
      row.canOrder === 'false'
    ) {
      canOrder = false;
    }
    this.createEmployee(user, {
      name,
      phone,
      departmentName,
      employeeNo: row.employeeNo,
      role,
      companyId: row.companyId,
      canOrder,
      status,
    });
    return 'created';
  }

  listDishes(user: UserRow, merchantId?: string, mealType?: MealType): DishRow[] {
    const scope = resolveAdminScope(user);
    if (scope.isMerchant && scope.merchantId) {
      return dishService.listByMerchant(scope.merchantId, mealType, {
        hideSoldOut: false,
      });
    }
    const db = getDb();
    if (merchantId) {
      return dishService.listByMerchant(merchantId, mealType, {
        hideSoldOut: false,
      });
    }
    const { clause, params } = companyFilterSql(user, 'm.company_id');
    return db
      .prepare(
        `SELECT d.* FROM dishes d
         INNER JOIN merchants m ON m.id = d.merchant_id
         WHERE ${clause}
         ORDER BY d.merchant_id, d.meal_type, d.sort_order ASC, d.created_at ASC`,
      )
      .all(...params) as DishRow[];
  }

  dishDtos(user: UserRow, merchantId?: string, mealType?: MealType) {
    return this.listDishes(user, merchantId, mealType).map(dishToDto);
  }

  getSystemConfig() {
    return systemConfigService.getFullConfig();
  }

  updateSystemConfig(input: {
    mealDeadlines?: Partial<Record<MealType, string>>;
    appSettings?: Partial<import('../models/types').AppSettingsDto>;
  }) {
    return systemConfigService.updateFullConfig(input);
  }

  resetUserPassword(operator: UserRow, targetUserId: string): void {
    if (resolveAdminScope(operator).isMerchant) throw new Error('FORBIDDEN');
    const db = getDb();
    const target = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(targetUserId);
    if (!target) throw new Error('NOT_FOUND');
    if (operator.role === 'company_admin') {
      if (target.company_id !== operator.company_id) {
        throw new Error('FORBIDDEN');
      }
      if (target.role === 'admin') throw new Error('FORBIDDEN');
    } else if (operator.role !== 'admin') {
      throw new Error('FORBIDDEN');
    }
    passwordAuthService.setPasswordHash(targetUserId, '123456');
  }

  adminLoginUser(user: UserRow) {
    return {
      user: userToDto(user),
      token: signUserToken(user),
    };
  }

  /** category 为空的菜品（按商家分组），含建议分类（不落库）。 */
  listCategoryMissingDishes(
    user: UserRow,
    merchantIdFilter?: string,
  ): {
    merchantId: string;
    merchantName: string;
    dishes: Array<{
      merchantId: string;
      merchantName: string;
      dishId: string;
      dishName: string;
      price: number;
      extraPrice: number;
      mealTypes: MealType[];
      mealType: MealType;
      imageUrl: string;
      currentCategory: string;
      suggestedCategory: DishCategory | null;
      reason: string | null;
    }>;
  }[] {
    const scope = resolveAdminScope(user);
    const db = getDb();
    let rows: Array<DishRow & { merchant_name: string }>;

    if (scope.isMerchant && scope.merchantId) {
      rows = db
        .prepare(
          `SELECT d.*, m.name AS merchant_name
           FROM dishes d
           INNER JOIN merchants m ON m.id = d.merchant_id
           WHERE d.merchant_id = ?
             AND trim(coalesce(d.category, '')) = ''
           ORDER BY d.name ASC`,
        )
        .all(scope.merchantId) as Array<DishRow & { merchant_name: string }>;
    } else {
      const { clause, params } = companyFilterSql(user, 'm.company_id');
      const merchantClause = merchantIdFilter ? ' AND d.merchant_id = ?' : '';
      const merchantParams = merchantIdFilter ? [merchantIdFilter] : [];
      rows = db
        .prepare(
          `SELECT d.*, m.name AS merchant_name
           FROM dishes d
           INNER JOIN merchants m ON m.id = d.merchant_id
           WHERE trim(coalesce(d.category, '')) = ''
             AND ${clause}${merchantClause}
           ORDER BY m.name ASC, d.name ASC`,
        )
        .all(...params, ...merchantParams) as Array<
        DishRow & { merchant_name: string }
      >;
    }

    const groupMap = new Map<
      string,
      {
        merchantId: string;
        merchantName: string;
        dishes: Array<{
          merchantId: string;
          merchantName: string;
          dishId: string;
          dishName: string;
          price: number;
          extraPrice: number;
          mealTypes: MealType[];
          mealType: MealType;
          imageUrl: string;
          currentCategory: string;
          suggestedCategory: DishCategory | null;
          reason: string | null;
        }>;
      }
    >();

    for (const row of rows) {
      const dto = dishToDto(row);
      const suggestion = suggestDishCategory(row.name, dto.extraPrice);
      const item = {
        merchantId: row.merchant_id,
        merchantName: row.merchant_name,
        dishId: row.id,
        dishName: row.name,
        price: dto.price,
        extraPrice: dto.extraPrice,
        mealTypes: dto.mealTypes,
        mealType: dto.mealType,
        imageUrl: dto.image,
        currentCategory: dto.category || '',
        suggestedCategory: suggestion.suggestedCategory,
        reason: suggestion.reason,
      };
      const g = groupMap.get(row.merchant_id);
      if (g) {
        g.dishes.push(item);
      } else {
        groupMap.set(row.merchant_id, {
          merchantId: row.merchant_id,
          merchantName: row.merchant_name,
          dishes: [item],
        });
      }
    }

    return Array.from(groupMap.values());
  }

  /** 仅更新菜品 category，不改价格、餐段、图片等。 */
  updateDishCategoryOnly(
    operator: UserRow,
    dishId: string,
    category: DishCategory,
  ): DishRow {
    if (!category) {
      throw new Error('INVALID_CATEGORY');
    }
    const merchantId = getMerchantIdByDishId(dishId);
    assertMerchantAccess(operator, merchantId);
    return dishService.update(dishId, { category });
  }

  batchUpdateDishCategories(
    operator: UserRow,
    items: Array<{ dishId: string; category: DishCategory }>,
  ): DishRow[] {
    const out: DishRow[] = [];
    for (const item of items) {
      out.push(this.updateDishCategoryOnly(operator, item.dishId, item.category));
    }
    return out;
  }
}

export const adminService = new AdminService();
