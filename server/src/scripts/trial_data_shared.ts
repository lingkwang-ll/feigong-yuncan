/**
 * 试运行数据共享定义（prepare / seed / export 复用）
 */
import { nanoid } from 'nanoid';
import Database from 'better-sqlite3';
import { nowIso } from '../models/mappers';
import { MealType } from '../models/types';
import { defaultPasswordHash } from '../utils/password.util';

export const TRIAL_MERCHANT_ID = 'm_self';
export const TRIAL_MERCHANT_NAME = '绿健食堂';
export const TRIAL_MERCHANT_USER_ID = 'u_mer_1';
export const TRIAL_MERCHANT_PHONE = '13900000000';

export interface TrialEmployee {
  id: string;
  phone: string;
  name: string;
  department: string;
}

/** 试运行员工白名单（手机号 → 姓名 / 部门） */
export const TRIAL_EMPLOYEES: TrialEmployee[] = [
  { id: 'u_emp_1', phone: '13800000000', name: '张三', department: '行政部' },
  { id: 'u_emp_2', phone: '13800000001', name: '李四', department: '销售部' },
  { id: 'u_emp_3', phone: '13800000002', name: '王五', department: '生产部' },
];

export interface TrialDishSeed {
  name: string;
  description: string;
  price: number;
  mealType: MealType;
  tags: string[];
}

/** 绿健食堂试运行菜品（与 seed.ts buildSelfDishes 一致） */
export function buildTrialDishes(): TrialDishSeed[] {
  return [
    { name: '皮蛋瘦肉粥', description: '咸香细腻', price: 6, mealType: 'breakfast', tags: ['推荐'] },
    { name: '小笼包（6个）', description: '现蒸现吃', price: 8, mealType: 'breakfast', tags: [] },
    { name: '豆浆', description: '现磨', price: 3, mealType: 'breakfast', tags: ['健康'] },
    { name: '黄焖鸡米饭', description: '鸡肉鲜嫩，酱香浓郁', price: 18, mealType: 'lunch', tags: ['推荐'] },
    { name: '番茄炒蛋', description: '家常滋味', price: 12, mealType: 'lunch', tags: [] },
    { name: '青椒牛肉丝', description: '下饭', price: 16, mealType: 'lunch', tags: [] },
    { name: '清炒时蔬', description: '时令蔬菜', price: 6, mealType: 'dinner', tags: ['健康'] },
    { name: '玉米排骨汤', description: '小火慢炖', price: 8, mealType: 'dinner', tags: ['健康'] },
    { name: '杂粮饭', description: '膳食纤维丰富', price: 2, mealType: 'dinner', tags: ['健康'] },
    { name: '鸡胸肉轻食', description: '低脂高蛋白', price: 22, mealType: 'overtime', tags: ['健康', '低脂'] },
    { name: '牛肉饭团', description: '便于携带', price: 14, mealType: 'overtime', tags: ['推荐'] },
    { name: '原味豆浆', description: '现磨', price: 3, mealType: 'overtime', tags: ['健康'] },
  ];
}

export const MEAL_TYPE_LABEL: Record<MealType, string> = {
  breakfast: '早餐',
  lunch: '中餐',
  dinner: '晚餐',
  overtime: '加班餐',
};

export function currentMealPeriod(now = new Date()): MealType {
  const mins = now.getHours() * 60 + now.getMinutes();
  if (mins <= 7 * 60 + 30) return 'breakfast';
  if (mins <= 9 * 60 + 30) return 'lunch';
  if (mins <= 15 * 60) return 'dinner';
  if (mins <= 17 * 60 + 30) return 'overtime';
  return 'dinner';
}

export function clearReviewsIfExists(db: Database.Database): number {
  const row = db
    .prepare(
      `SELECT name FROM sqlite_master WHERE type='table' AND name='reviews'`,
    )
    .get() as { name: string } | undefined;
  if (!row) return 0;
  const before = db.prepare('SELECT COUNT(1) AS c FROM reviews').get() as {
    c: number;
  };
  db.exec('DELETE FROM reviews');
  return before.c;
}

export function clearOrderData(db: Database.Database): {
  orders: number;
  items: number;
} {
  const beforeOrders = db
    .prepare('SELECT COUNT(1) AS c FROM orders')
    .get() as { c: number };
  const beforeItems = db
    .prepare('SELECT COUNT(1) AS c FROM order_items')
    .get() as { c: number };
  db.exec(`
    DELETE FROM order_items;
    DELETE FROM orders;
    DELETE FROM sqlite_sequence WHERE name = 'order_items';
  `);
  return { orders: beforeOrders.c, items: beforeItems.c };
}

export function upsertTrialUsers(db: Database.Database): void {
  const now = nowIso();
  const pwdHash = defaultPasswordHash();
  const upsertEmployee = db.prepare(`
    INSERT INTO users (id, name, nickname, phone, role, status, company_id, can_order, password_hash, password_updated_at, created_at, updated_at)
    VALUES (@id, @name, @name, @phone, @role, 'active', 'comp_default', 1, @pwdHash, @now, @now, @now)
    ON CONFLICT(phone) DO UPDATE SET
      name = excluded.name,
      nickname = excluded.name,
      role = excluded.role,
      status = 'active',
      company_id = COALESCE(users.company_id, 'comp_default'),
      can_order = 1,
      password_hash = COALESCE(users.password_hash, excluded.password_hash),
      password_updated_at = COALESCE(users.password_updated_at, excluded.password_updated_at),
      updated_at = excluded.updated_at
  `);

  for (const e of TRIAL_EMPLOYEES) {
    upsertEmployee.run({
      id: e.id,
      name: e.name,
      phone: e.phone,
      role: 'employee',
      pwdHash,
      now,
    });
  }

  const upsertMerchant = db.prepare(`
    INSERT INTO users (id, name, nickname, phone, role, status, company_id, can_order, password_hash, password_updated_at, created_at, updated_at)
    VALUES (@id, @name, @name, @phone, 'merchant', 'active', 'comp_default', 1, @pwdHash, @now, @now, @now)
    ON CONFLICT(phone) DO UPDATE SET
      name = excluded.name,
      nickname = excluded.name,
      role = 'merchant',
      status = 'active',
      password_hash = COALESCE(users.password_hash, excluded.password_hash),
      password_updated_at = COALESCE(users.password_updated_at, excluded.password_updated_at),
      updated_at = excluded.updated_at
  `);

  upsertMerchant.run({
    id: TRIAL_MERCHANT_USER_ID,
    name: TRIAL_MERCHANT_NAME,
    phone: TRIAL_MERCHANT_PHONE,
    pwdHash,
    now,
  });

  upsertTrialEmployeeProfiles(db);
}

const TRIAL_DEPT_IDS: Record<string, string> = {
  行政部: 'dept_admin',
  销售部: 'dept_sales',
  生产部: 'dept_prod',
};

/** 试运行员工预绑定档案（便于已绑定账号直接进首页） */
export function upsertTrialEmployeeProfiles(db: Database.Database): void {
  const now = nowIso();
  const upsert = db.prepare(`
    INSERT INTO employee_profiles
      (id, user_id, employee_name, employee_no, phone,
       department_id, department_name, role_type, bind_status,
       created_at, updated_at)
    VALUES
      (@id, @userId, @employeeName, @employeeNo, @phone,
       @departmentId, @departmentName, 'employee', 'bound',
       @now, @now)
    ON CONFLICT(user_id) DO UPDATE SET
      employee_name = excluded.employee_name,
      employee_no = excluded.employee_no,
      phone = excluded.phone,
      department_id = excluded.department_id,
      department_name = excluded.department_name,
      bind_status = 'bound',
      updated_at = excluded.updated_at
  `);

  TRIAL_EMPLOYEES.forEach((e, index) => {
    upsert.run({
      id: `ep_${e.id}`,
      userId: e.id,
      employeeName: e.name,
      employeeNo: String(index + 1).padStart(3, '0'),
      phone: e.phone,
      departmentId: TRIAL_DEPT_IDS[e.department] ?? `dept_${index + 1}`,
      departmentName: e.department,
      now,
    });
  });
}

export function ensureTrialMerchant(db: Database.Database): void {
  const now = nowIso();
  const existing = db
    .prepare('SELECT id FROM merchants WHERE id = ?')
    .get(TRIAL_MERCHANT_ID) as { id: string } | undefined;

  if (existing) {
    db.prepare(
      `UPDATE merchants SET
         user_id = ?, name = ?, is_open = 1, updated_at = ?
       WHERE id = ?`,
    ).run(TRIAL_MERCHANT_USER_ID, TRIAL_MERCHANT_NAME, now, TRIAL_MERCHANT_ID);
    return;
  }

  db.prepare(
    `INSERT INTO merchants
       (id, user_id, name, logo_url, address, distance_text, distance,
        rating, month_sold, hygiene_grade, is_open,
        payment_qr_code_url, delivery_fee, created_at, updated_at)
     VALUES (?, ?, ?, 'logo', ?, '0m', 0, 4.8, 1860, 'A', 1, 'qr', 3, ?, ?)`,
  ).run(
    TRIAL_MERCHANT_ID,
    TRIAL_MERCHANT_USER_ID,
    TRIAL_MERCHANT_NAME,
    '科技园 A 区 综合楼 1 层',
    now,
    now,
  );
}

/** 将绿健食堂菜品重置为试运行菜单（不影响其他商家菜品） */
export function ensureTrialDishes(db: Database.Database): number {
  const now = nowIso();
  db.prepare('DELETE FROM dishes WHERE merchant_id = ?').run(TRIAL_MERCHANT_ID);

  const insert = db.prepare(
    `INSERT INTO dishes
       (id, merchant_id, name, image_url, description, price, meal_type,
        tags_json, is_available, is_sold_out, created_at, updated_at)
     VALUES (?, ?, ?, 'dish', ?, ?, ?, ?, 1, 0, ?, ?)`,
  );

  let count = 0;
  for (const d of buildTrialDishes()) {
    insert.run(
      `d_${nanoid(8)}`,
      TRIAL_MERCHANT_ID,
      d.name,
      d.description,
      d.price,
      d.mealType,
      JSON.stringify(d.tags),
      now,
      now,
    );
    count++;
  }
  return count;
}

export function parseCliArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const arg of argv) {
    if (!arg.startsWith('--')) continue;
    const eq = arg.indexOf('=');
    if (eq > 0) {
      out[arg.slice(2, eq)] = arg.slice(eq + 1);
    } else {
      out[arg.slice(2)] = 'true';
    }
  }
  return out;
}

export function formatDateLocal(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
