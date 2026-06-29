import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { paymentConfigService } from '../services/payment-config.service';
import { paymentService } from '../services/payment.service';

export const paymentController = {
  config(_req: Request, res: Response) {
    res.json({ data: paymentConfigService.getPublicConfig() });
  },

  create(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const b = req.body ?? {};
    const orderId = typeof b.orderId === 'string' ? b.orderId : '';
    const channel = b.channel as 'wechat_pay' | 'alipay' | 'manual_qr';
    if (!orderId) throw BadRequest('缺少 orderId');
    if (!['wechat_pay', 'alipay', 'manual_qr'].includes(channel)) {
      throw BadRequest('channel 非法');
    }
    try {
      const result = paymentService.createPayment(
        orderId,
        channel,
        req.user.id,
      );
      res.json({
        data: {
          paymentId: result.payment.id,
          paymentNo: result.payment.payment_no,
          channel: result.payment.channel,
          amount: result.payment.amount,
          status: result.payment.status,
          payParams: result.payParams,
        },
      });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'CHANNEL_NOT_ENABLED') {
        throw BadRequest(
          '该支付方式暂未开通，请使用付款截图',
          'CHANNEL_NOT_ENABLED',
        );
      }
      if (msg === 'ORDER_NOT_FOUND') throw NotFound('订单不存在');
      if (msg === 'FORBIDDEN') throw Forbidden('无权操作该订单');
      if (msg === 'ORDER_NOT_PENDING_PAYMENT') {
        throw BadRequest('订单不在待支付状态', 'ORDER_NOT_PENDING_PAYMENT');
      }
      if (msg === 'NO_EMPLOYEE_PAYMENT_REQUIRED') {
        throw BadRequest('该订单无需员工支付', 'NO_EMPLOYEE_PAYMENT_REQUIRED');
      }
      if (msg === 'ORDER_ALREADY_PAID') {
        throw BadRequest('订单已支付', 'ORDER_ALREADY_PAID');
      }
      throw e;
    }
  },

  mockPaid(req: Request, res: Response) {
    if (process.env.NODE_ENV === 'production') {
      throw Forbidden('生产环境禁止 mock 支付');
    }
    if (!req.user) throw Unauthorized();
    const b = req.body ?? {};
    const paymentId = typeof b.paymentId === 'string' ? b.paymentId : '';
    if (!paymentId) throw BadRequest('缺少 paymentId');
    const amount = b.amount != null ? Number(b.amount) : undefined;
    try {
      const payment = paymentService.mockPaid(paymentId, amount);
      res.json({ data: payment });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'PAYMENT_NOT_FOUND') throw NotFound('支付单不存在');
      if (msg === 'PAYMENT_AMOUNT_MISMATCH') {
        throw BadRequest('支付金额不一致', 'PAYMENT_AMOUNT_MISMATCH');
      }
      if (msg === 'ORDER_NOT_PENDING_PAYMENT') {
        throw BadRequest('订单不在待支付状态');
      }
      throw e;
    }
  },

  wechatNotify(req: Request, res: Response) {
    try {
      const result = paymentService.handleWechatNotify(req.body);
      if (result.ok) {
        res.json({ code: 'SUCCESS', message: 'OK' });
      } else {
        res.status(400).json({ code: 'FAIL', message: 'invalid notify' });
      }
    } catch {
      res.status(400).json({ code: 'FAIL', message: 'invalid notify' });
    }
  },

  alipayNotify(req: Request, res: Response) {
    try {
      const result = paymentService.handleAlipayNotify(req.body);
      if (result.ok) {
        res.send('success');
      } else {
        res.status(400).send('fail');
      }
    } catch {
      res.status(400).send('fail');
    }
  },
};
