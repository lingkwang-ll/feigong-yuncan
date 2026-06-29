/**
 * prepare_trial_data.ts
 *
 * 试运行前一键整理数据：
 * - 清空 orders / order_items（及 reviews 表若存在）
 * - 保留其他 users / merchants / dishes（非绿健食堂）
 * - 确保试运行账号、绿健食堂、试运行菜品存在
 * - 不写入任何演示/测试订单
 *
 * 用法：npm run prepare:trial
 */
import 'dotenv/config';
import { closeDb, getDb } from '../db/database';
import {
  TRIAL_EMPLOYEES,
  TRIAL_MERCHANT_NAME,
  TRIAL_MERCHANT_PHONE,
  buildTrialDishes,
  clearOrderData,
  clearReviewsIfExists,
  ensureTrialDishes,
  ensureTrialMerchant,
  upsertTrialUsers,
} from './trial_data_shared';

function main() {
  const db = getDb();

  console.log('[prepare:trial] 开始整理试运行数据...');

  const cleared = clearOrderData(db);
  console.log(
    `[prepare:trial] 已清空订单: orders ${cleared.orders} 条, order_items ${cleared.items} 条`,
  );

  const reviewCount = clearReviewsIfExists(db);
  if (reviewCount > 0) {
    console.log(`[prepare:trial] 已清空 reviews: ${reviewCount} 条`);
  } else {
    console.log('[prepare:trial] reviews 表不存在（评价仅存客户端时可忽略）');
  }

  upsertTrialUsers(db);
  console.log('[prepare:trial] 试运行账号已就绪:');
  for (const e of TRIAL_EMPLOYEES) {
    console.log(`  员工 ${e.phone} ${e.name} ${e.department}`);
  }
  console.log(`  商家 ${TRIAL_MERCHANT_PHONE} ${TRIAL_MERCHANT_NAME}`);

  ensureTrialMerchant(db);
  const dishCount = ensureTrialDishes(db);
  console.log(
    `[prepare:trial] 绿健食堂试运行菜品 ${dishCount} 道（${buildTrialDishes().map((d) => d.name).slice(0, 3).join('、')}…）`,
  );

  const remainOrders = db
    .prepare('SELECT COUNT(1) AS c FROM orders')
    .get() as { c: number };
  console.log(`[prepare:trial] 当前订单数: ${remainOrders.c}（应为 0）`);
  console.log('[prepare:trial] 完成，可开始真实试运行订餐');
}

try {
  main();
} catch (e) {
  console.error('[prepare:trial] failed:', e);
  process.exit(1);
} finally {
  closeDb();
}
