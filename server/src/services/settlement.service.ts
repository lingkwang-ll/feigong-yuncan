import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import {
  MerchantSettlementRow,
  OrderRow,
  SettlementStatus,
} from '../models/types';

const SETTLEMENT_DAYS = 7;

function addDays(iso: string, days: number): string {
  const d = new Date(iso);
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

function genSettlementNo(): string {
  return `ST${Date.now()}${Math.floor(Math.random() * 1000)
    .toString()
    .padStart(3, '0')}`;
}

export class SettlementService {
  /** 订单完成时创建结算记录 */
  onOrderCompleted(order: OrderRow): MerchantSettlementRow {
    const db = getDb();
    const existing = db
      .prepare<[string], MerchantSettlementRow>(
        'SELECT * FROM merchant_settlements WHERE order_id = ?',
      )
      .get(order.id);
    if (existing) return existing;

    const now = nowIso();
    const completedAt = now;
    const eligibleAt = addDays(completedAt, SETTLEMENT_DAYS);
    const orderAmount = order.final_amount ?? order.total_amount;
    const companyPay = order.company_pay_amount ?? 0;
    const employeePay = order.employee_pay_amount ?? 0;
    const platformFee = Number((orderAmount * 0.02).toFixed(2));
    const receivable = Number(
      (orderAmount - platformFee).toFixed(2),
    );

    const id = `MS${nanoid(10)}`;
    const settlementNo = genSettlementNo();
    db.prepare(
      `INSERT INTO merchant_settlements
         (id, merchant_id, order_id, settlement_no, order_amount,
          company_pay_amount, employee_pay_amount, platform_service_fee,
          merchant_receivable_amount, status, completed_at,
          settlement_eligible_at, settled_at, block_reason, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, NULL, NULL, ?, ?)`,
    ).run(
      id,
      order.merchant_id,
      order.id,
      settlementNo,
      orderAmount,
      companyPay,
      employeePay,
      platformFee,
      receivable,
      completedAt,
      eligibleAt,
      now,
      now,
    );

    db.prepare(
      `UPDATE orders SET
         settlement_status = 'completed_pending_settlement',
         completed_at = ?,
         settlement_eligible_at = ?,
         updated_at = ?
       WHERE id = ?`,
    ).run(completedAt, eligibleAt, now, order.id);

    return db
      .prepare<[string], MerchantSettlementRow>(
        'SELECT * FROM merchant_settlements WHERE id = ?',
      )
      .get(id)!;
  }

  /** 将到期结算标记为 eligible */
  runEligibilityCheck(): number {
    const db = getDb();
    const now = nowIso();
    const due = db
      .prepare(
        `SELECT * FROM merchant_settlements
         WHERE status = 'pending'
           AND settlement_eligible_at IS NOT NULL
           AND datetime(settlement_eligible_at) <= datetime(?)`,
      )
      .all(now) as MerchantSettlementRow[];

    let count = 0;
    for (const s of due) {
      const order = db
        .prepare<[string], OrderRow>('SELECT * FROM orders WHERE id = ?')
        .get(s.order_id);
      if (!order || order.settlement_status === 'settlement_blocked') {
        continue;
      }
      db.prepare(
        `UPDATE merchant_settlements SET status = 'eligible', updated_at = ? WHERE id = ?`,
      ).run(now, s.id);
      db.prepare(
        `UPDATE orders SET settlement_status = 'settlement_pending', updated_at = ? WHERE id = ?`,
      ).run(now, s.order_id);
      count++;
    }
    return count;
  }

  settle(settlementId: string): MerchantSettlementRow {
    const db = getDb();
    const row = db
      .prepare<[string], MerchantSettlementRow>(
        'SELECT * FROM merchant_settlements WHERE id = ?',
      )
      .get(settlementId);
    if (!row) throw new Error('SETTLEMENT_NOT_FOUND');
    if (row.status === 'settled') return row;
    if (row.status === 'blocked') throw new Error('SETTLEMENT_BLOCKED');
    if (row.status !== 'eligible' && row.status !== 'pending') {
      throw new Error('SETTLEMENT_NOT_ELIGIBLE');
    }

    const now = nowIso();
    db.prepare(
      `UPDATE merchant_settlements SET status = 'settled', settled_at = ?, updated_at = ? WHERE id = ?`,
    ).run(now, now, settlementId);
    db.prepare(
      `UPDATE orders SET settlement_status = 'settled', updated_at = ? WHERE id = ?`,
    ).run(now, row.order_id);

    return db
      .prepare<[string], MerchantSettlementRow>(
        'SELECT * FROM merchant_settlements WHERE id = ?',
      )
      .get(settlementId)!;
  }

  /** 测试用：将结算到期时间提前 */
  forceEligible(orderId: string): MerchantSettlementRow {
    const db = getDb();
    const now = nowIso();
    const past = new Date(Date.now() - 1000).toISOString();
    db.prepare(
      `UPDATE merchant_settlements SET settlement_eligible_at = ?, updated_at = ? WHERE order_id = ?`,
    ).run(past, now, orderId);
    this.runEligibilityCheck();
    const row = db
      .prepare<[string], MerchantSettlementRow>(
        'SELECT * FROM merchant_settlements WHERE order_id = ?',
      )
      .get(orderId);
    if (!row) throw new Error('SETTLEMENT_NOT_FOUND');
    return row;
  }

  getByOrderId(orderId: string): MerchantSettlementRow | undefined {
    return getDb()
      .prepare<[string], MerchantSettlementRow>(
        'SELECT * FROM merchant_settlements WHERE order_id = ?',
      )
      .get(orderId);
  }

  listByMerchant(
    merchantId: string,
    status?: string,
  ): MerchantSettlementRow[] {
    const db = getDb();
    if (status) {
      return db
        .prepare<[string, string], MerchantSettlementRow>(
          `SELECT * FROM merchant_settlements
           WHERE merchant_id = ? AND status = ?
           ORDER BY created_at DESC`,
        )
        .all(merchantId, status);
    }
    return db
      .prepare<[string], MerchantSettlementRow>(
        `SELECT * FROM merchant_settlements
         WHERE merchant_id = ? ORDER BY created_at DESC`,
      )
      .all(merchantId);
  }

  listAll(status?: string): MerchantSettlementRow[] {
    const db = getDb();
    if (status) {
      return db
        .prepare(
          `SELECT * FROM merchant_settlements WHERE status = ? ORDER BY created_at DESC`,
        )
        .all(status) as MerchantSettlementRow[];
    }
    return db
      .prepare(
        `SELECT * FROM merchant_settlements ORDER BY created_at DESC`,
      )
      .all() as MerchantSettlementRow[];
  }

  getMerchantWalletSummary(merchantId: string) {
    const db = getDb();

    const sumReceivable = (...statuses: string[]) => {
      if (statuses.length === 0) return 0;
      const placeholders = statuses.map(() => '?').join(',');
      const row = db
        .prepare(
          `SELECT COALESCE(SUM(merchant_receivable_amount), 0) AS amt
           FROM merchant_settlements
           WHERE merchant_id = ? AND status IN (${placeholders})`,
        )
        .get(merchantId, ...statuses) as { amt: number } | undefined;
      return Number((row?.amt ?? 0).toFixed(2));
    };

    const settledTotal = sumReceivable('settled');

    const withdrawnRow = db
      .prepare<[string], { amt: number }>(
        `SELECT COALESCE(SUM(amount), 0) AS amt FROM merchant_withdrawals
         WHERE merchant_id = ? AND status = 'paid'`,
      )
      .get(merchantId);
    const withdrawnAmount = Number((withdrawnRow?.amt ?? 0).toFixed(2));

    const withdrawingRow = db
      .prepare<[string], { amt: number }>(
        `SELECT COALESCE(SUM(amount), 0) AS amt FROM merchant_withdrawals
         WHERE merchant_id = ? AND status IN ('pending', 'approved')`,
      )
      .get(merchantId);
    const withdrawingAmount = Number((withdrawingRow?.amt ?? 0).toFixed(2));

    const withdrawableAmount = Math.max(
      0,
      Number((settledTotal - withdrawingAmount - withdrawnAmount).toFixed(2)),
    );

    const pendingSettlementAmount = sumReceivable('pending', 'eligible');

    return {
      withdrawableAmount,
      pendingSettlementAmount,
      withdrawingAmount,
      withdrawnAmount,
      settlementRuleText: '订单完成满7天后可提现',
    };
  }

  listSettlementDetailsForMerchant(merchantId: string) {
    const db = getDb();
    const rows = db
      .prepare(
        `SELECT ms.*, o.order_no
         FROM merchant_settlements ms
         LEFT JOIN orders o ON o.id = ms.order_id
         WHERE ms.merchant_id = ?
         ORDER BY datetime(ms.completed_at) DESC
         LIMIT 100`,
      )
      .all(merchantId) as Array<
      MerchantSettlementRow & { order_no: string | null }
    >;

    return rows.map((r) => ({
      orderId: r.order_id,
      orderNo: r.order_no ?? r.order_id,
      completedAt: r.completed_at,
      status: r.status,
      settlementEligibleAt: r.settlement_eligible_at,
      orderAmount: r.order_amount,
      merchantReceivableAmount: r.merchant_receivable_amount,
    }));
  }

  markOrderPaidToPlatform(orderId: string, channel: string): void {
    const db = getDb();
    db.prepare(
      `UPDATE orders SET settlement_status = 'paid_to_platform', payment_channel = ?, updated_at = ? WHERE id = ?`,
    ).run(channel, nowIso(), orderId);
  }

  markOrderInService(orderId: string): void {
    const db = getDb();
    db.prepare(
      `UPDATE orders SET settlement_status = 'in_service', updated_at = ? WHERE id = ?`,
    ).run(nowIso(), orderId);
  }

  initialSettlementStatus(
    employeePayAmount: number,
  ): SettlementStatus {
    return employeePayAmount <= 0 ? 'in_service' : 'not_paid';
  }
}

export const settlementService = new SettlementService();
