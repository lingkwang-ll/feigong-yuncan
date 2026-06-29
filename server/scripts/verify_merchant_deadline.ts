/**
 * 一次性 E2E 验证：后端下单时按商家营业时间结束时间作为订餐截止。
 *
 * 流程（对 m_self 商家做临时改写，结束后还原）：
 *   1. 备份 meal_opening_hours_json / meal_order_deadlines_json；
 *   2. 写入 lunch end=23:59 → POST /api/orders 应通过；
 *   3. 写入 lunch end=01:00 → 400 MEAL_DEADLINE_PASSED；
 *   4. 清空营业时间 → fallback 全局默认；
 *   5. 还原备份。
 */
import Database from 'better-sqlite3';
import path from 'path';
import {
  isOrderWindowClosed,
  normalizeMealOpeningHours,
  resolveMealOrderWindow,
} from '../src/utils/meal-opening-hours.util';

const BASE = process.env.API_BASE ?? 'http://localhost:3000/api';
const MERCHANT_ID = process.env.VERIFY_MERCHANT_ID ?? 'm_self';
const EMP_PHONE = '13800000000';
const PASSWORD = '123456';

interface OrderResp {
  data?: { id?: string };
  error?: { code?: string; message?: string };
}

interface LoginResp {
  data?: { token: string; user: { id: string } };
}

async function postJson<T>(
  url: string,
  body: unknown,
  token?: string,
): Promise<{ status: number; body: T }> {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  const j = (await res.json().catch(() => ({}))) as T;
  return { status: res.status, body: j };
}

async function getJson<T>(url: string, token?: string): Promise<{ status: number; body: T }> {
  const res = await fetch(url, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  const j = (await res.json().catch(() => ({}))) as T;
  return { status: res.status, body: j };
}

function openDb() {
  const dbPath = path.resolve(process.cwd(), 'data', 'feigong-yuncan.db');
  return new Database(dbPath);
}

interface HoursBackup {
  opening: string | null;
  deadlines: string | null;
}

function readBackup(): HoursBackup {
  const db = openDb();
  try {
    const row = db
      .prepare<
        [string],
        {
          meal_opening_hours_json: string | null;
          meal_order_deadlines_json: string | null;
        }
      >(
        'SELECT meal_opening_hours_json, meal_order_deadlines_json FROM merchants WHERE id = ?',
      )
      .get(MERCHANT_ID);
    return {
      opening: row?.meal_opening_hours_json ?? null,
      deadlines: row?.meal_order_deadlines_json ?? null,
    };
  } finally {
    db.close();
  }
}

function writeLunchOpening(start: string, end: string): void {
  const db = openDb();
  try {
    const opening = JSON.stringify({
      lunch: { enabled: true, start, end, hours: `${start}-${end}` },
    });
    const deadlines = JSON.stringify({ lunch: end });
    db.prepare(
      'UPDATE merchants SET meal_opening_hours_json = ?, meal_order_deadlines_json = ?, updated_at = ? WHERE id = ?',
    ).run(opening, deadlines, new Date().toISOString(), MERCHANT_ID);
  } finally {
    db.close();
  }
}

function writeLunchEnd(end: string): void {
  writeLunchOpening('11:00', end);
}

function clearHours(): void {
  const db = openDb();
  try {
    db.prepare(
      'UPDATE merchants SET meal_opening_hours_json = ?, meal_order_deadlines_json = ?, updated_at = ? WHERE id = ?',
    ).run('{}', '{}', new Date().toISOString(), MERCHANT_ID);
  } finally {
    db.close();
  }
}

function restoreBackup(backup: HoursBackup): void {
  const db = openDb();
  try {
    db.prepare(
      'UPDATE merchants SET meal_opening_hours_json = ?, meal_order_deadlines_json = ?, updated_at = ? WHERE id = ?',
    ).run(
      backup.opening ?? '{}',
      backup.deadlines ?? '{}',
      new Date().toISOString(),
      MERCHANT_ID,
    );
  } finally {
    db.close();
  }
}

async function findLunchDish(token: string): Promise<{
  id: string;
  name: string;
  price: number;
  mealType: string;
} | null> {
  const res = await getJson<{
    data: { id: string; name: string; price: number; mealType: string }[];
  }>(`${BASE}/merchants/${MERCHANT_ID}/dishes?mealType=lunch`, token);
  const list = res.body.data ?? [];
  return list.length ? list[0] : null;
}

let pass = 0;
let fail = 0;
function ok(msg: string) {
  console.log(`[PASS] ${msg}`);
  pass++;
}
function bad(msg: string) {
  console.log(`[FAIL] ${msg}`);
  fail++;
}

async function placeLunchOrder(
  dish: { id: string; name: string; price: number; mealType: string },
  empToken: string,
) {
  const body = {
    merchantId: MERCHANT_ID,
    merchantName: 'VerifyDeadline',
    deliveryType: 'selfPickup',
    address: '',
    phone: '13800000000',
    goodsAmount: dish.price,
    deliveryFee: 0,
    totalAmount: dish.price,
    items: [{ dish, quantity: 1 }],
  };
  return await postJson<OrderResp>(`${BASE}/orders`, body, empToken);
}

function runCrossDayUnitTests() {
  const opening = normalizeMealOpeningHours({
    overtime: { enabled: true, start: '23:00', end: '03:00' },
  });
  const w = resolveMealOrderWindow('overtime', opening);
  if (!w?.crossDay) bad('overtime 23:00-03:00 should be cross-day');
  else ok('overtime 23:00-03:00 parsed as cross-day');
  if (w) {
    if (!isOrderWindowClosed(w, 22 * 60)) bad('22:00 should be outside window');
    else ok('22:00 outside cross-day window');
    if (isOrderWindowClosed(w, 23 * 60)) bad('23:00 should be orderable');
    else ok('23:00 orderable in cross-day window');
    if (isOrderWindowClosed(w, 2 * 60 + 30)) bad('02:30 should be orderable');
    else ok('02:30 orderable in cross-day window');
    if (!isOrderWindowClosed(w, 3 * 60 + 1)) bad('03:01 should be closed');
    else ok('03:01 closed after cross-day deadline');
  }
  const lunchOpening = normalizeMealOpeningHours({
    lunch: { enabled: true, start: '11:00', end: '13:00' },
  });
  const lw = resolveMealOrderWindow('lunch', lunchOpening);
  if (lw?.crossDay) bad('lunch 11:00-13:00 should not be cross-day');
  else ok('lunch same-day window');
  if (lw) {
    if (!isOrderWindowClosed(lw, 14 * 60)) bad('lunch 14:00 should be closed');
    else ok('lunch 14:00 closed (same-day)');
    if (isOrderWindowClosed(lw, 12 * 60)) bad('lunch 12:00 should be open');
    else ok('lunch 12:00 open (same-day)');
  }
}

async function main() {
  console.log('--- cross-day unit tests ---');
  runCrossDayUnitTests();
  console.log('');
  console.log(`API base: ${BASE}`);
  console.log(`Target merchant: ${MERCHANT_ID}`);

  const backup = readBackup();
  console.log(`Backup opening: ${backup.opening ?? '<null>'}`);
  console.log(`Backup deadlines: ${backup.deadlines ?? '<null>'}`);

  try {
    const login = await postJson<LoginResp>(`${BASE}/auth/password-login`, {
      phone: EMP_PHONE,
      password: PASSWORD,
      role: 'employee',
    });
    if (!login.body.data?.token) {
      bad(`employee login failed status=${login.status}`);
      return;
    }
    const empToken = login.body.data.token;
    ok(`employee login id=${login.body.data.user.id}`);

    const dish = await findLunchDish(empToken);
    if (!dish) {
      bad('no lunch dish available for merchant');
      return;
    }
    ok(`lunch dish picked: ${dish.id}`);

    writeLunchEnd('23:59');
    const r1 = await placeLunchOrder(dish, empToken);
    if (r1.status >= 200 && r1.status < 300 && r1.body.data?.id) {
      ok(`lunch end=23:59 -> order accepted (id=${r1.body.data.id})`);
    } else {
      bad(
        `lunch end=23:59 expected success, got status=${r1.status} body=${JSON.stringify(r1.body)}`,
      );
    }

    const nowMin = new Date().getHours() * 60 + new Date().getMinutes();
    writeLunchOpening('11:00', '12:00');
    const lunchW = resolveMealOrderWindow(
      'lunch',
      normalizeMealOpeningHours({
        lunch: { enabled: true, start: '11:00', end: '12:00' },
      }),
    );
    if (lunchW && isOrderWindowClosed(lunchW, nowMin)) {
      const r2 = await placeLunchOrder(dish, empToken);
      if (r2.status === 400 && r2.body.error?.code === 'MEAL_DEADLINE_PASSED') {
        ok('lunch 11:00-12:00 past deadline -> blocked MEAL_DEADLINE_PASSED');
      } else {
        bad(
          `lunch past deadline expected 400, got status=${r2.status} body=${JSON.stringify(r2.body)}`,
        );
      }
    } else {
      ok('lunch 11:00-12:00 skip API past test (current time still in window)');
    }

    clearHours();
    const globalLunchEnd = 9 * 60 + 30;
    if (nowMin > globalLunchEnd) {
      const r3 = await placeLunchOrder(dish, empToken);
      if (r3.status === 400 && r3.body.error?.code === 'MEAL_DEADLINE_PASSED') {
        ok('merchant hours cleared (fallback global) -> blocked MEAL_DEADLINE_PASSED');
      } else {
        bad(
          `fallback expected 400 MEAL_DEADLINE_PASSED, got status=${r3.status} body=${JSON.stringify(r3.body)}`,
        );
      }
    } else {
      ok('fallback skip (global lunch deadline not passed yet)');
    }
  } finally {
    restoreBackup(backup);
    console.log('Restored opening hours and deadlines from backup');
  }

  console.log('');
  console.log('------------------ summary ------------------');
  console.log(`  PASS: ${pass}`);
  console.log(`  FAIL: ${fail}`);
  process.exitCode = fail > 0 ? 1 : 0;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 2;
});
