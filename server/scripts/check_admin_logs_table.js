const Database = require('better-sqlite3');
const path = require('path');

const dbPath = path.resolve(
  process.cwd(),
  process.env.DATABASE_PATH || './data/feigong-yuncan.db',
);

const db = new Database(dbPath);
db.exec(`
  CREATE TABLE IF NOT EXISTS admin_operation_logs (
    id                TEXT PRIMARY KEY,
    operator_user_id  TEXT,
    operator_role     TEXT,
    action            TEXT NOT NULL,
    target_type       TEXT,
    target_id         TEXT,
    detail_json       TEXT,
    ip_address        TEXT,
    created_at        TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_admin_op_logs_created
    ON admin_operation_logs(created_at DESC);
`);
const row = db
  .prepare(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='admin_operation_logs'",
  )
  .get();
console.log(row ? 'yes' : 'no');
db.close();
