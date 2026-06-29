/**
 * seed_trial_users.ts
 *
 * 写入 / 更新试运行员工与商家白名单（不清订单、不改菜品）。
 *
 * 用法：npm run seed:trial-users
 */
import 'dotenv/config';
import { closeDb, getDb } from '../db/database';
import {
  TRIAL_EMPLOYEES,
  TRIAL_MERCHANT_NAME,
  TRIAL_MERCHANT_PHONE,
  ensureTrialMerchant,
  upsertTrialUsers,
} from './trial_data_shared';

function main() {
  const db = getDb();
  console.log('[seed:trial-users] 写入试运行账号白名单...');

  upsertTrialUsers(db);
  ensureTrialMerchant(db);

  console.log('[seed:trial-users] 员工:');
  for (const e of TRIAL_EMPLOYEES) {
    console.log(`  ${e.phone}  ${e.name}  ${e.department}`);
  }
  console.log(`[seed:trial-users] 商家: ${TRIAL_MERCHANT_PHONE}  ${TRIAL_MERCHANT_NAME}`);
  console.log('[seed:trial-users] 完成');
}

try {
  main();
} catch (e) {
  console.error('[seed:trial-users] failed:', e);
  process.exit(1);
} finally {
  closeDb();
}
