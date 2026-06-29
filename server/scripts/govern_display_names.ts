/**
 * 展示名称治理：安全回填 orders.merchant_name / order_items.dish_name
 *
 * 默认 dry-run；加 --apply 才写入。
 *
 * Usage:
 *   npx ts-node --transpile-only scripts/govern_display_names.ts
 *   npx ts-node --transpile-only scripts/govern_display_names.ts --apply
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

import {
  isCorruptDisplayText,
  resolveDishDisplayName,
  resolveMerchantDisplayName,
} from '../src/utils/display-text.util';

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

const apply = process.argv.includes('--apply');

function main() {
  const dbPath = loadDbPath();
  const db = new Database(dbPath);
  console.log(`=== govern_display_names ${apply ? '(APPLY)' : '(dry-run)'} ===`);

  let orderUpdates = 0;
  let itemUpdates = 0;

  const orders = db
    .prepare('SELECT id, merchant_id, merchant_name FROM orders')
    .all() as { id: string; merchant_id: string; merchant_name: string }[];

  const updateOrder = db.prepare(
    'UPDATE orders SET merchant_name = ? WHERE id = ?',
  );
  const updateItem = db.prepare(
    'UPDATE order_items SET dish_name = ? WHERE order_id = ? AND dish_name = ?',
  );

  for (const o of orders) {
    if (!isCorruptDisplayText(o.merchant_name)) continue;
    const m = db
      .prepare('SELECT name FROM merchants WHERE id = ?')
      .get(o.merchant_id) as { name: string } | undefined;
    const next = resolveMerchantDisplayName(o.merchant_name, m?.name);
    if (next === o.merchant_name || next === '未知商家') continue;
    console.log(`order ${o.id}: merchant_name "${o.merchant_name}" -> "${next}"`);
    orderUpdates++;
    if (apply) updateOrder.run(next, o.id);
  }

  const items = db
    .prepare('SELECT order_id, dish_id, dish_name FROM order_items')
    .all() as { order_id: string; dish_id: string | null; dish_name: string }[];

  for (const row of items) {
    if (!isCorruptDisplayText(row.dish_name)) continue;
    let fromDb: string | undefined;
    if (row.dish_id) {
      const d = db
        .prepare('SELECT name FROM dishes WHERE id = ?')
        .get(row.dish_id) as { name: string } | undefined;
      fromDb = d?.name;
    }
    const next = resolveDishDisplayName(row.dish_name, fromDb);
    if (next === row.dish_name || next === '菜品信息缺失') continue;
    console.log(
      `order_item ${row.order_id}: dish_name "${row.dish_name}" -> "${next}"`,
    );
    itemUpdates++;
    if (apply) updateItem.run(next, row.order_id, row.dish_name);
  }

  console.log(
    `\nSummary: orders=${orderUpdates}, order_items=${itemUpdates}` +
      (apply ? ' (applied)' : ' (dry-run only)'),
  );
}

main();
