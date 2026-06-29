/**
 * seed_package_demo.ts
 *
 * 为「验收测试店」重建标准套餐点餐演示数据。
 * - 仅处理该商家，不影响其它商家
 * - 旧菜品标记不可用，旧套餐标记未启用
 * - 写入标准 category + mealTypes 的荤/素/加菜与 3 个套餐
 *
 * 用法：npm run seed:package-demo
 */
import 'dotenv/config';
import { nanoid } from 'nanoid';
import { closeDb, getDb } from '../src/db/database';
import { nowIso } from '../src/models/mappers';
import { MealType } from '../src/models/types';

const DEMO_MERCHANT_NAME = '验收测试店';
const MEAL_TYPES: MealType[] = ['lunch', 'overtime'];

interface DishSeed {
  id: string;
  name: string;
  category: 'meat' | 'vegetable' | 'extra';
  extraPrice?: number;
}

const DISHES: DishSeed[] = [
  { id: 'd_pkgdemo_meat_beef', name: '牛肉', category: 'meat' },
  { id: 'd_pkgdemo_meat_egg', name: '炒鸡蛋', category: 'meat' },
  { id: 'd_pkgdemo_meat_pork', name: '红烧肉', category: 'meat' },
  { id: 'd_pkgdemo_veg_greens', name: '青菜', category: 'vegetable' },
  { id: 'd_pkgdemo_veg_potato', name: '土豆丝', category: 'vegetable' },
  { id: 'd_pkgdemo_veg_leek', name: '韭黄', category: 'vegetable' },
  { id: 'd_pkgdemo_extra_chicken', name: '鸡腿', category: 'extra', extraPrice: 6 },
  { id: 'd_pkgdemo_extra_drink', name: '饮料', category: 'extra', extraPrice: 3 },
  { id: 'd_pkgdemo_extra_egg', name: '加蛋', category: 'extra', extraPrice: 2 },
];

interface PackageSeed {
  id: string;
  name: string;
  basePrice: number;
  meat: number;
  vegetable: number;
}

const PACKAGES: PackageSeed[] = [
  { id: 'pkg_pkgdemo_1m2v', name: '一荤两素', basePrice: 10, meat: 1, vegetable: 2 },
  { id: 'pkg_pkgdemo_2m2v', name: '两荤两素', basePrice: 16, meat: 2, vegetable: 2 },
  { id: 'pkg_pkgdemo_2m3v', name: '两荤三素', basePrice: 18, meat: 2, vegetable: 3 },
];

function main() {
  const db = getDb();
  const merchant = db
    .prepare<[string], { id: string; name: string }>(
      'SELECT id, name FROM merchants WHERE name = ?',
    )
    .get(DEMO_MERCHANT_NAME);

  if (!merchant) {
    console.error(
      `[seed:package-demo] 未找到商家「${DEMO_MERCHANT_NAME}」，请先在管理端创建该商家`,
    );
    process.exit(1);
  }

  const merchantId = merchant.id;
  const now = nowIso();
  const mealTypesJson = JSON.stringify(MEAL_TYPES);

  console.log(`[seed:package-demo] 商家 ${merchant.name} (${merchantId})`);

  const disabledDishes = db
    .prepare(
      `UPDATE dishes SET is_available = 0, updated_at = ?
       WHERE merchant_id = ? AND id NOT LIKE 'd_pkgdemo_%'`,
    )
    .run(now, merchantId).changes;
  console.log(`[seed:package-demo] 已标记 ${disabledDishes} 道旧菜品不可用`);

  const disabledPkgs = db
    .prepare(
      `UPDATE packages SET is_enabled = 0, updated_at = ?
       WHERE merchant_id = ? AND id NOT LIKE 'pkg_pkgdemo_%'`,
    )
    .run(now, merchantId).changes;
  console.log(`[seed:package-demo] 已标记 ${disabledPkgs} 个旧套餐未启用`);

  const insertDish = db.prepare(
    `INSERT INTO dishes
       (id, merchant_id, name, image_url, description, price, meal_type,
        tags_json, is_available, is_sold_out, sort_order,
        category, extra_price, meal_types_json, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       merchant_id = excluded.merchant_id,
       name = excluded.name,
       category = excluded.category,
       extra_price = excluded.extra_price,
       meal_types_json = excluded.meal_types_json,
       meal_type = excluded.meal_type,
       is_available = 1,
       is_sold_out = 0,
       updated_at = excluded.updated_at`,
  );

  for (let i = 0; i < DISHES.length; i++) {
    const d = DISHES[i];
    const extraPrice = d.category === 'extra' ? d.extraPrice ?? 0 : 0;
    insertDish.run(
      d.id,
      merchantId,
      d.name,
      'dish',
      '',
      0,
      'lunch',
      '[]',
      i,
      d.category,
      extraPrice,
      mealTypesJson,
      now,
      now,
    );
  }
  console.log(`[seed:package-demo] 菜品 ${DISHES.length} 道已就绪`);

  const insertPkg = db.prepare(
    `INSERT INTO packages
       (id, merchant_id, name, description, base_price, meal_types_json,
        rules_json, allow_extra, extra_dish_ids_json, is_enabled, created_at, updated_at)
     VALUES (?, ?, ?, '', ?, ?, ?, 1, '[]', 1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       merchant_id = excluded.merchant_id,
       name = excluded.name,
       base_price = excluded.base_price,
       meal_types_json = excluded.meal_types_json,
       rules_json = excluded.rules_json,
       is_enabled = 1,
       updated_at = excluded.updated_at`,
  );

  for (const p of PACKAGES) {
    const rulesJson = JSON.stringify({ meat: p.meat, vegetable: p.vegetable });
    insertPkg.run(
      p.id,
      merchantId,
      p.name,
      p.basePrice,
      mealTypesJson,
      rulesJson,
      now,
      now,
    );
  }
  console.log(`[seed:package-demo] 套餐 ${PACKAGES.length} 个已就绪`);
  console.log('[seed:package-demo] 完成。可执行 check_package_order_data.ps1 验收');
}

try {
  main();
} catch (e) {
  console.error('[seed:package-demo] failed:', e);
  process.exit(1);
} finally {
  closeDb();
}
