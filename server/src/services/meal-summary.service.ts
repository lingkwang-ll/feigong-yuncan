import { getDb } from '../db/database';
import { MEAL_TYPE_LABEL } from '../constants/meal';
import {
  nowIso,
  parseOrderExtraItems,
  parseOrderSelectedItems,
} from '../models/mappers';
import { MealType, OrderItemRow, OrderRow, UserRow } from '../models/types';
import {
  assertMerchantAccess,
  companyFilterSql,
  merchantFilterSql,
} from '../utils/company-scope.util';
import { resolveDepartmentForUser } from '../utils/employee-context.util';
import { nanoid } from 'nanoid';

/** @deprecated 兼容 CSV 导出 */
export interface MealLabelItemDto {
  dishName: string;
  quantity: number;
  remark: string;
}

export interface MealLabelDishLineDto {
  name: string;
  quantity: number;
}

export interface MealLabelGroupDto {
  labelCode: string;
  employeeName: string;
  department: string;
  packages: MealLabelDishLineDto[];
  meats: MealLabelDishLineDto[];
  vegetables: MealLabelDishLineDto[];
  extras: MealLabelDishLineDto[];
  /** 扁平列表（兼容旧导出） */
  items: MealLabelItemDto[];
  remark: string;
  amount: number;
  /** 加菜随单展示时整行后缀（随单） */
  extrasFollowOrder?: boolean;
}

export interface DishSummaryItemDto {
  dishName: string;
  quantity: number;
  subtotal: number;
}

export interface MealSummaryDto {
  date: string;
  mealType: MealType;
  mealLabel: string;
  merchantId: string;
  merchantName: string;
  companyId: string | null;
  totalPeople: number;
  totalPortions: number;
  totalAmount: number;
  pendingCount: number;
  completedCount: number;
  phase: string;
  collectorName: string;
  collectorPhone: string;
  collectorAddress: string;
  dishSummary: DishSummaryItemDto[];
  employeeDetails: MealLabelGroupDto[];
  labelGroups: MealLabelGroupDto[];
  batchStatus: 'pending' | 'confirmed';
}

export interface DashboardStatsDto {
  date: string;
  orderPeople: number;
  orderPortions: number;
  orderAmount: number;
  pendingBatches: number;
  completedBatches: number;
  collectorName: string;
  mealStats: Record<
    MealType,
    { people: number; portions: number; amount: number }
  >;
}

const CATEGORY_LABEL: Record<string, string> = {
  meat: '荤菜',
  vegetable: '素菜',
  extra: '加菜',
};

function bumpQty(map: Map<string, number>, name: string, qty: number): void {
  map.set(name, (map.get(name) ?? 0) + qty);
}

function mapToLines(map: Map<string, number>): MealLabelDishLineDto[] {
  return [...map.entries()].map(([name, quantity]) => ({ name, quantity }));
}

function departmentOf(order: OrderRow): string {
  const fromProfile = order.user_id
    ? resolveDepartmentForUser(order.user_id)
    : '';
  if (fromProfile && fromProfile !== '未填写部门') return fromProfile;
  const c = order.user_company?.trim() ?? '';
  if (c && !c.includes('科技') && !c.includes('公司') && c.length <= 12) {
    return c;
  }
  const addr = order.address ?? '';
  for (const line of addr.split('\n')) {
    const t = line.trim();
    if (t.includes('/') && !t.startsWith('备注')) {
      return t.split('/')[0]?.trim() ?? c;
    }
  }
  return c || '未填写部门';
}

function addressShort(raw: string | null | undefined): string {
  if (!raw) return '—';
  const line = raw.split('\n')[0]?.trim() ?? '';
  return line.replace(/ · /g, '').replace(/\s+/g, '') || '—';
}

function isPendingStatus(status: string): boolean {
  return [
    'pendingMerchantConfirm',
    'pendingPayment',
    'paymentSubmitted',
    'accepted',
  ].includes(status);
}

function isCompletedStatus(status: string): boolean {
  return status === 'completed';
}

interface GroupAcc {
  employeeName: string;
  department: string;
  packages: Map<string, number>;
  meats: Map<string, number>;
  vegetables: Map<string, number>;
  extras: Map<string, number>;
  remarks: Set<string>;
  amount: number;
}

interface MealBoxDraft {
  employeeName: string;
  department: string;
  employeeKey: string;
  remark: string;
  packages: Map<string, number>;
  meats: Map<string, number>;
  vegetables: Map<string, number>;
  amount: number;
}

function extractMealBoxesFromOrder(
  order: OrderRow,
  mealType: MealType,
  items: OrderItemRow[],
  dept: string,
  employeeName: string,
): MealBoxDraft[] {
  const employeeKey = groupKey(employeeName, dept);
  const base = {
    employeeName,
    department: dept,
    employeeKey,
    remark: order.remark?.trim() ?? '',
    amount: order.total_amount,
  };

  const selected = parseOrderSelectedItems(order.selected_items_json);
  const extraItems = parseOrderExtraItems(order.extra_items_json);
  const hasStructured =
    selected.length > 0 || extraItems.length > 0 || !!order.package_name;

  if (hasStructured) {
    const packages = new Map<string, number>();
    const meats = new Map<string, number>();
    const vegetables = new Map<string, number>();
    const pkg = order.package_name?.trim() ?? '';
    if (pkg) bumpQty(packages, pkg, 1);
    for (const si of selected) {
      const mt = si.mealType as MealType | undefined;
      if (mt && mt !== mealType) continue;
      const cat = si.category ?? 'vegetable';
      if (cat === 'meat') bumpQty(meats, si.name, 1);
      else if (cat === 'vegetable') bumpQty(vegetables, si.name, 1);
      else if (cat !== 'staple' && cat !== 'soup' && cat !== 'drink') {
        bumpQty(vegetables, si.name, 1);
      }
    }
    if (packages.size + meats.size + vegetables.size === 0) return [];
    return [{ ...base, packages, meats, vegetables }];
  }

  const boxes: MealBoxDraft[] = [];
  const looseMeats = new Map<string, number>();
  const looseVegetables = new Map<string, number>();

  for (const it of items) {
    if (it.meal_type !== mealType) continue;
    const name = it.dish_name;
    if (name.startsWith('【套餐】')) {
      const pkg = name.replace(/^【套餐】/, '');
      for (let i = 0; i < it.quantity; i++) {
        boxes.push({
          ...base,
          packages: new Map([[pkg, 1]]),
          meats: new Map(),
          vegetables: new Map(),
        });
      }
    } else if (!name.startsWith('【加菜】')) {
      bumpQty(looseVegetables, name, it.quantity);
    }
  }

  if (boxes.length === 0 && (looseMeats.size > 0 || looseVegetables.size > 0)) {
    boxes.push({
      ...base,
      packages: new Map(),
      meats: looseMeats,
      vegetables: looseVegetables,
    });
  } else if (boxes.length > 0 && looseVegetables.size > 0) {
    const first = boxes[0]!;
    for (const [n, q] of looseVegetables) bumpQty(first.vegetables, n, q);
  }

  return boxes;
}

function collectOrderExtras(
  order: OrderRow,
  mealType: MealType,
  items: OrderItemRow[],
  target: Map<string, number>,
): void {
  const extraItems = parseOrderExtraItems(order.extra_items_json);
  for (const ex of extraItems) {
    bumpQty(target, ex.name, ex.quantity);
  }
  if (extraItems.length > 0) return;
  for (const it of items) {
    if (it.meal_type !== mealType) continue;
    if (it.dish_name.startsWith('【加菜】')) {
      bumpQty(
        target,
        it.dish_name.replace(/^【加菜】/, ''),
        it.quantity,
      );
    }
  }
}

function groupKey(name: string, dept: string): string {
  return `${name}|${dept}`;
}

function resolveCollector(orders: OrderRow[]): {
  name: string;
  phone: string;
  address: string;
} {
  const collectors = orders.filter((o) => o.is_meal_collector);
  const source =
    collectors.length > 0
      ? collectors
      : orders.filter(
          (o) =>
            (o.collector_address?.trim() ?? '') !== '' ||
            ((o.address?.trim() ?? '') !== '' &&
              (o.phone?.trim() ?? '') !== ''),
        );
  if (source.length === 0) {
    return { name: '—', phone: '—', address: '—' };
  }
  const first = source[0]!;
  return {
    name: first.collector_name?.trim() || first.user_name || '—',
    phone: first.collector_phone?.trim() || first.phone || '—',
    address: addressShort(
      first.collector_address?.trim() || first.address || '',
    ),
  };
}

function fetchOrdersForBatch(
  user: UserRow,
  opts: {
    date: string;
    mealType: MealType;
    merchantId: string;
    companyId?: string;
    status?: string;
  },
): OrderRow[] {
  const db = getDb();
  const { clause, params } = companyFilterSql(user, 'o.company_id');
  let sql = `
    SELECT DISTINCT o.* FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.id
    WHERE ${clause}
      AND o.merchant_id = ?
      AND oi.meal_type = ?
      AND o.status != 'cancelled'
      AND strftime('%Y-%m-%d', o.created_at, '+8 hours') = ?
  `;
  const bind: unknown[] = [
    ...params,
    opts.merchantId,
    opts.mealType,
    opts.date,
  ];
  const { clause: mClause, params: mParams } = merchantFilterSql(
    user,
    'o.merchant_id',
  );
  if (mClause !== '1=1') {
    sql += ` AND ${mClause}`;
    bind.push(...mParams);
  }
  if (opts.companyId && user.role === 'admin') {
    sql += ' AND o.company_id = ?';
    bind.push(opts.companyId);
  }
  if (opts.status === 'pending') {
    sql +=
      " AND o.status IN ('pendingMerchantConfirm','pendingPayment','paymentSubmitted','accepted')";
  } else if (opts.status === 'completed') {
    sql += " AND o.status = 'completed'";
  }
  sql += ' ORDER BY o.created_at ASC';
  return db.prepare(sql).all(...bind) as OrderRow[];
}

function accumulateOrderIntoGroup(
  order: OrderRow,
  mealType: MealType,
  group: GroupAcc,
  items: OrderItemRow[],
): void {
  if (order.remark?.trim()) group.remarks.add(order.remark.trim());

  const selected = parseOrderSelectedItems(order.selected_items_json);
  const extraItems = parseOrderExtraItems(order.extra_items_json);
  const hasStructured =
    selected.length > 0 || extraItems.length > 0 || order.package_name;

  if (hasStructured) {
    if (order.package_name?.trim()) {
      bumpQty(group.packages, order.package_name.trim(), 1);
    }
    for (const si of selected) {
      const cat = si.category ?? 'vegetable';
      if (cat === 'meat') bumpQty(group.meats, si.name, 1);
      else if (cat === 'vegetable') bumpQty(group.vegetables, si.name, 1);
      else if (cat !== 'staple' && cat !== 'soup' && cat !== 'drink') {
        bumpQty(group.vegetables, si.name, 1);
      }
    }
    for (const ex of extraItems) {
      bumpQty(group.extras, ex.name, ex.quantity);
    }
    return;
  }

  // 旧数据兼容：从 order_items 展开
  for (const it of items) {
    if (it.meal_type !== mealType) continue;
    const name = it.dish_name;
    if (name.startsWith('【套餐】')) {
      bumpQty(group.packages, name.replace(/^【套餐】/, ''), it.quantity);
    } else if (name.startsWith('【加菜】')) {
      bumpQty(group.extras, name.replace(/^【加菜】/, ''), it.quantity);
    } else {
      bumpQty(group.vegetables, name, it.quantity);
    }
  }
}

function groupToDto(
  g: GroupAcc,
  labelCode: string,
  extrasFollowOrder = false,
): MealLabelGroupDto {
  const packages = mapToLines(g.packages);
  const meats = mapToLines(g.meats);
  const vegetables = mapToLines(g.vegetables);
  const extras = mapToLines(g.extras);
  const flat: MealLabelItemDto[] = [
    ...packages.map((p) => ({
      dishName: `套餐：${p.name}`,
      quantity: p.quantity,
      remark: '',
    })),
    ...meats.map((m) => ({
      dishName: `${CATEGORY_LABEL.meat}：${m.name}`,
      quantity: m.quantity,
      remark: '',
    })),
    ...vegetables.map((v) => ({
      dishName: `${CATEGORY_LABEL.vegetable}：${v.name}`,
      quantity: v.quantity,
      remark: '',
    })),
    ...extras.map((e) => ({
      dishName: `${CATEGORY_LABEL.extra}：${e.name}`,
      quantity: e.quantity,
      remark: '',
    })),
  ];
  return {
    labelCode,
    employeeName: g.employeeName,
    department: g.department,
    packages,
    meats,
    vegetables,
    extras,
    items: flat,
    remark: [...g.remarks].join('；'),
    amount: Number(g.amount.toFixed(2)),
    extrasFollowOrder,
  };
}

function boxToDto(
  box: MealBoxDraft,
  labelCode: string,
  extras: Map<string, number>,
  extrasFollowOrder: boolean,
): MealLabelGroupDto {
  const packages = mapToLines(box.packages);
  const meats = mapToLines(box.meats);
  const vegetables = mapToLines(box.vegetables);
  const extraLines = mapToLines(extras);
  const flat: MealLabelItemDto[] = [
    ...packages.map((p) => ({
      dishName: `套餐：${p.name}`,
      quantity: p.quantity,
      remark: '',
    })),
    ...meats.map((m) => ({
      dishName: `${CATEGORY_LABEL.meat}：${m.name}`,
      quantity: m.quantity,
      remark: '',
    })),
    ...vegetables.map((v) => ({
      dishName: `${CATEGORY_LABEL.vegetable}：${v.name}`,
      quantity: v.quantity,
      remark: '',
    })),
    ...extraLines.map((e) => ({
      dishName: `${CATEGORY_LABEL.extra}：${e.name}`,
      quantity: e.quantity,
      remark: '',
    })),
  ];
  return {
    labelCode,
    employeeName: box.employeeName,
    department: box.department,
    packages,
    meats,
    vegetables,
    extras: extraLines,
    items: flat,
    remark: box.remark,
    amount: Number(box.amount.toFixed(2)),
    extrasFollowOrder,
  };
}

function buildBatch(
  orders: OrderRow[],
  date: string,
  mealType: MealType,
  merchantId: string,
  merchantName: string,
  companyId: string | null,
): MealSummaryDto {
  const db = getDb();
  const getItems = db.prepare<[string], OrderItemRow>(
    'SELECT * FROM order_items WHERE order_id = ? ORDER BY id ASC',
  );

  const dishPrice = new Map<string, number>();
  const dishRows = db
    .prepare('SELECT name, price FROM dishes WHERE merchant_id = ?')
    .all(merchantId) as { name: string; price: number }[];
  for (const d of dishRows) dishPrice.set(d.name, d.price);

  const dishTotals = new Map<string, { qty: number; subtotal: number }>();
  const people = new Set<string>();
  let totalAmount = 0;
  let pendingCount = 0;
  let completedCount = 0;

  const boxDrafts: MealBoxDraft[] = [];
  const extrasByEmployee = new Map<string, Map<string, number>>();

  for (const order of orders) {
    const items = getItems.all(order.id).filter((it) => it.meal_type === mealType);
    if (items.length === 0) {
      const selected = parseOrderSelectedItems(order.selected_items_json);
      const hasPkg = !!order.package_name?.trim();
      if (selected.length === 0 && !hasPkg) continue;
    }

    people.add(order.user_name ?? order.id);
    totalAmount += order.total_amount;
    if (isPendingStatus(order.status)) pendingCount++;
    if (isCompletedStatus(order.status)) completedCount++;

    const dept = departmentOf(order);
    const name = order.user_name ?? '员工';
    const orderItems =
      items.length > 0
        ? items
        : getItems.all(order.id).filter((it) => it.meal_type === mealType);

    const boxes = extractMealBoxesFromOrder(
      order,
      mealType,
      orderItems,
      dept,
      name,
    );
    boxDrafts.push(...boxes);

    const empExtras =
      extrasByEmployee.get(groupKey(name, dept)) ?? new Map<string, number>();
    collectOrderExtras(order, mealType, orderItems, empExtras);
    extrasByEmployee.set(groupKey(name, dept), empExtras);

    for (const it of orderItems) {
      const price = dishPrice.get(it.dish_name) ?? it.price ?? 0;
      const dt = dishTotals.get(it.dish_name) ?? { qty: 0, subtotal: 0 };
      dt.qty += it.quantity;
      dt.subtotal += price * it.quantity;
      dishTotals.set(it.dish_name, dt);
    }
    for (const si of parseOrderSelectedItems(order.selected_items_json)) {
      const dt = dishTotals.get(si.name) ?? { qty: 0, subtotal: 0 };
      dt.qty += 1;
      dishTotals.set(si.name, dt);
    }
    for (const ex of parseOrderExtraItems(order.extra_items_json)) {
      const dt = dishTotals.get(ex.name) ?? { qty: 0, subtotal: 0 };
      dt.qty += ex.quantity;
      dishTotals.set(ex.name, dt);
    }
  }

  const firstBoxIndexByEmployee = new Map<string, number>();
  boxDrafts.forEach((b, idx) => {
    if (!firstBoxIndexByEmployee.has(b.employeeKey)) {
      firstBoxIndexByEmployee.set(b.employeeKey, idx);
    }
  });

  const employeeDetails: MealLabelGroupDto[] = [];
  let seq = 0;
  boxDrafts.forEach((box, idx) => {
    seq++;
    const isFirst = firstBoxIndexByEmployee.get(box.employeeKey) === idx;
    const extras = isFirst
      ? (extrasByEmployee.get(box.employeeKey) ?? new Map())
      : new Map<string, number>();
    employeeDetails.push(
      boxToDto(
        box,
        String(seq).padStart(3, '0'),
        extras,
        isFirst && extras.size > 0,
      ),
    );
  });

  const collector = resolveCollector(orders);
  const totalPortions = employeeDetails.reduce(
    (s, e) =>
      s +
      e.packages.reduce((a, p) => a + p.quantity, 0) +
      e.meats.reduce((a, m) => a + m.quantity, 0) +
      e.vegetables.reduce((a, v) => a + v.quantity, 0) +
      e.extras.reduce((a, x) => a + x.quantity, 0),
    0,
  );

  let phase = 'empty';
  if (employeeDetails.length > 0) {
    if (pendingCount > 0 && completedCount === 0) phase = 'pending';
    else if (pendingCount > 0) phase = 'preparing';
    else phase = 'completed';
  }

  const dishSummary = [...dishTotals.entries()]
    .map(([dishName, v]) => ({
      dishName,
      quantity: v.qty,
      subtotal: Number(v.subtotal.toFixed(2)),
    }))
    .sort((a, b) => b.quantity - a.quantity);

  return {
    date,
    mealType,
    mealLabel: MEAL_TYPE_LABEL[mealType],
    merchantId,
    merchantName,
    companyId,
    totalPeople: people.size,
    totalPortions,
    totalAmount: Number(totalAmount.toFixed(2)),
    pendingCount,
    completedCount,
    phase,
    collectorName: collector.name,
    collectorPhone: collector.phone,
    collectorAddress: collector.address,
    dishSummary,
    employeeDetails,
    labelGroups: employeeDetails,
    batchStatus: getBatchStatus(date, mealType, merchantId),
  };
}

function getBatchStatus(
  date: string,
  mealType: MealType,
  merchantId: string,
): 'pending' | 'confirmed' {
  const row = getDb()
    .prepare(
      `SELECT status FROM meal_batch_confirmations
       WHERE batch_date = ? AND meal_type = ? AND merchant_id = ?`,
    )
    .get(date, mealType, merchantId) as { status: string } | undefined;
  return row?.status === 'confirmed' ? 'confirmed' : 'pending';
}

function confirmBatch(
  user: UserRow,
  date: string,
  mealType: MealType,
  merchantId: string,
): void {
  assertMerchantAccess(user, merchantId);
  const now = nowIso();
  getDb()
    .prepare(
      `INSERT INTO meal_batch_confirmations
         (id, batch_date, meal_type, merchant_id, status, confirmed_by, confirmed_at)
       VALUES (?, ?, ?, ?, 'confirmed', ?, ?)
       ON CONFLICT(batch_date, meal_type, merchant_id)
       DO UPDATE SET status = 'confirmed', confirmed_by = excluded.confirmed_by, confirmed_at = excluded.confirmed_at`,
    )
    .run(`mbc_${nanoid(8)}`, date, mealType, merchantId, user.id, now);
}

export class MealSummaryService {
  buildSummary(
    user: UserRow,
    opts: {
      date: string;
      mealType: MealType;
      merchantId: string;
      companyId?: string;
      status?: string;
    },
  ): MealSummaryDto {
    const db = getDb();
    const merchant = db
      .prepare<
        [string],
        { id: string; name: string; company_id: string | null }
      >('SELECT id, name, company_id FROM merchants WHERE id = ?')
      .get(opts.merchantId);
    if (!merchant) throw new Error('MERCHANT_NOT_FOUND');

    const orders = fetchOrdersForBatch(user, opts);
    return buildBatch(
      orders,
      opts.date,
      opts.mealType,
      merchant.id,
      merchant.name,
      merchant.company_id,
    );
  }

  confirmSummary(
    user: UserRow,
    opts: { date: string; mealType: MealType; merchantId: string },
  ): MealSummaryDto {
    confirmBatch(user, opts.date, opts.mealType, opts.merchantId);
    return this.buildSummary(user, opts);
  }

  listLabels(
    user: UserRow,
    opts: {
      date: string;
      mealType: MealType;
      merchantId: string;
      companyId?: string;
    },
  ): MealLabelGroupDto[] {
    const summary = this.buildSummary(user, opts);
    return summary.labelGroups;
  }

  dashboardStats(user: UserRow, date: string): DashboardStatsDto {
    const db = getDb();
    const { clause, params } = companyFilterSql(user, 'o.company_id');
    const merchants = db
      .prepare(
        `SELECT id FROM merchants WHERE onboarding_status = 'approved' AND is_enabled = 1`,
      )
      .all() as { id: string }[];

    const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'overtime'];
    const mealStats = Object.fromEntries(
      mealTypes.map((t) => [t, { people: 0, portions: 0, amount: 0 }]),
    ) as DashboardStatsDto['mealStats'];

    let orderPeople = 0;
    let orderPortions = 0;
    let orderAmount = 0;
    let pendingBatches = 0;
    let completedBatches = 0;
    let collectorName = '—';

    for (const m of merchants) {
      for (const mealType of mealTypes) {
        const batch = this.buildSummary(user, {
          date,
          mealType,
          merchantId: m.id,
        });
        if (batch.totalPeople === 0) continue;
        mealStats[mealType].people += batch.totalPeople;
        mealStats[mealType].portions += batch.totalPortions;
        mealStats[mealType].amount += batch.totalAmount;
        orderPeople += batch.totalPeople;
        orderPortions += batch.totalPortions;
        orderAmount += batch.totalAmount;
        if (batch.pendingCount > 0) pendingBatches++;
        if (batch.completedCount > 0 && batch.pendingCount === 0) {
          completedBatches++;
        }
        if (batch.collectorName !== '—') collectorName = batch.collectorName;
      }
    }

    const orders = db
      .prepare(
        `SELECT COUNT(DISTINCT o.user_id) AS c FROM orders o
         WHERE ${clause} AND date(o.created_at) = date(?) AND o.status != 'cancelled'`,
      )
      .get(...params, date) as { c: number };

    return {
      date,
      orderPeople: Math.max(orderPeople, orders?.c ?? 0),
      orderPortions,
      orderAmount: Number(orderAmount.toFixed(2)),
      pendingBatches,
      completedBatches,
      collectorName,
      mealStats,
    };
  }
}

export const mealSummaryService = new MealSummaryService();

/** 标签 HTML 行格式化（供 admin-export 与 API 共用） */
export function formatLabelGroupLines(g: MealLabelGroupDto): string[] {
  const lines: string[] = [];
  lines.push(`${g.employeeName}｜${g.department}`);
  if (g.packages.length > 0) {
    lines.push(
      `套餐：${g.packages.map((p) => `${p.name} x${p.quantity}`).join('、')}`,
    );
  }
  if (g.meats.length > 0) {
    lines.push(
      `荤菜：${g.meats.map((m) => `${m.name} x${m.quantity}`).join('、')}`,
    );
  }
  if (g.vegetables.length > 0) {
    lines.push(
      `素菜：${g.vegetables.map((v) => `${v.name} x${v.quantity}`).join('、')}`,
    );
  }
  if (g.extras.length > 0) {
    const suffix = g.extrasFollowOrder ? '（随单）' : '';
    lines.push(
      `加菜：${g.extras.map((e) => `${e.name} x${e.quantity}`).join('、')}${suffix}`,
    );
  }
  return lines;
}
