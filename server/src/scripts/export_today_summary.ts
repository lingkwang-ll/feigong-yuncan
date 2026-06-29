/**
 * export_today_summary.ts
 *
 * 按日期 + 餐段导出企业订餐汇总（JSON / CSV）。
 *
 * 用法：
 *   npm run export:today
 *   npm run export:today -- --date=2026-06-12 --meal=lunch --format=both
 *
 * 输出目录：server/exports/
 */
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { closeDb, getDb } from '../db/database';
import { MealType, OrderItemRow, OrderRow } from '../models/types';
import {
  MEAL_TYPE_LABEL,
  TRIAL_MERCHANT_ID,
  TRIAL_MERCHANT_NAME,
  currentMealPeriod,
  formatDateLocal,
  parseCliArgs,
} from './trial_data_shared';

interface DishTotal {
  dishName: string;
  quantity: number;
}

interface EmployeeLine {
  labelCode: string;
  employeeName: string;
  department: string;
  addressShort: string;
  dishName: string;
  quantity: number;
  remark: string;
}

interface ExportPayload {
  date: string;
  mealType: MealType;
  mealLabel: string;
  merchantId: string;
  merchantName: string;
  totalPeople: number;
  totalPortions: number;
  totalAmount: number;
  dishSummary: DishTotal[];
  employeeLines: EmployeeLine[];
}

function addressShort(raw: string | null): string {
  if (!raw) return '—';
  const line = raw.split('\n')[0]?.trim() ?? '';
  return line.replace(/ · /g, '').replace(/\s+/g, '') || '—';
}

function departmentOf(order: OrderRow): string {
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

function buildSummary(
  dateStr: string,
  mealType: MealType,
  merchantId: string,
): ExportPayload {
  const db = getDb();

  const merchant = db
    .prepare('SELECT id, name FROM merchants WHERE id = ?')
    .get(merchantId) as { id: string; name: string } | undefined;

  const orders = db
    .prepare(
      `SELECT * FROM orders
       WHERE merchant_id = ?
         AND status != 'cancelled'
         AND date(created_at) = date(?)
       ORDER BY created_at ASC`,
    )
    .all(merchantId, dateStr) as OrderRow[];

  const getItems = db.prepare<[string], OrderItemRow>(
    'SELECT * FROM order_items WHERE order_id = ? ORDER BY id ASC',
  );

  const dishMap = new Map<string, number>();
  const lines: EmployeeLine[] = [];
  let labelSeq = 0;
  let totalAmount = 0;
  const people = new Set<string>();

  for (const order of orders) {
    const items = getItems.all(order.id);
    const hasMeal = items.some((it) => it.meal_type === mealType);
    if (!hasMeal) continue;

    people.add(order.user_name ?? order.id);
    totalAmount += order.total_amount;

    const dept = departmentOf(order);
    const addr = addressShort(order.address);
    const name = order.user_name ?? '员工';
    const remark = order.remark ?? '';

    for (const it of items) {
      if (it.meal_type !== mealType) continue;
      labelSeq++;
      lines.push({
        labelCode: String(labelSeq).padStart(3, '0'),
        employeeName: name,
        department: dept,
        addressShort: addr,
        dishName: it.dish_name,
        quantity: it.quantity,
        remark,
      });
      dishMap.set(
        it.dish_name,
        (dishMap.get(it.dish_name) ?? 0) + it.quantity,
      );
    }
  }

  const dishSummary = [...dishMap.entries()]
    .map(([dishName, quantity]) => ({ dishName, quantity }))
    .sort((a, b) => b.quantity - a.quantity);

  const totalPortions = lines.reduce((s, l) => s + l.quantity, 0);

  return {
    date: dateStr,
    mealType,
    mealLabel: MEAL_TYPE_LABEL[mealType],
    merchantId,
    merchantName: merchant?.name ?? TRIAL_MERCHANT_NAME,
    totalPeople: people.size,
    totalPortions,
    totalAmount: Number(totalAmount.toFixed(2)),
    dishSummary,
    employeeLines: lines,
  };
}

function toCsv(payload: ExportPayload): string {
  const rows: string[] = [];
  rows.push('section,key,value');
  rows.push(`summary,date,${payload.date}`);
  rows.push(`summary,meal,${payload.mealLabel}`);
  rows.push(`summary,merchant,${payload.merchantName}`);
  rows.push(`summary,totalPeople,${payload.totalPeople}`);
  rows.push(`summary,totalPortions,${payload.totalPortions}`);
  rows.push(`summary,totalAmount,${payload.totalAmount}`);
  rows.push('');
  rows.push('dishSummary,dishName,quantity');
  for (const d of payload.dishSummary) {
    rows.push(`dish,${escapeCsv(d.dishName)},${d.quantity}`);
  }
  rows.push('');
  rows.push(
    'employeeLine,labelCode,employeeName,department,addressShort,dishName,quantity,remark',
  );
  for (const l of payload.employeeLines) {
    rows.push(
      [
        'line',
        l.labelCode,
        escapeCsv(l.employeeName),
        escapeCsv(l.department),
        escapeCsv(l.addressShort),
        escapeCsv(l.dishName),
        l.quantity,
        escapeCsv(l.remark),
      ].join(','),
    );
  }
  return rows.join('\n');
}

function escapeCsv(v: string): string {
  if (v.includes(',') || v.includes('"') || v.includes('\n')) {
    return `"${v.replace(/"/g, '""')}"`;
  }
  return v;
}

function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const now = new Date();
  const dateStr = args.date ?? formatDateLocal(now);
  const mealType = (args.meal as MealType | undefined) ?? currentMealPeriod(now);
  const merchantId = args.merchant ?? TRIAL_MERCHANT_ID;
  const format = args.format ?? 'both';

  if (!['breakfast', 'lunch', 'dinner', 'overtime'].includes(mealType)) {
    throw new Error(`无效餐段: ${mealType}`);
  }

  const payload = buildSummary(dateStr, mealType, merchantId);

  const outDir = path.resolve(process.cwd(), 'exports');
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

  const base = `trial-summary-${dateStr}-${mealType}`;

  if (format === 'json' || format === 'both') {
    const jsonPath = path.join(outDir, `${base}.json`);
    fs.writeFileSync(jsonPath, JSON.stringify(payload, null, 2), 'utf-8');
    console.log(`[export:today] JSON → ${jsonPath}`);
  }

  if (format === 'csv' || format === 'both') {
    const csvPath = path.join(outDir, `${base}.csv`);
    fs.writeFileSync(csvPath, toCsv(payload), 'utf-8');
    console.log(`[export:today] CSV  → ${csvPath}`);
  }

  console.log('[export:today] 汇总:');
  console.log(`  日期 ${payload.date}  餐段 ${payload.mealLabel}  商家 ${payload.merchantName}`);
  console.log(
    `  人数 ${payload.totalPeople}  份数 ${payload.totalPortions}  金额 ¥${payload.totalAmount}`,
  );
  console.log(`  菜品 ${payload.dishSummary.length} 种  明细 ${payload.employeeLines.length} 条`);
}

try {
  main();
} catch (e) {
  console.error('[export:today] failed:', e);
  process.exit(1);
} finally {
  closeDb();
}
