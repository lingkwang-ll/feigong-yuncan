import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { orderService, CreateOrderInput } from '../services/order.service';
import { overtimeRosterService, parseRosterMealType } from '../services/overtime-roster.service';
import { overtimeMealUsageService } from '../services/overtime-meal-usage.service';
import { resolveEmployeeContext } from '../utils/employee-context.util';
import { shanghaiDateString } from '../utils/date.util';
import { COMPANY_PAY_SUBSIDY_CAP } from '../constants/company-pay.constants';
import { isMealDeadlinePassed } from '../utils/meal-deadline.util';
import {
  ALL_MEAL_TYPES,
  ALL_ORDER_STATUSES,
  ALL_PAYMENT_TYPES,
  DeliveryType,
  MealType,
  OrderStatus,
  PaymentType,
} from '../models/types';
import {
  assertMerchantAccess,
  assertOrderAccess,
  resolveAdminScope,
} from '../utils/company-scope.util';

function isMealType(v: unknown): v is MealType {
  return typeof v === 'string' && ALL_MEAL_TYPES.includes(v as MealType);
}

function parseDeliveryType(v: unknown): DeliveryType {
  if (v === 'delivery' || v === 'selfPickup') return v;
  throw BadRequest('deliveryType 非法');
}

function parseStatus(v: unknown): OrderStatus {
  if (typeof v === 'string' && ALL_ORDER_STATUSES.includes(v as OrderStatus)) {
    return v as OrderStatus;
  }
  throw BadRequest('status 非法');
}

function parsePaymentType(v: unknown): PaymentType | undefined {
  if (typeof v === 'string' && ALL_PAYMENT_TYPES.includes(v as PaymentType)) {
    return v as PaymentType;
  }
  return undefined;
}

function parseMealType(v: unknown): MealType | undefined {
  if (typeof v === 'string' && ALL_MEAL_TYPES.includes(v as MealType)) {
    return v as MealType;
  }
  return undefined;
}

/**
 * Flutter 端 Order.toJson 的 items 结构是：
 *   items: [{ dish: {...DishDto...}, quantity }]
 * 同时为了灵活也支持平铺的 items：
 *   items: [{ dishName, price, quantity, ... }]
 */
function parsePackageOrder(
  raw: unknown,
): CreateOrderInput['packageOrder'] | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'object') throw BadRequest('packageOrder 非法');
  const obj = raw as Record<string, unknown>;
  const packageId = typeof obj.packageId === 'string' ? obj.packageId : '';
  if (!packageId) throw BadRequest('packageOrder.packageId 不能为空');
  const selectedDishIds = Array.isArray(obj.selectedDishIds)
    ? obj.selectedDishIds.filter((s): s is string => typeof s === 'string')
    : [];
  const extrasRaw = Array.isArray(obj.extras) ? obj.extras : [];
  const extras = extrasRaw.map((x, idx) => {
    if (!x || typeof x !== 'object') {
      throw BadRequest(`packageOrder.extras[${idx}] 非法`);
    }
    const e = x as Record<string, unknown>;
    const dishId = typeof e.dishId === 'string' ? e.dishId : '';
    const quantity = Number(e.quantity ?? 1);
    if (!dishId) throw BadRequest(`packageOrder.extras[${idx}].dishId 非法`);
    if (!Number.isFinite(quantity) || quantity < 1) {
      throw BadRequest(`packageOrder.extras[${idx}].quantity 非法`);
    }
    return { dishId, quantity: Math.floor(quantity) };
  });
  return { packageId, selectedDishIds, extras };
}

function normalizeItems(raw: unknown): CreateOrderInput['items'] {
  if (!Array.isArray(raw)) throw BadRequest('items 必须是数组');
  return raw.map((it, idx) => {
    if (!it || typeof it !== 'object') {
      throw BadRequest(`items[${idx}] 非法`);
    }
    const obj = it as Record<string, unknown>;
    // 兼容两种结构
    if (obj.dish && typeof obj.dish === 'object') {
      const d = obj.dish as Record<string, unknown>;
      const price = Number(d.price);
      const quantity = Number(obj.quantity ?? 1);
      if (!Number.isFinite(price)) throw BadRequest(`items[${idx}].price 非法`);
      if (!Number.isFinite(quantity) || quantity <= 0) {
        throw BadRequest(`items[${idx}].quantity 非法`);
      }
      return {
        dishId: (d.id as string) || undefined,
        dishName: String(d.name ?? ''),
        dishImageUrl: (d.image as string) || undefined,
        dishDescription: (d.description as string) || '',
        mealType: isMealType(d.mealType) ? d.mealType : undefined,
        price,
        quantity,
      };
    }
    const price = Number(obj.price);
    const quantity = Number(obj.quantity ?? 1);
    if (!Number.isFinite(price)) throw BadRequest(`items[${idx}].price 非法`);
    if (!Number.isFinite(quantity) || quantity <= 0) {
      throw BadRequest(`items[${idx}].quantity 非法`);
    }
    return {
      dishId: (obj.dishId as string) || undefined,
      dishName: String(obj.dishName ?? ''),
      dishImageUrl: (obj.dishImageUrl as string) || undefined,
      dishDescription: (obj.dishDescription as string) || '',
      mealType: isMealType(obj.mealType) ? obj.mealType : undefined,
      price,
      quantity,
    };
  });
}

/**
 * 员工只允许把自己下的订单切到这些状态
 * （取消 / 完成确认；不允许把订单改为已接单 / 配送中等商家侧状态）
 */
const EMPLOYEE_ALLOWED_NEXT_STATUS: ReadonlySet<OrderStatus> = new Set([
  'cancelled',
  'completed',
]);

export const orderController = {
  create(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const b = req.body ?? {};
    // createdAt 由服务端写入，忽略客户端传入
    if (b.createdAt !== undefined) delete b.createdAt;

    const merchantId = b.merchantId;
    const merchantName = b.merchantName;
    if (!merchantId) throw BadRequest('缺少 merchantId');
    if (!merchantName) throw BadRequest('缺少 merchantName');

    const goodsAmount = Number(b.goodsAmount ?? 0);
    const deliveryFee = Number(b.deliveryFee ?? 0);
    const totalAmount = Number(b.totalAmount ?? 0);
    if (!Number.isFinite(goodsAmount) || !Number.isFinite(totalAmount)) {
      throw BadRequest('金额字段非法');
    }

    // ===== 套餐下单分支（packageOrder 存在则走服务端重算） =====
    const packageOrder = parsePackageOrder(b.packageOrder);
    let items: CreateOrderInput['items'];
    if (packageOrder) {
      // 套餐订单不强制要求前端 items；后端会按规则生成 order_items
      items = [];
    } else {
      items = normalizeItems(b.items);
      if (items.length === 0) throw BadRequest('items 不能为空');
    }

    const scope = resolveAdminScope(req.user);
    // 强制使用登录身份，避免前端伪造 userId 给别人下单
    let effectiveUserId: string = req.user.id;
    let effectiveUserName: string = req.user.name;
    let effectiveCompanyId: string | undefined = req.user.company_id ?? undefined;

    if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
      // 后台代下单：允许显式传入下单人 userId
      if (b.userId && typeof b.userId === 'string') {
        effectiveUserId = b.userId;
        effectiveUserName = (b.customerName ?? b.userName ?? req.user.name) as string;
      }
      if (b.companyId && typeof b.companyId === 'string') {
        effectiveCompanyId = b.companyId;
      }
    } else if (scope.isMerchant) {
      // 商家不允许通过该接口下单
      throw Forbidden('商家账号不能通过此接口下单');
    }

    try {
      const result = orderService.create({
        userId: effectiveUserId,
        userName: effectiveUserName,
        userCompany: b.customerCompany ?? b.userCompany ?? '',
        companyId: effectiveCompanyId,
        merchantId,
        merchantName,
        deliveryType: parseDeliveryType(b.deliveryType),
        address: b.address ?? '',
        phone: b.phone ?? '',
        remark: b.remark ?? '',
        isMealCollector: !!b.isMealCollector,
        collectorName: b.collectorName ?? '',
        collectorPhone: b.collectorPhone ?? '',
        collectorAddress: b.collectorAddress ?? '',
        collectorLatitude:
          b.collectorLatitude != null ? Number(b.collectorLatitude) : null,
        collectorLongitude:
          b.collectorLongitude != null ? Number(b.collectorLongitude) : null,
        collectorPoiName: b.collectorPoiName ?? '',
        collectorAddressText: b.collectorAddressText ?? '',
        goodsAmount,
        deliveryFee,
        totalAmount,
        paymentType: parsePaymentType(b.paymentType),
        orderMealType: parseMealType(b.mealType ?? b.orderMealType),
        paymentScreenshot: b.paymentScreenshot ?? null,
        items,
        packageOrder: packageOrder ?? undefined,
        couponClaimId:
          typeof b.couponClaimId === 'string' ? b.couponClaimId : null,
      });
      res.json({ data: orderService.toDisplayDto(result.order) });
    } catch (e) {
      const code = (e as Error).message;
      if (code.startsWith('MEAL_DEADLINE_PASSED:')) {
        throw BadRequest('已超过该餐段下单截止时间', 'MEAL_DEADLINE_PASSED');
      }
      if (code === 'EMPTY_ITEMS') throw BadRequest('items 不能为空');
      // ----- 套餐下单专属错误码 -----
      if (code === 'PACKAGE_NOT_FOUND') throw NotFound('套餐不存在');
      if (code === 'PACKAGE_MERCHANT_MISMATCH')
        throw BadRequest('套餐不属于该商家', 'PACKAGE_MERCHANT_MISMATCH');
      if (code === 'PACKAGE_DISABLED')
        throw BadRequest('套餐已停用', 'PACKAGE_DISABLED');
      if (code === 'PACKAGE_RULE_COUNT_MISMATCH')
        throw BadRequest(
          '所选菜品总数与套餐规则不符',
          'PACKAGE_RULE_COUNT_MISMATCH',
        );
      if (code.startsWith('PACKAGE_RULE_MISMATCH:')) {
        const cat = code.split(':')[1] ?? '';
        throw BadRequest(
          `所选 ${cat} 数量与套餐规则不符`,
          'PACKAGE_RULE_MISMATCH',
        );
      }
      if (code === 'DISH_NOT_FOUND') throw BadRequest('菜品不存在', 'DISH_NOT_FOUND');
      if (code === 'DISH_MERCHANT_MISMATCH')
        throw BadRequest('菜品不属于该商家', 'DISH_MERCHANT_MISMATCH');
      if (code === 'DISH_UNAVAILABLE')
        throw BadRequest('菜品已下架', 'DISH_UNAVAILABLE');
      if (code === 'DISH_CATEGORY_INVALID')
        throw BadRequest('菜品分类非法，套餐只能选荤菜或素菜');
      if (code === 'INVALID_EXTRA_ITEM') throw BadRequest('加菜项非法');
      if (code === 'EXTRA_DISH_NOT_FOUND') throw BadRequest('加菜不存在');
      if (code === 'EXTRA_DISH_MERCHANT_MISMATCH')
        throw BadRequest('加菜不属于该商家');
      if (code === 'EXTRA_DISH_UNAVAILABLE') throw BadRequest('加菜已下架');
      if (code === 'EXTRA_DISH_CATEGORY_INVALID')
        throw BadRequest('加菜分类必须为 extra');
      if (code === 'EXTRA_DISH_NOT_ALLOWED')
        throw BadRequest('该加菜不在套餐允许范围内');
      if (code === 'COUPON_NOT_FOUND') throw BadRequest('优惠券不存在', 'COUPON_NOT_FOUND');
      if (code === 'COUPON_EXPIRED') throw BadRequest('优惠券已过期', 'COUPON_EXPIRED');
      if (code === 'COUPON_DISABLED') throw BadRequest('优惠券已停用', 'COUPON_DISABLED');
      if (code === 'COUPON_ALREADY_USED')
        throw BadRequest('优惠券已使用', 'COUPON_ALREADY_USED');
      if (code === 'CLAIM_NOT_FOUND') throw BadRequest('优惠券领取记录不存在', 'CLAIM_NOT_FOUND');
      if (code === 'THRESHOLD_NOT_MET')
        throw BadRequest('未满足使用门槛', 'THRESHOLD_NOT_MET');
      if (code === 'NEWCOMER_NOT_ELIGIBLE')
        throw BadRequest('新人券仅限首次下单', 'NEWCOMER_NOT_ELIGIBLE');
      if (code === 'MEAL_TYPE_NOT_APPLICABLE')
        throw BadRequest('当前餐段不可用', 'MEAL_TYPE_NOT_APPLICABLE');
      if (code === 'NO_EMPLOYEE_PAY_TO_DISCOUNT')
        throw BadRequest('无可抵扣的员工自付金额', 'NO_EMPLOYEE_PAY_TO_DISCOUNT');
      if (code === 'FORBIDDEN') throw Forbidden('无权使用该优惠券');
      if (code === 'MERCHANT_MISMATCH')
        throw BadRequest('优惠券商家不匹配', 'MERCHANT_MISMATCH');
      throw e;
    }
  },

  listMy(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    // 强制只能查自己的，不再相信前端传的 userId
    const userId = req.user.id;
    const orders = orderService.listByUser(userId);
    const list = orders.map((o) =>
      orderService.toDisplayDto(o),
    );
    res.json({ data: list });
  },

  listMerchant(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const user = req.user;
    const scope = resolveAdminScope(user);
    const requested = req.query.merchantId as string | undefined;

    if (user.role === 'employee') {
      throw Forbidden('员工不可访问商家订单接口');
    }

    if (scope.isMerchant) {
      if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
      if (requested && requested !== scope.merchantId) {
        throw Forbidden('无权查看其它商家的订单');
      }
      const orders = orderService.listByMerchant(scope.merchantId);
      res.json({
        data: orders.map((o) =>
          orderService.toDisplayDto(o),
        ),
      });
      return;
    }

    if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
      let orders;
      if (requested) {
        try {
          assertMerchantAccess(user, requested);
        } catch (e) {
          if ((e as Error).message === 'FORBIDDEN') {
            throw Forbidden('无权查看该商家的订单');
          }
          throw e;
        }
        orders = orderService.listByMerchant(requested);
      } else if (scope.isPlatformAdmin) {
        orders = orderService.listAll();
      } else {
        // company_admin 不指定 merchantId → 只返回本企业的订单
        orders = orderService
          .listAll()
          .filter((o) => o.company_id === scope.companyId);
      }
      res.json({
        data: orders.map((o) =>
          orderService.toDisplayDto(o),
        ),
      });
      return;
    }

    throw Forbidden('当前角色无权访问商家订单');
  },

  updateStatus(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const orderId = req.params.orderId;
    const status = parseStatus(req.body?.status);
    const rejectReason =
      typeof req.body?.rejectReason === 'string'
        ? req.body.rejectReason
        : null;

    const existing = orderService.getById(orderId);
    if (!existing) throw NotFound('订单不存在');

    try {
      assertOrderAccess(req.user, existing);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') {
        throw Forbidden('无权操作该订单');
      }
      throw e;
    }

    // 员工只允许取消 / 确认完成自己的订单，其它状态留给商家 / 管理员
    if (req.user.role === 'employee' && !EMPLOYEE_ALLOWED_NEXT_STATUS.has(status)) {
      throw Forbidden('员工不能将订单切换到该状态');
    }

    try {
      const order = orderService.updateStatus(
        orderId,
        status,
        rejectReason,
        req.user.role,
      );
      res.json({
        data: orderService.toDisplayDto(order),
      });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('订单不存在');
      if (msg === 'CANCEL_NOT_ALLOWED') {
        throw BadRequest('系统已关闭取消订单', 'CANCEL_NOT_ALLOWED');
      }
      if (msg === 'PAYMENT_SCREENSHOT_REQUIRED') {
        throw BadRequest('请先上传付款截图', 'PAYMENT_SCREENSHOT_REQUIRED');
      }
      if (msg === 'INVALID_STATUS_TRANSITION') {
        throw BadRequest('不允许的状态流转', 'INVALID_STATUS_TRANSITION');
      }
      if (msg === 'PAYMENT_FLOW_INCOMPLETE') {
        throw BadRequest('请先完成支付流程', 'PAYMENT_FLOW_INCOMPLETE');
      }
      if (msg === 'EMPLOYEE_STATUS_FORBIDDEN') {
        throw Forbidden('员工不能将订单切换到该状态');
      }
      if (msg === 'EMPLOYEE_COMPLETE_FORBIDDEN') {
        throw BadRequest('订单尚未接单，无法确认完成', 'EMPLOYEE_COMPLETE_FORBIDDEN');
      }
      throw e;
    }
  },

  companyPayEligibility(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    if (req.user.role !== 'employee') {
      throw Forbidden('仅员工可查询企业代付资格');
    }
    const mealTypeRaw = (req.query.mealType as string | undefined)?.trim() ?? 'lunch';
    const mealType = parseRosterMealType(mealTypeRaw) ?? (mealTypeRaw as MealType);
    const rosterMeals: MealType[] = ['breakfast', 'lunch', 'dinner'];
    if (!rosterMeals.includes(mealType)) {
      throw BadRequest('mealType 非法');
    }

    const ctx = resolveEmployeeContext({
      userId: req.user.id,
      userName: req.user.name,
      phone: req.user.phone,
    });
    const workDate = shanghaiDateString();
    const onRoster = overtimeRosterService.isOnRoster({
      workDate,
      mealType,
      userId: req.user.id,
      phone: ctx.phone,
      employeeNo: ctx.employeeNo,
      employeeName: ctx.employeeName,
      department: ctx.departmentName,
    });
    const companyPayUsed = overtimeMealUsageService.hasUsedCompanyPay({
      workDate,
      mealType,
      userId: req.user.id,
      phone: ctx.phone,
    });
    const mealClosed = isMealDeadlinePassed(mealType, null);

    let reason = 'available';
    let hint = `名单内员工 · 每人当天该餐段限用一次，最多补贴 ¥${COMPANY_PAY_SUBSIDY_CAP}`;
    let eligible = false;

    if (!onRoster) {
      reason = 'not_on_roster';
      hint = '未在名单中，需自费';
    } else if (companyPayUsed) {
      reason = 'already_used';
      hint = '今日该餐段企业代付已使用，需自费';
    } else if (mealClosed) {
      reason = 'closed';
      hint = '当前餐段未开放';
    } else {
      eligible = true;
    }

    res.json({
      data: {
        mealType,
        eligible,
        onRoster,
        companyPayUsed,
        mealClosed,
        reason,
        hint,
      },
    });
  },

  /** @deprecated 员工端不再展示加班餐 Tab，保留兼容 */
  overtimeEligibility(req: Request, res: Response) {
    res.json({
      data: {
        showOvertimeTab: false,
        onRoster: false,
        companyPayUsed: false,
        mealClosed: true,
        reason: 'deprecated',
        hint: '请选择早餐/中餐/晚餐',
      },
    });
  },
};
