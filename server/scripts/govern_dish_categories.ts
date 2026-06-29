/**
 * E2E 测试菜品 category 治理（不删库、不清数据）
 *
 * 仅处理绿健食堂 (m_self) 下 ChatTestDish / LegacyDish 且 category 为空的记录：
 *   category = vegetable, is_available = 0
 *
 * 默认 dry-run；加 --apply 才写入。
 *
 * Usage:
 *   cd server
 *   npx ts-node --transpile-only scripts/govern_dish_categories.ts
 *   npx ts-node --transpile-only scripts/govern_dish_categories.ts --apply
 */
import Database from 'better-sqlite3';
import path from 'path';

const MERCHANT_ID = 'm_self';
const TEST_DISH_NAMES = ['ChatTestDish', 'LegacyDish'] as const;
const TARGET_CATEGORY = 'vegetable';

const apply = process.argv.includes('--apply');

interface DishRow {
  id: string;
  merchant_id: string;
  merchant_name: string;
  name: string;
  category: string | null;
  is_available: number;
}

function main(): void {
  const dbPath = path.resolve(process.cwd(), 'data', 'feigong-yuncan.db');
  const db = new Database(dbPath);

  const placeholders = TEST_DISH_NAMES.map(() => '?').join(', ');
  const rows = db
    .prepare(
      `SELECT d.id, d.merchant_id, COALESCE(m.name, d.merchant_id) as merchant_name,
              d.name, d.category, d.is_available
       FROM dishes d
       LEFT JOIN merchants m ON m.id = d.merchant_id
       WHERE d.merchant_id = ?
         AND d.name IN (${placeholders})
         AND (d.category IS NULL OR trim(d.category) = '')
       ORDER BY d.name, d.id`,
    )
    .all(MERCHANT_ID, ...TEST_DISH_NAMES) as DishRow[];

  console.log(
    `=== govern_dish_categories ${apply ? '(APPLY)' : '(dry-run)'} ===`,
  );
  console.log(`目标商家：${MERCHANT_ID}（绿健食堂）`);
  console.log(`目标菜名：${TEST_DISH_NAMES.join(' / ')}`);
  console.log(`待处理：${rows.length} 道\n`);

  if (rows.length === 0) {
    console.log('无待处理记录，退出。');
    db.close();
    return;
  }

  for (const row of rows) {
    const cat = (row.category ?? '').trim() || '<空>';
    const avail = row.is_available ? '上架' : '下架';
    console.log(
      `  [${row.id}] ${row.name}: category ${cat} → ${TARGET_CATEGORY}, is_available ${avail} → 下架`,
    );
  }

  if (!apply) {
    console.log('\n以上为 dry-run，未写入数据库。');
    console.log('确认后执行：npx ts-node --transpile-only scripts/govern_dish_categories.ts --apply');
    db.close();
    return;
  }

  const update = db.prepare(
    `UPDATE dishes
     SET category = ?, is_available = 0, updated_at = datetime('now')
     WHERE id = ?`,
  );

  const tx = db.transaction(() => {
    for (const row of rows) {
      update.run(TARGET_CATEGORY, row.id);
    }
  });
  tx();

  console.log(`\n已写入：${rows.length} 道（category=${TARGET_CATEGORY}, is_available=0）`);
  db.close();
}

main();
