import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import {
  couponClaimToDto,
  couponService,
  couponTemplateToDto,
  CreateCouponTemplateInput,
} from '../services/coupon.service';
import { MealType, UserRow } from '../models/types';
import { ALL_MEAL_TYPES } from '../models/types';
import { resolveAdminScope } from '../utils/company-scope.util';
import { merchantService } from '../services/merchant.service';
import { resolveEmployeeContext } from '../utils/employee-context.util';
import { shanghaiDateString } from '../utils/date.util';
import { overtimeRosterService } from '../services/overtime-roster.service';
import { overtimeMealUsageService } from '../services/overtime-meal-usage.service';
import { COMPANY_PAY_SUBSIDY_CAP } from '../constants/company-pay.constants';

function ensureUser(req: Request): UserRow {
  if (!req.user) throw Unauthorized();
  return req.user;
}

function resolveMerchantId(user: UserRow, bodyMerchantId?: string): string {
  const scope = resolveAdminScope(user);
  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    return scope.merchantId;
  }
  if ((scope.isPlatformAdmin || scope.isCompanyAdmin) && bodyMerchantId) {
    return bodyMerchantId;
  }
  throw Forbidden('无权管理优惠券');
}

function mapCouponError(e: unknown): never {
  const code = (e as Error).message;
  const map: Record<string, string> = {
    COUPON_NOT_FOUND: '优惠券不存在',
    COUPON_EXPIRED: '优惠券已过期',
    COUPON_DISABLED: '优惠券已停用',
    COUPON_SOLD_OUT: '优惠券已领完',
    CLAIM_LIMIT_REACHED: '已达领取上限',
    CLAIM_NOT_FOUND: '优惠券领取记录不存在',
    COUPON_ALREADY_USED: '优惠券已使用',
    THRESHOLD_NOT_MET: '未满足使用门槛',
    NEWCOMER_NOT_ELIGIBLE: '新人券仅限首次下单',
    MEAL_TYPE_NOT_APPLICABLE: '当前餐段不可用',
    NO_EMPLOYEE_PAY_TO_DISCOUNT: '无可抵扣的员工自付金额',
    FORBIDDEN: '无权操作',
    MERCHANT_MISMATCH: '优惠券商家不匹配',
    NAME_REQUIRED: '优惠券名称不能为空',
    INVALID_DISCOUNT: '优惠金额无效',
    MIN_ORDER_REQUIRED: '满减券需设置使用门槛',
    INVALID_QUANTITY: '发放数量无效',
  };
  if (code === 'FORBIDDEN') throw Forbidden(map.FORBIDDEN);
  if (map[code]) throw BadRequest(map[code], code);
  throw e;
}

function parseMealTypes(raw: unknown): MealType[] {
  if (!Array.isArray(raw)) return ['breakfast', 'lunch', 'dinner'];
  return raw.filter(
    (m): m is MealType =>
      typeof m === 'string' && ALL_MEAL_TYPES.includes(m as MealType),
  );
}

function previewEmployeePayBeforeCoupon(
  user: UserRow,
  merchantId: string,
  mealType: MealType | null,
  totalAmount: number,
): number {
  const empCtx = resolveEmployeeContext({
    userId: user.id,
    userName: user.name,
    phone: user.phone,
  });
  const workDate = shanghaiDateString();
  let companyPay = 0;
  if (mealType && ['breakfast', 'lunch', 'dinner'].includes(mealType)) {
    const roster = overtimeRosterService.findMatchingRoster({
      workDate,
      mealType,
      userId: user.id,
      phone: empCtx.phone,
      employeeNo: empCtx.employeeNo,
      employeeName: empCtx.employeeName,
      department: empCtx.departmentName,
    });
    const used = overtimeMealUsageService.getActiveUsage({
      workDate,
      mealType,
      userId: user.id,
      phone: empCtx.phone,
    });
    if (roster && !used) {
      companyPay = Math.min(totalAmount, COMPANY_PAY_SUBSIDY_CAP);
    }
  }
  return Number((totalAmount - companyPay).toFixed(2));
}

export const couponController = {
  /** GET /api/merchant/coupons */
  listMerchantCoupons(req: Request, res: Response) {
    const user = ensureUser(req);
    const merchantId = resolveMerchantId(
      user,
      (req.query.merchantId as string) ?? undefined,
    );
    const rows = couponService.listByMerchant(merchantId);
    res.json({ data: rows.map(couponTemplateToDto) });
  },

  /** POST /api/merchant/coupons */
  createMerchantCoupon(req: Request, res: Response) {
    const user = ensureUser(req);
    const b = req.body ?? {};
    const merchantId = resolveMerchantId(user, b.merchantId as string);
    try {
      const input: CreateCouponTemplateInput = {
        name: String(b.name ?? ''),
        couponType: b.couponType ?? b.type ?? 'fixed',
        discountAmount: Number(b.discountAmount ?? 0),
        minOrderAmount: Number(b.minOrderAmount ?? 0),
        mealTypes: parseMealTypes(b.mealTypes),
        totalQuantity: Number(b.totalQuantity ?? 0),
        perUserLimit: Number(b.perUserLimit ?? 1),
        startAt: String(b.startAt ?? b.validFrom ?? new Date().toISOString()),
        endAt: String(
          b.endAt ??
            b.validTo ??
            new Date(Date.now() + 30 * 86400000).toISOString(),
        ),
      };
      const row = couponService.createTemplate(merchantId, input);
      res.json({ data: couponTemplateToDto(row) });
    } catch (e) {
      mapCouponError(e);
    }
  },

  /** PATCH /api/merchant/coupons/:id/status */
  setMerchantCouponStatus(req: Request, res: Response) {
    const user = ensureUser(req);
    const merchantId = resolveMerchantId(
      user,
      (req.body?.merchantId as string) ?? undefined,
    );
    const enabled = req.body?.enabled ?? req.body?.status === 'enabled';
    const status = enabled ? 'enabled' : 'disabled';
    try {
      const row = couponService.setTemplateStatus(
        req.params.id,
        status,
        merchantId,
      );
      res.json({ data: couponTemplateToDto(row) });
    } catch (e) {
      mapCouponError(e);
    }
  },

  /** GET /api/coupons/merchant/:merchantId */
  listForMerchantPublic(req: Request, res: Response) {
    const user = ensureUser(req);
    if (user.role !== 'employee') throw Forbidden('仅员工可领取优惠券');
    const merchantId = req.params.merchantId;
    if (!merchantService.getById(merchantId)) throw NotFound('商家不存在');
    const claimable = couponService.listClaimableForMerchant(merchantId, user.id);
    res.json({
      data: claimable.map((t) => ({
        ...couponTemplateToDto(t),
        userClaimedCount: t.userClaimedCount,
        canClaim: t.userClaimedCount < t.per_user_limit,
      })),
    });
  },

  /** POST /api/coupons/:id/claim — id 为 templateId */
  claim(req: Request, res: Response) {
    const user = ensureUser(req);
    if (user.role !== 'employee') throw Forbidden('仅员工可领取优惠券');
    try {
      const claim = couponService.claimTemplate(req.params.id, user.id);
      const template = couponService.getTemplate(claim.template_id);
      res.json({ data: couponClaimToDto(claim, template) });
    } catch (e) {
      mapCouponError(e);
    }
  },

  /** GET /api/coupons/my */
  listMy(req: Request, res: Response) {
    const user = ensureUser(req);
    if (user.role !== 'employee') throw Forbidden('仅员工可查看');
    const merchantId = req.query.merchantId as string | undefined;
    const claims = couponService.listMyClaims(user.id, merchantId);
    res.json({
      data: claims.map((c) => {
        const t = couponService.getTemplate(c.template_id);
        return couponClaimToDto(c, t);
      }),
    });
  },

  /** GET /api/coupons/best */
  findBest(req: Request, res: Response) {
    const user = ensureUser(req);
    if (user.role !== 'employee') throw Forbidden('仅员工可查询');
    const merchantId = String(req.query.merchantId ?? '');
    const mealType = req.query.mealType as MealType | undefined;
    const amount = Number(req.query.amount ?? 0);
    if (!merchantId) throw BadRequest('缺少 merchantId');
    if (!Number.isFinite(amount) || amount <= 0) {
      throw BadRequest('amount 无效');
    }
    const employeePayBeforeCoupon = previewEmployeePayBeforeCoupon(
      user,
      merchantId,
      mealType ?? null,
      amount,
    );
    const best = couponService.findBestClaim({
      userId: user.id,
      merchantId,
      mealType: mealType ?? null,
      totalAmount: amount,
      employeePayBeforeCoupon,
    });
    if (!best) {
      res.json({ data: null });
      return;
    }
    res.json({
      data: {
        claim: couponClaimToDto(best.claim, best.template),
        discountAmount: best.discountAmount,
        employeePayBeforeCoupon,
        employeePayAmount: Number(
          (employeePayBeforeCoupon - best.discountAmount).toFixed(2),
        ),
      },
    });
  },
};

export const couponAdminController = {
  list(req: Request, res: Response) {
    ensureUser(req);
    const merchantId = req.query.merchantId as string | undefined;
    const rows = couponService.listAll(merchantId);
    res.json({ data: rows.map(couponTemplateToDto) });
  },

  setStatus(req: Request, res: Response) {
    ensureUser(req);
    const enabled = req.body?.enabled ?? req.body?.status === 'enabled';
    const status = enabled ? 'enabled' : 'disabled';
    try {
      const row = couponService.setTemplateStatus(req.params.id, status);
      res.json({ data: couponTemplateToDto(row) });
    } catch (e) {
      mapCouponError(e);
    }
  },
};
