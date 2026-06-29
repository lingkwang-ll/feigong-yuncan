import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { runMigrations } from './migrate_db';

let db: Database.Database | null = null;

function ensureDir(filepath: string) {
  const dir = path.dirname(filepath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

export function getDb(): Database.Database {
  if (db) return db;
  // 优先使用 DATABASE_PATH（上线规范名），兼容旧 DATABASE_FILE。
  const file =
    process.env.DATABASE_PATH ||
    process.env.DATABASE_FILE ||
    './data/feigong-yuncan.db';
  const abs = path.resolve(process.cwd(), file);
  ensureDir(abs);

  db = new Database(abs);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  const schemaPath = path.resolve(__dirname, 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf-8');
  db.exec(schema);
  runMigrations(db);

  return db;
}

export function closeDb() {
  if (db) {
    db.close();
    db = null;
  }
}
