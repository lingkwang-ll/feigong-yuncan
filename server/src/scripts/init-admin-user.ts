/**
 * 生产环境初始化平台管理员账号（幂等）
 *
 * 用法：
 *   cd server
 *   npm run build && npm run init:admin
 *
 * 环境变量（读取 server/.env）：
 *   DATABASE_PATH / DB_PATH / DATABASE_FILE
 *   PLATFORM_ADMIN_PHONE（默认 13700000000）
 *   INIT_ADMIN_PASSWORD（默认 123456）
 */
import 'dotenv/config';
import { nanoid } from 'nanoid';
import { closeDb, getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { UserRow } from '../models/types';
import { hashPassword, verifyPassword } from '../utils/password.util';
import { isValidPhone, normalizePhone } from '../utils/phone.util';

function resolveDbPath(): string {
  return (
    process.env.DATABASE_PATH ||
    process.env.DB_PATH ||
    process.env.DATABASE_FILE ||
    './data/feigong-yuncan.db'
  );
}

function main(): void {
  const dbPath = resolveDbPath();
  const phoneRaw = process.env.PLATFORM_ADMIN_PHONE || '13700000000';
  const password = process.env.INIT_ADMIN_PASSWORD || '123456';
  const phone = normalizePhone(phoneRaw);

  if (!isValidPhone(phone)) {
    console.error('[init-admin] 无效手机号:', phoneRaw);
    process.exit(1);
  }

  console.log('[init-admin] 数据库:', dbPath);
  console.log('[init-admin] 管理员手机号:', phone);

  const db = getDb();
  const now = nowIso();
  const pwdHash = hashPassword(password);

  const existing = db
    .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
    .get(phone);

  if (!existing) {
    const adminId = `u_admin_${nanoid(6)}`;
    db.prepare(
      `INSERT INTO users (
         id, name, nickname, phone, role, status, company_id,
         password_hash, password_updated_at, created_at, updated_at
       ) VALUES (?, '平台管理员', '平台管理员', ?, 'admin', 'active', NULL, ?, ?, ?, ?)`,
    ).run(adminId, phone, pwdHash, now, now, now);
    console.log('[init-admin] 已创建管理员账号 id=', adminId);
  } else {
    db.prepare(
      `UPDATE users
       SET role = 'admin',
           status = 'active',
           company_id = NULL,
           password_hash = ?,
           password_updated_at = ?,
           updated_at = ?
       WHERE id = ?`,
    ).run(pwdHash, now, now, existing.id);
    console.log('[init-admin] 已重置管理员账号 id=', existing.id);
  }

  const user = db
    .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
    .get(phone);

  if (!user || user.role !== 'admin') {
    console.error('[init-admin] 校验失败：角色不是 admin');
    process.exit(1);
  }
  if (!verifyPassword(password, user.password_hash)) {
    console.error('[init-admin] 校验失败：密码 hash 不匹配');
    process.exit(1);
  }

  closeDb();
  console.log('管理员账号初始化成功');
}

main();
