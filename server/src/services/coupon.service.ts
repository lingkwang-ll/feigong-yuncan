import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MealType } from '../models/types';

export type CouponType = 'fixed' | 'threshold' | 'newcomer';
export type CouponTemplateStatus = 'enabled' | 'disabled';
export type CouponClaimStatus = 'claimed' | 'used' | 'expired';

export interface CouponTemplateRow {
  id: string;
  merchant_id: string;
  name: string;
  coupon_type: CouponType;
  discount_amount: number;
  min_order_amount: number;
  meal_types_json: string;
  total_quantity: number;
  per_user_limit: number;
  claimed_count: number;
  used_count: number;
  start_at: string;
  end_at: string;
  status: CouponTemplateStatus;
  created_at: string;
  updated_at: string;
}

export interface CouponClaimRow {
  id: string;
  template_id: string;
  merchant_id: string;
  user_id: string;
  status: CouponClaimStatus;
  claimed_at: string;
  used_at: string | null;
  order_id: string | null;
}

export interface CreateCouponTemplateInput {
  name: string;
  couponType: CouponType;
  discountAmount: number;
  minOrderAmount?: number;
  mealTypes: MealType[];
  totalQuantity: number;
  perUserLimit?: number;
  startAt: string;
  endAt: string;
}

function parseMealTypes(raw: string | null): MealType[] {
  if (!raw) return ['breakfast', 'lunch', 'dinner'];
  try {
    const arr = JSON.parse(raw);
    return Array.isArray(arr) ? (arr as MealType[]) : [];
  } catch {
    return ['breakfast', 'lunch', 'dinner'];
  }
}

function isActiveNow(row: CouponTemplateRow, now = new Date()): boolean {
  if (row.status !== 'enabled') return false;
  const start = new Date(row.start_at);
  const end = new Date(row.end_at);
  return now >= start && now <= end;
}

export class CouponService {
  getTemplate(id: string): CouponTemplateRow | undefined {
    return getDb()
      .prepare<[string], CouponTemplateRow>(
        'SELECT * FROM coupon_templates WHERE id = ?',
      )
      .get(id);
  }

  listByMerchant(merchantId: string): CouponTemplateRow[] {
    return getDb()
      .prepare<[string], CouponTemplateRow>(
        `SELECT * FROM coupon_templates WHERE merchant_id = ?
           ORDER BY created_at DESC`,
      )
      .all(merchantId);
  }

  listAll(merchantId?: string): CouponTemplateRow[] {
    if (merchantId) return this.listByMerchant(merchantId);
    return getDb()
      .prepare<[], CouponTemplateRow>(
        `SELECT * FROM coupon_templates ORDER BY created_at DESC`,
      )
      .all();
  }

  createTemplate(
    merchantId: string,
    input: CreateCouponTemplateInput,
  ): CouponTemplateRow {
    const name = input.name.trim();
    if (!name) throw new Error('NAME_REQUIRED');
    const discount = Number(input.discountAmount);
    if (!(discount > 0)) throw new Error('INVALID_DISCOUNT');
    const minOrder = Number(input.minOrderAmount ?? 0);
    if (input.couponType === 'threshold' && minOrder <= 0) {
      throw new Error('MIN_ORDER_REQUIRED');
    }
    const totalQty = Math.floor(Number(input.totalQuantity));
    if (!(totalQty > 0)) throw new Error('INVALID_QUANTITY');
    const perUser = Math.max(1, Math.floor(Number(input.perUserLimit ?? 1)));
    const mealTypes = input.mealTypes.length
      ? input.mealTypes
      : (['breakfast', 'lunch', 'dinner'] as MealType[]);

    const id = `cpt_${nanoid(10)}`;
    const now = nowIso();
    getDb()
      .prepare(
        `INSERT INTO coupon_templates
           (id, merchant_id, name, coupon_type, discount_amount, min_order_amount,
            meal_types_json, total_quantity, per_user_limit, claimed_count, used_count,
            start_at, end_at, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, 'enabled', ?, ?)`,
      )
      .run(
        id,
        merchantId,
        name,
        input.couponType,
        discount,
        minOrder,
        JSON.stringify(mealTypes),
        totalQty,
        perUser,
        input.startAt,
        input.endAt,
        now,
        now,
      );
    return this.getTemplate(id)!;
  }

  setTemplateStatus(
    templateId: string,
    status: CouponTemplateStatus,
    merchantId?: string,
  ): CouponTemplateRow {
    const row = this.getTemplate(templateId);
    if (!row) throw new Error('COUPON_NOT_FOUND');
    if (merchantId && row.merchant_id !== merchantId) {
      throw new Error('FORBIDDEN');
    }
    const now = nowIso();
    getDb()
      .prepare(
        `UPDATE coupon_templates SET status = ?, updated_at = ? WHERE id = ?`,
      )
      .run(status, now, templateId);
    return this.getTemplate(templateId)!;
  }

  /** 员工可见：商家当前可领取的券模板 */
  listClaimableForMerchant(
    merchantId: string,
    userId: string,
  ): (CouponTemplateRow & { userClaimedCount: number })[] {
    const templates = this.listByMerchant(merchantId).filter((t) => isActiveNow(t));
    return templates
      .map((t) => {
        const userClaimed = getDb()
          .prepare<[string, string], { c: number }>(
            `SELECT COUNT(*) AS c FROM coupon_claims
               WHERE template_id = ? AND user_id = ?`,
          )
          .get(t.id, userId);
        return { ...t, userClaimedCount: userClaimed?.c ?? 0 };
      })
      .filter(
        (t) =>
          t.status === 'enabled' &&
          t.claimed_count < t.total_quantity &&
          t.userClaimedCount < t.per_user_limit,
      );
  }

  claimTemplate(templateId: string, userId: string): CouponClaimRow {
    const template = this.getTemplate(templateId);
    if (!template) throw new Error('COUPON_NOT_FOUND');
    if (!isActiveNow(template)) throw new Error('COUPON_EXPIRED');
    if (template.status !== 'enabled') throw new Error('COUPON_DISABLED');
    if (template.claimed_count >= template.total_quantity) {
      throw new Error('COUPON_SOLD_OUT');
    }

    const userCount = getDb()
      .prepare<[string, string], { c: number }>(
        `SELECT COUNT(*) AS c FROM coupon_claims
           WHERE template_id = ? AND user_id = ?`,
      )
      .get(templateId, userId);
    if ((userCount?.c ?? 0) >= template.per_user_limit) {
      throw new Error('CLAIM_LIMIT_REACHED');
    }

    const id = `ccl_${nanoid(10)}`;
    const now = nowIso();
    const db = getDb();
    const tx = db.transaction(() => {
      db.prepare(
        `INSERT INTO coupon_claims
           (id, template_id, merchant_id, user_id, status, claimed_at, used_at, order_id)
         VALUES (?, ?, ?, ?, 'claimed', ?, NULL, NULL)`,
      ).run(id, templateId, template.merchant_id, userId, now);
      db.prepare(
        `UPDATE coupon_templates
            SET claimed_count = claimed_count + 1, updated_at = ?
          WHERE id = ?`,
      ).run(now, templateId);
    });
    tx();
    return db
      .prepare<[string], CouponClaimRow>(
        'SELECT * FROM coupon_claims WHERE id = ?',
      )
      .get(id)!;
  }

  listMyClaims(userId: string, merchantId?: string): CouponClaimRow[] {
    if (merchantId) {
      return getDb()
        .prepare<[string, string], CouponClaimRow>(
          `SELECT * FROM coupon_claims
             WHERE user_id = ? AND merchant_id = ?
             ORDER BY claimed_at DESC`,
        )
        .all(userId, merchantId);
    }
    return getDb()
      .prepare<[string], CouponClaimRow>(
        `SELECT * FROM coupon_claims WHERE user_id = ? ORDER BY claimed_at DESC`,
      )
      .all(userId);
  }

  getClaim(id: string): CouponClaimRow | undefined {
    return getDb()
      .prepare<[string], CouponClaimRow>(
        'SELECT * FROM coupon_claims WHERE id = ?',
      )
      .get(id);
  }

  hasCompletedOrderAtMerchant(userId: string, merchantId: string): boolean {
    const row = getDb()
      .prepare<[string, string], { c: number }>(
        `SELECT COUNT(*) AS c FROM orders
           WHERE user_id = ? AND merchant_id = ?
             AND status NOT IN ('cancelled')`,
      )
      .get(userId, merchantId);
    return (row?.c ?? 0) > 0;
  }

  /** 校验 claim 是否可用于下单（不写库） */
  validateClaimForOrder(input: {
    claimId: string;
    userId: string;
    merchantId: string;
    mealType: MealType | null;
    totalAmount: number;
    employeePayBeforeCoupon: number;
  }): { discountAmount: number; template: CouponTemplateRow; claim: CouponClaimRow } {
    const claim = this.getClaim(input.claimId);
    if (!claim) throw new Error('CLAIM_NOT_FOUND');
    if (claim.user_id !== input.userId) throw new Error('FORBIDDEN');
    if (claim.merchant_id !== input.merchantId) throw new Error('MERCHANT_MISMATCH');
    if (claim.status !== 'claimed') throw new Error('COUPON_ALREADY_USED');

    const template = this.getTemplate(claim.template_id);
    if (!template) throw new Error('COUPON_NOT_FOUND');
    if (!isActiveNow(template)) throw new Error('COUPON_EXPIRED');
    if (template.status !== 'enabled') throw new Error('COUPON_DISABLED');

    const mealTypes = parseMealTypes(template.meal_types_json);
    if (input.mealType && mealTypes.length && !mealTypes.includes(input.mealType)) {
      throw new Error('MEAL_TYPE_NOT_APPLICABLE');
    }

    if (template.coupon_type === 'threshold') {
      if (input.totalAmount < template.min_order_amount) {
        throw new Error('THRESHOLD_NOT_MET');
      }
    }

    if (template.coupon_type === 'newcomer') {
      if (this.hasCompletedOrderAtMerchant(input.userId, input.merchantId)) {
        throw new Error('NEWCOMER_NOT_ELIGIBLE');
      }
    }

    if (input.employeePayBeforeCoupon <= 0) {
      throw new Error('NO_EMPLOYEE_PAY_TO_DISCOUNT');
    }

    const discountAmount = Number(
      Math.min(template.discount_amount, input.employeePayBeforeCoupon).toFixed(2),
    );
    if (discountAmount <= 0) throw new Error('NO_DISCOUNT_APPLICABLE');

    return { discountAmount, template, claim };
  }

  /** 下单时应用优惠券（事务内调用） */
  markClaimUsed(input: {
    claimId: string;
    orderId: string;
    userId: string;
    discountAmount: number;
  }): void {
    const now = nowIso();
    const db = getDb();
    const claim = this.getClaim(input.claimId);
    if (!claim || claim.status !== 'claimed') {
      throw new Error('COUPON_ALREADY_USED');
    }
    db.prepare(
      `UPDATE coupon_claims
          SET status = 'used', used_at = ?, order_id = ?
        WHERE id = ? AND status = 'claimed'`,
    ).run(now, input.orderId, input.claimId);
    db.prepare(
      `UPDATE coupon_templates
          SET used_count = used_count + 1, updated_at = ?
        WHERE id = ?`,
    ).run(now, claim.template_id);
    db.prepare(
      `INSERT INTO coupon_usages
         (id, claim_id, template_id, merchant_id, user_id, order_id, discount_amount, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      `cus_${nanoid(10)}`,
      input.claimId,
      claim.template_id,
      claim.merchant_id,
      input.userId,
      input.orderId,
      input.discountAmount,
      now,
    );
  }

  /** 自动选最优可用 claim */
  findBestClaim(input: {
    userId: string;
    merchantId: string;
    mealType: MealType | null;
    totalAmount: number;
    employeePayBeforeCoupon: number;
  }): {
    claim: CouponClaimRow;
    template: CouponTemplateRow;
    discountAmount: number;
  } | null {
    if (input.employeePayBeforeCoupon <= 0) return null;
    const claims = getDb()
      .prepare<[string, string], CouponClaimRow>(
        `SELECT * FROM coupon_claims
           WHERE user_id = ? AND merchant_id = ? AND status = 'claimed'
           ORDER BY claimed_at ASC`,
      )
      .all(input.userId, input.merchantId);

    let best: {
      claim: CouponClaimRow;
      template: CouponTemplateRow;
      discountAmount: number;
    } | null = null;

    for (const claim of claims) {
      try {
        const v = this.validateClaimForOrder({
          claimId: claim.id,
          userId: input.userId,
          merchantId: input.merchantId,
          mealType: input.mealType,
          totalAmount: input.totalAmount,
          employeePayBeforeCoupon: input.employeePayBeforeCoupon,
        });
        if (!best || v.discountAmount > best.discountAmount) {
          best = {
            claim,
            template: v.template,
            discountAmount: v.discountAmount,
          };
        }
      } catch {
        // skip invalid claim
      }
    }
    return best;
  }

  merchantHasActiveCoupons(merchantId: string): boolean {
    const rows = this.listByMerchant(merchantId);
    return rows.some((t) => t.status === 'enabled' && isActiveNow(t));
  }
}

export const couponService = new CouponService();

export function couponTemplateToDto(row: CouponTemplateRow) {
  return {
    id: row.id,
    merchantId: row.merchant_id,
    name: row.name,
    couponType: row.coupon_type,
    discountAmount: row.discount_amount,
    minOrderAmount: row.min_order_amount,
    mealTypes: parseMealTypes(row.meal_types_json),
    totalQuantity: row.total_quantity,
    perUserLimit: row.per_user_limit,
    claimedCount: row.claimed_count,
    usedCount: row.used_count,
    startAt: row.start_at,
    endAt: row.end_at,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function couponClaimToDto(
  row: CouponClaimRow,
  template?: CouponTemplateRow,
) {
  return {
    id: row.id,
    templateId: row.template_id,
    merchantId: row.merchant_id,
    userId: row.user_id,
    status: row.status,
    claimedAt: row.claimed_at,
    usedAt: row.used_at,
    orderId: row.order_id,
    template: template ? couponTemplateToDto(template) : undefined,
  };
}
