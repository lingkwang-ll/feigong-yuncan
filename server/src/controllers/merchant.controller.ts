import { Request, Response } from 'express';
import { BadRequest, Forbidden, NotFound, Unauthorized } from '../middleware/error.middleware';
import { merchantToDto, reviewToDto } from '../models/mappers';
import { ALL_MEAL_TYPES, MealType, ReviewListFilter, UserRow } from '../models/types';
import { merchantService } from '../services/merchant.service';
import { merchantCreditService } from '../services/merchant-credit.service';
import { settlementService } from '../services/settlement.service';
import { withdrawalService } from '../services/withdrawal.service';
import { mealLabelPrintService,
  MarkMealLabelPrintedInput,
} from '../services/meal-label-print.service';
import { reviewService } from '../services/review.service';
import { adminOperationLogService } from '../services/admin-operation-log.service';
import { merchantAgreementService } from '../services/merchant-agreement.service';
import {
  assertMerchantAccess,
  DEFAULT_COMPANY_ID,
  resolveAdminScope,
} from '../utils/company-scope.util';

/**
 * 解析本次请求要操作的 merchantId 并完成鉴权
 *
 * - 商家：仅能操作自己绑定的 merchantId（即使 body 显式传入也必须等于自己）
 * - 平台 / 企业管理员：可通过 body / query 指定任意 merchantId（受 assertMerchantAccess 校验）
 * - 员工：禁止访问商家管理接口
 */
function resolveOwnedMerchantId(req: Request, bodyMerchantId?: string): string {
  if (!req.user) throw Unauthorized();
  const user = req.user;
  const requestedId =
    bodyMerchantId || (req.query.merchantId as string | undefined) || undefined;
  const scope = resolveAdminScope(user);

  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (requestedId && requestedId !== scope.merchantId) {
      throw Forbidden('无权操作其它商家');
    }
    return scope.merchantId;
  }

  if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
    if (!requestedId) throw BadRequest('缺少 merchantId');
    try {
      assertMerchantAccess(user, requestedId);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权操作该商家');
      throw e;
    }
    return requestedId;
  }

  throw Forbidden('当前角色无权访问商家管理接口');
}

function assertCanReadMerchant(user: UserRow, merchantId: string): void {
  try {
    assertMerchantAccess(user, merchantId);
  } catch (e) {
    if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权访问该商家');
    throw e;
  }
}

export const merchantController = {
  listNearby(req: Request, res: Response) {
    const companyId =
      req.user?.company_id ??
      (req.query.companyId as string | undefined) ??
      DEFAULT_COMPANY_ID;
    const list = merchantService.listForCompany(companyId).map(merchantToDto);
    res.json({ data: list });
  },

  getMyProfile(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const scope = resolveAdminScope(req.user);

    if (scope.isMerchant) {
      const m = merchantService.getByUserId(req.user.id);
      if (!m) throw NotFound('未找到对应商家');
      res.json({ data: merchantToDto(m) });
      return;
    }

    if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
      const targetUserId =
        (req.query.userId as string | undefined) ||
        (req.header('X-User-Id') as string | undefined);
      if (!targetUserId) throw BadRequest('缺少 userId');
      const m = merchantService.getByUserId(targetUserId);
      if (!m) throw NotFound('未找到对应商家');
      assertCanReadMerchant(req.user, m.id);
      res.json({ data: merchantToDto(m) });
      return;
    }

    throw Forbidden('当前角色无权访问商家资料');
  },

  updateProfile(req: Request, res: Response) {
    const body = req.body ?? {};
    const id = resolveOwnedMerchantId(req, body.merchantId);
    const m = merchantService.updateProfile(id, {
      name: body.name,
      logo: body.logo,
      contactName: body.contactName,
      contactPhone: body.contactPhone,
      address: body.address,
      description: body.description,
    });
    res.json({ data: merchantToDto(m) });
  },

  updateDeliverySettings(req: Request, res: Response) {
    const body = req.body ?? {};
    const id = resolveOwnedMerchantId(req, body.merchantId);
    const m = merchantService.updateDeliverySettings(id, {
      deliveryModes: body.deliveryModes,
      deliveryFee:
        body.deliveryFee != null ? Number(body.deliveryFee) : undefined,
      deliveryScope: body.deliveryScope,
      estimatedDeliveryTime: body.estimatedDeliveryTime,
    });
    res.json({ data: merchantToDto(m) });
  },

  updateBusinessHours(req: Request, res: Response) {
    const body = req.body ?? {};
    const id = resolveOwnedMerchantId(req, body.merchantId);
    const meals = (body.supportedMealTypes ?? []) as MealType[];
    if (meals.some((m) => !ALL_MEAL_TYPES.includes(m))) {
      throw BadRequest('supportedMealTypes 非法');
    }
    try {
      const m = merchantService.updateBusinessHours(id, {
        supportedMealTypes: meals.length ? meals : undefined,
        mealOpeningHours: body.mealOpeningHours,
      });
      res.json({ data: merchantToDto(m) });
    } catch (e) {
      const code = (e as Error).message;
      if (code === 'BUSINESS_HOURS_END_BEFORE_START') {
        throw BadRequest('结束时间必须晚于开始时间', 'BUSINESS_HOURS_END_BEFORE_START');
      }
      if (code === 'INVALID_BUSINESS_HOURS') {
        throw BadRequest('营业时间格式非法', 'INVALID_BUSINESS_HOURS');
      }
      throw e;
    }
  },

  updatePaymentQrCode(req: Request, res: Response) {
    const { merchantId: bodyMerchantId, paymentQrCode, channel } = req.body ?? {};
    if (!paymentQrCode) throw BadRequest('缺少 paymentQrCode');
    const id = resolveOwnedMerchantId(req, bodyMerchantId);
    let m;
    if (channel === 'wechat' || channel === 'alipay') {
      m = merchantService.updateChannelPaymentQr(id, channel, paymentQrCode);
    } else {
      m = merchantService.updatePaymentQrCode(id, paymentQrCode);
    }
    merchantAgreementService.recordSignWithCurrentVersion(id, {
      ipAddress: req.ip || req.socket.remoteAddress,
      userAgent:
        (typeof req.body?.deviceInfo === 'string'
          ? req.body.deviceInfo.trim()
          : '') ||
        req.get('user-agent') ||
        undefined,
    });
    res.json({ data: merchantToDto(m) });
  },

  updateIsOpen(req: Request, res: Response) {
    const { merchantId: bodyMerchantId, isOpen } = req.body ?? {};
    if (typeof isOpen !== 'boolean') throw BadRequest('isOpen 必须是 boolean');
    const id = resolveOwnedMerchantId(req, bodyMerchantId);
    const m = merchantService.update(id, { is_open: isOpen ? 1 : 0 });
    if (isOpen) {
      merchantAgreementService.recordSignWithCurrentVersion(id, {
        ipAddress: req.ip || req.socket.remoteAddress,
        userAgent:
          (typeof req.body?.deviceInfo === 'string'
            ? req.body.deviceInfo.trim()
            : '') ||
          req.get('user-agent') ||
          undefined,
      });
    }
    res.json({ data: merchantToDto(m) });
  },

  getWallet(req: Request, res: Response) {
    const id = resolveOwnedMerchantId(req, req.query.merchantId as string);
    res.json({ data: settlementService.getMerchantWalletSummary(id) });
  },

  listWithdrawals(req: Request, res: Response) {
    const id = resolveOwnedMerchantId(req, req.query.merchantId as string);
    const rows = withdrawalService.listByMerchant(id);
    res.json({
      data: rows.map((r) => ({
        id: r.id,
        amount: r.amount,
        status: r.status,
        accountName: r.account_name,
        accountType: r.account_type,
        accountNo: r.account_no,
        remark: r.remark,
        createdAt: r.created_at,
        reviewedAt: r.reviewed_at,
      })),
    });
  },

  createWithdrawal(req: Request, res: Response) {
    const body = req.body ?? {};
    const id = resolveOwnedMerchantId(req, body.merchantId as string);
    const amount = Number(body.amount);
    const accountName = String(body.accountName ?? '').trim();
    const accountType = String(body.accountType ?? '').trim();
    const accountNo = String(body.accountNo ?? '').trim();

    try {
      const row = withdrawalService.create({
        merchantId: id,
        amount,
        accountName,
        accountType,
        accountNo,
      });
      res.json({
        data: {
          id: row.id,
          amount: row.amount,
          status: row.status,
          accountName: row.account_name,
          accountType: row.account_type,
          accountNo: row.account_no,
          createdAt: row.created_at,
        },
      });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'INVALID_AMOUNT') {
        throw BadRequest('提现金额必须大于 0', 'INVALID_AMOUNT');
      }
      if (msg === 'AMOUNT_EXCEEDS_WITHDRAWABLE') {
        throw BadRequest('提现金额不能超过可提现金额', 'AMOUNT_EXCEEDS_WITHDRAWABLE');
      }
      if (msg === 'ACCOUNT_REQUIRED') {
        throw BadRequest('请填写完整收款账户信息', 'ACCOUNT_REQUIRED');
      }
      throw e;
    }
  },

  listSettlementDetails(req: Request, res: Response) {
    const id = resolveOwnedMerchantId(req, req.query.merchantId as string);
    res.json({ data: settlementService.listSettlementDetailsForMerchant(id) });
  },

  getHygieneStats(req: Request, res: Response) {
    const id = resolveOwnedMerchantId(req, req.query.merchantId as string);
    res.json({ data: merchantCreditService.getHygieneStats(id) });
  },

  listReviews(req: Request, res: Response) {
    const merchantId = resolveOwnedMerchantId(req, req.query.merchantId as string);
    const rawFilter = (req.query.filter as string | undefined)?.trim() ?? 'all';
    const allowed: ReviewListFilter[] = [
      'all',
      'good',
      'medium',
      'bad',
      'with_images',
    ];
    const filter = allowed.includes(rawFilter as ReviewListFilter)
      ? (rawFilter as ReviewListFilter)
      : 'all';
    const stats = merchantCreditService.getHygieneStats(merchantId);
    const rows = reviewService.listForMerchant(merchantId, { filter, limit: 100 });
    res.json({
      data: {
        stats,
        reviews: rows.map((row) => {
          const display = reviewService.resolveDisplayName(row, 'merchant');
          return reviewToDto(row, reviewService.imagesOf(row), {
            displayUserName: display.displayUserName,
            departmentName: display.departmentName,
            orderNo: row.order_no ?? '',
          });
        }),
      },
    });
  },

  getMealLabelPrintStatus(req: Request, res: Response) {
    const merchantId = resolveOwnedMerchantId(req, req.query.merchantId as string);
    const businessDate = (req.query.businessDate as string)?.trim();
    const mealType = req.query.mealType as MealType;
    if (!businessDate) throw BadRequest('缺少 businessDate');
    if (!mealType || !ALL_MEAL_TYPES.includes(mealType)) {
      throw BadRequest('mealType 非法');
    }
    const items = mealLabelPrintService.listStatus(
      merchantId,
      businessDate,
      mealType,
    );
    res.json({ data: { items } });
  },

  markMealLabelsPrinted(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const merchantId = resolveOwnedMerchantId(req, req.body?.merchantId as string);
    const businessDate = (req.body?.businessDate as string)?.trim();
    const mealType = req.body?.mealType as MealType;
    const labels = (req.body?.labels ?? []) as MarkMealLabelPrintedInput[];
    if (!businessDate) throw BadRequest('缺少 businessDate');
    if (!mealType || !ALL_MEAL_TYPES.includes(mealType)) {
      throw BadRequest('mealType 非法');
    }
    if (!Array.isArray(labels) || labels.length === 0) {
      throw BadRequest('labels 不能为空');
    }
    try {
      const result = mealLabelPrintService.markPrinted(
        merchantId,
        businessDate,
        mealType,
        labels,
      );
      adminOperationLogService.write({
        operator: req.user,
        action: 'merchant.meal_labels.mark_printed',
        targetType: 'merchant',
        targetId: merchantId,
        detail: { businessDate, mealType, labelCount: labels.length, ...result },
        ip: req.ip,
      });
      res.json({ data: result });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'ORDER_NOT_FOUND') throw NotFound('订单不存在');
      if (msg === 'FORBIDDEN') throw Forbidden('无权标记该订单标签');
      throw e;
    }
  },
};
