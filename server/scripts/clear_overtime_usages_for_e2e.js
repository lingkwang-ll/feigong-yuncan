/**
 * E2E helper: clear overtime_meal_usages for test employees.
 * Usage: node scripts/clear_overtime_usages_for_e2e.js <workDate> <phones> [mealType]
 * Example: node scripts/clear_overtime_usages_for_e2e.js 2026-06-29 13800000001 lunch
 */
const path = require('path');
const Database = require('better-sqlite3');

const workDate = process.argv[2];
const phonesArg = process.argv[3] || '';
const mealType = (process.argv[4] || '').trim();

if (!workDate) {
  console.error('workDate required');
  process.exit(1);
}

const phones = phonesArg
  .split(',')
  .map((p) => p.trim())
  .filter(Boolean);
if (phones.length === 0) {
  console.log('0');
  process.exit(0);
}

const dbPath =
  process.env.DATABASE_PATH ||
  path.join(__dirname, '..', 'data', 'feigong-yuncan.db');
const db = new Database(dbPath);
const placeholders = phones.map(() => '?').join(',');
let sql = `DELETE FROM overtime_meal_usages WHERE work_date = ? AND employee_phone IN (${placeholders})`;
const params = [workDate, ...phones];
if (mealType) {
  sql += ' AND meal_type = ?';
  params.push(mealType);
}
const r = db.prepare(sql).run(...params);
console.log(String(r.changes));
