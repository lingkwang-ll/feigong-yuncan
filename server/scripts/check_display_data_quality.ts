/**
 * 展示数据质量检查（只读，不修改数据库）
 *
 * Usage:
 *   cd server
 *   npx ts-node --transpile-only scripts/check_display_data_quality.ts
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

import { isCorruptDisplayText } from '../src/utils/display-text.util';

function loadDbPath(): string {
  const envPath = path.join(__dirname, '..', '.env');
  if (fs.existsSync(envPath)) {
    for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
      const m = line.match(/^DATABASE_PATH=(.+)$/);
      if (m) return path.resolve(path.join(__dirname, '..'), m[1].trim());
    }
  }
  return path.join(__dirname, '..', 'data', 'feigong-yuncan.db');
}

interface IssueRow {
  table: string;
  id: string;
  field: string;
  value: string;
  suggestion: string;
}

const issues: IssueRow[] = [];

function report(
  table: string,
  id: string,
  field: string,
  value: string,
  suggestion: string,
) {
  issues.push({ table, id, field, value, suggestion });
}

function main() {
  const dbPath = loadDbPath();
  if (!fs.existsSync(dbPath)) {
    console.error(`[FAIL] database not found: ${dbPath}`);
    process.exit(1);
  }
  const db = new Database(dbPath, { readonly: true });

  console.log('=== check_display_data_quality (read-only) ===');
  console.log(`DB: ${dbPath}`);

  const orders = db
    .prepare('SELECT id, merchant_id, merchant_name FROM orders')
    .all() as { id: string; merchant_id: string; merchant_name: string }[];
  for (const o of orders) {
    if (isCorruptDisplayText(o.merchant_name)) {
      const m = db
        .prepare('SELECT name FROM merchants WHERE id = ?')
        .get(o.merchant_id) as { name: string } | undefined;
      report(
        'orders',
        o.id,
        'merchant_name',
        o.merchant_name,
        m?.name && !isCorruptDisplayText(m.name)
          ? `回填 merchants.name = "${m.name}"`
          : '前端展示「未知商家」；需人工确认商家名',
      );
    }
  }

  const orderItems = db
    .prepare('SELECT order_id, dish_id, dish_name FROM order_items')
    .all() as { order_id: string; dish_id: string | null; dish_name: string }[];
  for (const row of orderItems) {
    if (!isCorruptDisplayText(row.dish_name)) continue;
    let suggestion = '前端展示「菜品信息缺失」';
    if (row.dish_id) {
      const d = db
        .prepare('SELECT name FROM dishes WHERE id = ?')
        .get(row.dish_id) as { name: string } | undefined;
      if (d?.name && !isCorruptDisplayText(d.name)) {
        suggestion = `回填 dishes.name = "${d.name}"`;
      }
    }
    report('order_items', row.order_id, 'dish_name', row.dish_name, suggestion);
  }

  const dishes = db
    .prepare('SELECT id, name FROM dishes')
    .all() as { id: string; name: string }[];
  for (const d of dishes) {
    if (isCorruptDisplayText(d.name)) {
      report('dishes', d.id, 'name', d.name, '需人工修正菜品名或重新录入');
    }
  }

  const merchants = db
    .prepare('SELECT id, name FROM merchants')
    .all() as { id: string; name: string }[];
  for (const m of merchants) {
    if (isCorruptDisplayText(m.name)) {
      report('merchants', m.id, 'name', m.name, '需人工修正商家名或重新入驻');
    }
  }

  const users = db
    .prepare('SELECT id, name FROM users')
    .all() as { id: string; name: string }[];
  for (const u of users) {
    if (isCorruptDisplayText(u.name)) {
      report('users', u.id, 'name', u.name, '需人工修正用户姓名');
    }
  }

  const profiles = db
    .prepare('SELECT id, employee_name FROM employee_profiles')
    .all() as { id: string; employee_name: string }[];
  for (const p of profiles) {
    if (isCorruptDisplayText(p.employee_name)) {
      report(
        'employee_profiles',
        p.id,
        'employee_name',
        p.employee_name,
        '需人工修正员工档案姓名',
      );
    }
  }

  if (issues.length === 0) {
    console.log('[OK] no corrupt display names found');
    process.exit(0);
  }

  console.log(`\nFound ${issues.length} issue(s):\n`);
  const byTable = new Map<string, IssueRow[]>();
  for (const i of issues) {
    const list = byTable.get(i.table) ?? [];
    list.push(i);
    byTable.set(i.table, list);
  }
  for (const [table, rows] of byTable) {
    console.log(`--- ${table} (${rows.length}) ---`);
    for (const r of rows.slice(0, 50)) {
      console.log(
        `  id=${r.id}  ${r.field}="${r.value}"  -> ${r.suggestion}`,
      );
    }
    if (rows.length > 50) {
      console.log(`  ... and ${rows.length - 50} more`);
    }
  }
  process.exit(issues.length > 0 ? 0 : 0);
}

main();
