/**
 * reset_db.ts
 *
 * 重置 SQLite 数据库：
 * 1. 关闭并删除当前数据库文件（含 -wal/-shm）
 * 2. 重新打开（自动执行 schema.sql 建表）
 * 3. 可选：再次跑 seed 写入演示数据
 *
 * 用法：
 *   npm run reset:db          # 只重建表，不写 seed
 *   npm run reset:db -- --seed   # 重建表 + 写入 seed
 *
 * 注意：执行前请先停掉正在运行的 dev / start 服务，
 *      否则 better-sqlite3 / WAL 文件占用会导致删除失败。
 */
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { closeDb, getDb } from '../db/database';

function resolveDbPath(): string {
  const rel =
    process.env.DATABASE_PATH ||
    process.env.DATABASE_FILE ||
    './data/feigong-yuncan.db';
  return path.resolve(process.cwd(), rel);
}

function tryUnlink(p: string) {
  if (!fs.existsSync(p)) return;
  try {
    fs.unlinkSync(p);
    console.log(`[reset_db] removed: ${p}`);
  } catch (e) {
    console.warn(`[reset_db] cannot remove ${p}: ${(e as Error).message}`);
    console.warn('[reset_db] hint: 请先停止后端服务（npm run dev / start）再执行本脚本');
    throw e;
  }
}

async function main() {
  // 先关掉本进程的连接（如果有）
  closeDb();

  const dbPath = resolveDbPath();
  tryUnlink(dbPath);
  tryUnlink(dbPath + '-wal');
  tryUnlink(dbPath + '-shm');

  // 触发 schema 重建
  getDb();
  console.log(`[reset_db] schema re-created at ${dbPath}`);

  if (process.argv.includes('--seed')) {
    closeDb();
    // 延迟 require，避免在重建前误读旧连接
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    require('../seed/seed');
    return;
  }

  closeDb();
  console.log('[reset_db] done ✅ （未写入 seed，如需 demo 数据请加 --seed）');
}

main().catch((e) => {
  console.error('[reset_db] failed:', e);
  process.exit(1);
});
