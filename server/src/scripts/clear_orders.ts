/**
 * clear_orders.ts
 *
 * 仅清空 orders 与 order_items 两张表，保留用户、商家、菜品。
 *
 * 用法：
 *   npm run clear:orders
 *
 * 适用场景：试运行期间想保留账号 / 商家 / 菜品配置，
 * 但希望把脏测试单据全部清掉重新开始。
 */
import 'dotenv/config';
import { closeDb, getDb } from '../db/database';

function main() {
  const db = getDb();
  const before = {
    orders: db.prepare('SELECT COUNT(1) AS c FROM orders').get() as { c: number },
    items: db.prepare('SELECT COUNT(1) AS c FROM order_items').get() as { c: number },
  };
  db.exec(`
    DELETE FROM order_items;
    DELETE FROM orders;
    DELETE FROM sqlite_sequence WHERE name = 'order_items';
  `);
  const after = {
    orders: db.prepare('SELECT COUNT(1) AS c FROM orders').get() as { c: number },
    items: db.prepare('SELECT COUNT(1) AS c FROM order_items').get() as { c: number },
  };
  console.log('[clear_orders] cleared:');
  console.log(`  orders     : ${before.orders.c}  ->  ${after.orders.c}`);
  console.log(`  order_items: ${before.items.c}  ->  ${after.items.c}`);
}

try {
  main();
  console.log('[clear_orders] done ✅');
} catch (e) {
  console.error('[clear_orders] failed:', e);
  process.exit(1);
} finally {
  closeDb();
}
