/**
 * seed_commercial.ts — 商用环境初始化
 * 用法：npm run seed:commercial
 */
import { getDb } from '../db/database';
import { seedCommercialDefaults } from '../db/migrate_db';

function main() {
  console.log('[seed:commercial] 初始化商用默认数据...');
  const db = getDb();
  seedCommercialDefaults(db);
  console.log('[seed:commercial] 平台管理员手机号:', process.env.PLATFORM_ADMIN_PHONE || '13700000000');
  console.log('[seed:commercial] 默认企业: comp_default');
  console.log('[seed:commercial] 完成');
}

main();
