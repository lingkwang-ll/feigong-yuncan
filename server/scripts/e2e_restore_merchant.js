/* eslint-disable @typescript-eslint/no-require-imports */
/**
 * E2E helper: restore merchant rating / grade / is_open after risk-control tests.
 * Usage: node scripts/e2e_restore_merchant.js <dbPath> <rating> <grade> <isOpen:0|1> <merchantId>
 */
const path = require('path');
const Database = require('better-sqlite3');

const dbPath = process.argv[2];
const rating = parseFloat(process.argv[3]);
const grade = process.argv[4];
const isOpen = process.argv[5] === '1' ? 1 : 0;
const merchantId = process.argv[6];

if (!dbPath || !merchantId || Number.isNaN(rating)) {
  console.error('usage: node e2e_restore_merchant.js <dbPath> <rating> <grade> <isOpen> <merchantId>');
  process.exit(1);
}

const absDb = path.resolve(dbPath);
const db = new Database(absDb);
const now = new Date().toISOString();
db.prepare(
  'UPDATE merchants SET rating = ?, hygiene_grade = ?, is_open = ?, updated_at = ? WHERE id = ?',
).run(rating, grade, isOpen, now, merchantId);
console.log('restored');
