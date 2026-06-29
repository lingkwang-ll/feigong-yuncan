/**
 * backup_db.ts
 *
 * 把当前 SQLite 数据库复制到 server/backups/，
 * 文件名格式：feigong-yuncan-YYYYMMDD-HHmmss.db
 *
 * 用法：
 *   npm run backup:db
 *
 * 推荐做法：上线 / 大改 / 试运行结束前各做一次。
 * 复制使用 better-sqlite3 的 .backup() API，
 * 因此即使服务在跑也可以安全备份（不会中断写入）。
 */
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { closeDb, getDb } from '../db/database';

function pad(n: number) {
  return n.toString().padStart(2, '0');
}

function timestamp(d = new Date()) {
  return (
    d.getFullYear().toString() +
    pad(d.getMonth() + 1) +
    pad(d.getDate()) +
    '-' +
    pad(d.getHours()) +
    pad(d.getMinutes()) +
    pad(d.getSeconds())
  );
}

async function main() {
  const dbPath = path.resolve(
    process.cwd(),
    process.env.DATABASE_PATH ||
      process.env.DATABASE_FILE ||
      './data/feigong-yuncan.db',
  );
  if (!fs.existsSync(dbPath)) {
    console.error(`[backup_db] database not found: ${dbPath}`);
    process.exit(1);
  }

  const backupDir = path.resolve(process.cwd(), './backups');
  if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true });

  const target = path.join(backupDir, `feigong-yuncan-${timestamp()}.db`);

  const db = getDb();
  await db.backup(target);

  const size = fs.statSync(target).size;
  console.log('[backup_db] ok ✅');
  console.log(`  source : ${dbPath}`);
  console.log(`  target : ${target}`);
  console.log(`  size   : ${(size / 1024).toFixed(2)} KB`);
}

main()
  .catch((e) => {
    console.error('[backup_db] failed:', e);
    process.exit(1);
  })
  .finally(() => closeDb());
