import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { OrderRow, PaymentTransactionRow } from '../models/types';
import { paymentConfigService } from './payment-config.service';
import { orderService } from './order.service';
import { settlementService } from './settlement.service';

export type PaymentChannelInput = 'wechat_pay' | 'alipay' | 'manual_qr';

function genPaymentNo(): string {
  return `PY${Date.now()}${Math.floor(Math.random() * 10000)
    .toString()
    .padStart(4, '0')}`;
}

export class PaymentService {
  createPayment(
    orderId: string,
    channel: PaymentChannelInput,
    userId: string,
  ): {
    payment: PaymentTransactionRow;
    payParams: Record<string, unknown>;
  } {
    if (!paymentConfigService.isCreateAllowed(channel)) {
      throw new Error('CHANNEL_NOT_ENABLED');
    }

    const order = orderService.getById(orderId);
    if (!order) throw new Error('ORDER_NOT_FOUND');
    if (order.user_id !== userId) throw new Error('FORBIDDEN');
    if (order.status !== 'pendingPayment') {
      throw new Error('ORDER_NOT_PENDING_PAYMENT');
    }
    const amount = order.employee_pay_amount ?? 0;
    if (amount <= 0) throw new Error('NO_EMPLOYEE_PAYMENT_REQUIRED');

    const db = getDb();
    const existingPaid = db
      .prepare<[string], PaymentTransactionRow>(
        `SELECT * FROM payment_transactions
         WHERE order_id = ? AND status = 'paid' LIMIT 1`,
      )
      .get(orderId);
    if (existingPaid) throw new Error('ORDER_ALREADY_PAID');

    let pending = db
      .prepare<[string, string], PaymentTransactionRow>(
        `SELECT * FROM payment_transactions
         WHERE order_id = ? AND channel = ? AND status IN ('created','pending')
         ORDER BY created_at DESC LIMIT 1`,
      )
      .get(orderId, channel);

    const now = nowIso();
    if (!pending) {
      const id = `PT${nanoid(10)}`;
      const paymentNo = genPaymentNo();
      const requestPayload = { channel, amount, orderId };
      db.prepare(
        `INSERT INTO payment_transactions
           (id, order_id, payment_no, channel, amount, status,
            request_payload_json, notify_payload_json, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'pending', ?, '{}', ?, ?)`,
      ).run(
        id,
        orderId,
        paymentNo,
        channel,
        amount,
        JSON.stringify(requestPayload),
        now,
        now,
      );
      pending = db
        .prepare<[string], PaymentTransactionRow>(
          'SELECT * FROM payment_transactions WHERE id = ?',
        )
        .get(id)!;
    }

    const payParams = this.buildPayParams(pending, order);
    return { payment: pending, payParams };
  }

  private buildPayParams(
    payment: PaymentTransactionRow,
    order: OrderRow,
  ): Record<string, unknown> {
    if (payment.channel === 'wechat_pay') {
      if (paymentConfigService.isWechatPayReady()) {
        return {
          mode: 'wechat',
          paymentId: payment.id,
          paymentNo: payment.payment_no,
          amount: payment.amount,
          notifyUrl: process.env.WECHAT_PAY_NOTIFY_URL,
        };
      }
      if (paymentConfigService.shouldUseMockPayParams('wechat_pay')) {
        return {
          mode: 'mock',
          paymentId: payment.id,
          paymentNo: payment.payment_no,
          amount: payment.amount,
          hint: '开发环境 mock 支付（生产不可用）',
        };
      }
      return {
        mode: 'disabled',
        paymentId: payment.id,
        amount: payment.amount,
        hint: '微信支付暂未开通，请使用付款截图',
      };
    }
    if (payment.channel === 'alipay') {
      if (paymentConfigService.isAlipayPayReady()) {
        return {
          mode: 'alipay',
          paymentId: payment.id,
          paymentNo: payment.payment_no,
          amount: payment.amount,
          notifyUrl: process.env.ALIPAY_NOTIFY_URL,
          gateway: process.env.ALIPAY_GATEWAY,
        };
      }
      if (paymentConfigService.shouldUseMockPayParams('alipay')) {
        return {
          mode: 'mock',
          paymentId: payment.id,
          paymentNo: payment.payment_no,
          amount: payment.amount,
          hint: '开发环境 mock 支付（生产不可用）',
        };
      }
      return {
        mode: 'disabled',
        paymentId: payment.id,
        amount: payment.amount,
        hint: '支付宝暂未开通，请使用付款截图',
      };
    }
    return {
      mode: 'manual_qr',
      paymentId: payment.id,
      amount: payment.amount,
    };
  }

  /** 幂等标记支付成功 */
  markPaid(
    paymentId: string,
    opts?: { providerTradeNo?: string; notifyPayload?: unknown; amount?: number },
  ): PaymentTransactionRow {
    const db = getDb();
    const payment = db
      .prepare<[string], PaymentTransactionRow>(
        'SELECT * FROM payment_transactions WHERE id = ?',
      )
      .get(paymentId);
    if (!payment) throw new Error('PAYMENT_NOT_FOUND');

    if (payment.status === 'paid') return payment;

    const order = orderService.getById(payment.order_id);
    if (!order) throw new Error('ORDER_NOT_FOUND');

    const expected = order.employee_pay_amount ?? 0;
    const paidAmount = opts?.amount ?? payment.amount;
    if (Math.abs(paidAmount - expected) > 0.001) {
      throw new Error('PAYMENT_AMOUNT_MISMATCH');
    }
    if (order.status !== 'pendingPayment' && order.status !== 'paymentSubmitted') {
      throw new Error('ORDER_NOT_PENDING_PAYMENT');
    }

    const now = nowIso();
    const tx = db.transaction(() => {
      db.prepare(
        `UPDATE payment_transactions SET
           status = 'paid', provider_trade_no = ?, notify_payload_json = ?,
           paid_at = ?, updated_at = ?
         WHERE id = ? AND status != 'paid'`,
      ).run(
        opts?.providerTradeNo ?? `mock_${payment.payment_no}`,
        JSON.stringify(opts?.notifyPayload ?? { mock: true }),
        now,
        now,
        paymentId,
      );

      settlementService.markOrderPaidToPlatform(order.id, payment.channel);
      orderService.confirmOnlinePayment(order.id, payment.channel);
    });
    tx();

    return db
      .prepare<[string], PaymentTransactionRow>(
        'SELECT * FROM payment_transactions WHERE id = ?',
      )
      .get(paymentId)!;
  }

  mockPaid(paymentId: string, amount?: number): PaymentTransactionRow {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('MOCK_PAYMENT_FORBIDDEN_IN_PRODUCTION');
    }
    return this.markPaid(paymentId, { amount, notifyPayload: { mock: true } });
  }

  getByOrderId(orderId: string): PaymentTransactionRow | undefined {
    return getDb()
      .prepare<[string], PaymentTransactionRow>(
        `SELECT * FROM payment_transactions WHERE order_id = ? ORDER BY created_at DESC LIMIT 1`,
      )
      .get(orderId);
  }

  handleWechatNotify(_body: unknown): { ok: boolean } {
    // 真实验签占位：配置齐全且开关开启时在此接入微信 API v3 验签
    if (!paymentConfigService.isWechatPayReady()) {
      return { ok: false };
    }
    return { ok: false };
  }

  handleAlipayNotify(_body: unknown): { ok: boolean } {
    if (!paymentConfigService.isAlipayPayReady()) {
      return { ok: false };
    }
    return { ok: false };
  }
}

export const paymentService = new PaymentService();
