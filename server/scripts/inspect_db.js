const Database = require('better-sqlite3');
const db = new Database('./data/feigong-yuncan.db', { readonly: true });
const tables = db
  .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
  .all();
console.log('TABLES:', tables.map((t) => t.name).join(','));
const wanted = [
  'users',
  'companies',
  'merchants',
  'dishes',
  'orders',
  'order_items',
  'employee_profiles',
  'sms_codes',
  'admin_operation_logs',
  'system_config',
];
for (const t of wanted) {
  try {
    const c = db.prepare('SELECT COUNT(1) AS c FROM ' + t).get().c;
    console.log(t.padEnd(24), c);
  } catch (e) {
    console.log(t.padEnd(24), 'MISSING');
  }
}
