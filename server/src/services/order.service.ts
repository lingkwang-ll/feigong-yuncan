import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import {
  normalizeDishCategory,
  nowIso,
  orderToDto,
  parsePackageRules,
} from '../models/mappers';
import {
  ALL_ORDER_STATUSES,
  DeliveryType,
  DishCategory,
  DishRow,
  MealType,
  OrderDto,
  OrderExtraItemDto,
  OrderItemRow,
  OrderRow,
  OrderSelectedItemDto,
  OrderStatus,
  PackageRow,
  PackageRules,
  PaymentType,
} from '../models/types';
import { DEFAULT_COMPANY_ID } from '../utils/company-scope.util';
import {
  isCorruptDisplayText,
  resolveMerchantDisplayName,
} from '../utils/display-text.util';
import { conversationService } from './conversation.service';
import { merchantService } from './merchant.service';
import { orderPolicyService } from './order-policy.service';
import { packageService } from './package.service';
import { settlementService } from './settlement.service';
import { overtimeMealUsageService } from './overtime-meal-usage.service';
import { overtimeRosterService } from './overtime-roster.service';
import { shanghaiDateString } from '../utils/date.util';
import {
  isCorruptEmployeeText,
  resolveEmployeeContext,
} from '../utils/employee-context.util';
import { couponService } from './coupon.service';

export interface OrderItemInput {
  dishId?: string;
  dishName: string;
  dishImageUrl?: string;
  dishDescription?: string;
  mealType?: MealType;
  price: number;
  quantity: number;
}

export interface PackageOrderInput {
  packageId: string;
  /** 所选普通菜品 ID（按套餐规则要求，按分类各选若干） */
  selectedDishIds: string[];
  /** 加菜：[{ dishId, quantity }]，quantity>=1 */
  extras: { dishId: string; quantity: number }[];
}

export interface CreateOrderInput {
  companyId?: string;
  userId?: string;
  userName?: string;
  userCompany?: string;
  merchantId: string;
  merchantName: string;
  deliveryType: DeliveryType;
  address?: string;
  phone?: string;
  remark?: string;
  goodsAmount: number;
  deliveryFee: number;
  totalAmount: number;
  /** 客户端可传 paymentType 提示，服务端会二次校验 */
  paymentType?: PaymentType;
  /** 套餐/订单所属餐段（用于企业代付判定） */
  orderMealType?: MealType;
  paymentScreenshot?: string | null;
  isMealCollector?: boolean;
  collectorName?: string;
  collectorPhone?: string;
  collectorAddress?: string;
  collectorLatitude?: number | null;
  collectorLongitude?: number | null;
  collectorPoiName?: string;
  collectorAddressText?: string;
  /** 普通菜品下单（旧路径） */
  items: OrderItemInput[];
  /** 套餐下单（新路径，可选）。传入则后端忽略 items / goodsAmount / totalAmount，按套餐规则重算。 */
  packageOrder?: PackageOrderInput;
  /** 员工已领取的优惠券 claim ID；不传或 null 表示不使用 */
  couponClaimId?: string | null;
}

/** 套餐下单服务端计算结果 */
interface PackageOrderComputed {
  pkg: PackageRow;
  rules: PackageRules;
  selectedDishes: DishRow[];
  selectedItems: OrderSelectedItemDto[];
  extras: { dish: DishRow; quantity: number; subtotal: number }[];
  extraItems: OrderExtraItemDto[];
  extraAmount: number;
  finalAmount: number;
  /** 转换为 order_items 行（向 order_items 表落库，保持兼容旧查询） */
  itemRows: OrderItemInput[];
}

function genOrderNo(db: ReturnType<typeof getDb>): string {
  const d = new Date();
  const pad = (n: number, w = 2) => String(n).padStart(w, '0');
  const datePrefix =
    d.getFullYear().toString() +
    pad(d.getMonth() + 1) +
    pad(d.getDate());
  const exists = db.prepare<[string], { c: number }>(
    'SELECT COUNT(*) AS c FROM orders WHERE order_no = ?',
  );
  for (let attempt = 0; attempt < 50; attempt++) {
    const rnd = String(Math.floor(Math.random() * 1000)).padStart(3, '0');
    const orderNo = `${datePrefix}${rnd}`;
    const row = exists.get(orderNo);
    if (!row || row.c === 0) return orderNo;
  }
  throw new Error('ORDER_NO_GENERATION_FAILED');
}

export class OrderService {
  create(input: CreateOrderInput): { order: OrderRow; items: OrderItemRow[] } {
    const db = getDb();
    const id = `O${nanoid(10)}`;
    const orderNo = genOrderNo(db);
    const now = nowIso();
    const companyId =
      input.companyId ??
      getDb()
        .prepare<[string], { company_id: string | null }>(
          'SELECT company_id FROM merchants WHERE id = ?',
        )
        .get(input.merchantId)?.company_id ??
      DEFAULT_COMPANY_ID;

    // ===== 套餐下单：服务端重算价格 & 校验规则 =====
    let pkgResult: PackageOrderComputed | null = null;
    let itemsToInsert: OrderItemInput[];
    let goodsAmount: number;
    let totalAmount: number;
    let packageId: string | null = null;
    let packageName: string | null = null;
    let packageBasePrice = 0;
    let selectedItemsJson = '[]';
    let extraItemsJson = '[]';
    let extraAmount = 0;
    let finalAmount = 0;
    let packageAmount = 0;

    if (input.packageOrder) {
      pkgResult = this.computePackageOrder(input.merchantId, input.packageOrder);
      itemsToInsert = pkgResult.itemRows;
      // 服务端权威金额：套餐订单 = 套餐基础价 + 加菜价格之和（不信任任何前端金额字段）
      // deliveryFee 暂统一为 0，避免前端伪造，等后续接入运费策略再统一计算
      goodsAmount = pkgResult.finalAmount;
      totalAmount = pkgResult.finalAmount;
      packageId = pkgResult.pkg.id;
      packageName = pkgResult.pkg.name;
      packageBasePrice = pkgResult.pkg.base_price;
      selectedItemsJson = JSON.stringify(pkgResult.selectedItems);
      extraItemsJson = JSON.stringify(pkgResult.extraItems);
      extraAmount = pkgResult.extraAmount;
      finalAmount = pkgResult.finalAmount;
      packageAmount = packageBasePrice;
    } else {
      itemsToInsert = input.items;
      if (itemsToInsert.length === 0) {
        throw new Error('EMPTY_ITEMS');
      }
      goodsAmount = input.goodsAmount;
      totalAmount = input.totalAmount;
      finalAmount = input.goodsAmount;
      packageAmount = input.goodsAmount;
      extraAmount = 0;
    }

    orderPolicyService.assertCreateAllowed(itemsToInsert, input.merchantId);

    const empCtx = resolveEmployeeContext({
      userId: input.userId,
      userName: input.userName,
      phone: input.phone,
      userCompany: input.userCompany,
    });
    const departmentName = empCtx.departmentName;
    const userPhone = empCtx.phone;

    const orderMealType =
      input.orderMealType ??
      itemsToInsert.find((i) => i.mealType)?.mealType ??
      null;

    const payment = orderPolicyService.resolvePaymentSplit({
      orderMealType,
      userId: input.userId,
      userName: isCorruptEmployeeText(input.userName)
        ? empCtx.employeeName
        : (input.userName ?? empCtx.employeeName),
      userPhone,
      employeeNo: empCtx.employeeNo,
      departmentName,
      packageAmount,
      extraAmount,
    });

    const companyPayAmount = payment.companyPayAmount;
    const employeePayBeforeCoupon = payment.employeePayAmount;
    let couponDiscountAmount = 0;
    let couponClaimId: string | null = null;

    if (input.couponClaimId && input.userId) {
      const applied = couponService.validateClaimForOrder({
        claimId: input.couponClaimId,
        userId: input.userId,
        merchantId: input.merchantId,
        mealType: orderMealType,
        totalAmount: payment.totalAmount,
        employeePayBeforeCoupon,
      });
      couponDiscountAmount = applied.discountAmount;
      couponClaimId = applied.claim.id;
    }

    const employeePayAmount = Number(
      (employeePayBeforeCoupon - couponDiscountAmount).toFixed(2),
    );

    let paymentType: PaymentType = payment.paymentType;
    if (companyPayAmount > 0 && employeePayAmount <= 0) {
      paymentType = 'company_pay';
    } else if (companyPayAmount > 0 && employeePayAmount > 0) {
      paymentType = 'mixed_pay';
    } else {
      paymentType = 'self_pay';
    }

    const status: OrderStatus =
      employeePayAmount <= 0 ? 'pendingMerchantConfirm' : 'pendingPayment';

    goodsAmount = payment.totalAmount;
    totalAmount = payment.totalAmount;
    finalAmount = payment.totalAmount;
    extraAmount = payment.extraAmount;
    packageAmount = payment.packageAmount;
    const settlementStatus =
      settlementService.initialSettlementStatus(employeePayAmount);
    const paymentChannel = 'manual_qr';

    const merchantRow = merchantService.getById(input.merchantId);
    const storedMerchantName = resolveMerchantDisplayName(
      input.merchantName,
      merchantRow?.name,
    );

    const tx = db.transaction(() => {
      db.prepare(
        `INSERT INTO orders
           (id, order_no, company_id, user_id, user_name, user_company,
            merchant_id, merchant_name, delivery_type,
            address, phone, remark,
            goods_amount, delivery_fee, total_amount,
            status, payment_type, payment_screenshot_url,
            is_meal_collector, collector_name, collector_phone, collector_address,
            collector_latitude, collector_longitude, collector_poi_name, collector_address_text,
            package_id, package_name, package_base_price,
            selected_items_json, extra_items_json, extra_amount, final_amount,
            package_amount, company_pay_amount, employee_pay_amount,
            coupon_claim_id, coupon_discount_amount, employee_pay_before_coupon,
            settlement_status, payment_channel,
            created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        id,
        orderNo,
        companyId,
        input.userId ?? null,
        input.userName ?? null,
        input.userCompany ?? null,
        input.merchantId,
        storedMerchantName,
        input.deliveryType,
        input.address ?? null,
        input.phone ?? null,
        input.remark ?? null,
        goodsAmount,
        input.packageOrder ? 0 : input.deliveryFee,
        totalAmount,
        status,
        paymentType,
        employeePayAmount <= 0 ? null : input.paymentScreenshot ?? null,
        input.isMealCollector ? 1 : 0,
        input.collectorName ?? null,
        input.collectorPhone ?? null,
        input.collectorAddress ?? null,
        input.collectorLatitude ?? null,
        input.collectorLongitude ?? null,
        input.collectorPoiName ?? null,
        input.collectorAddressText ?? null,
        packageId,
        packageName,
        packageBasePrice,
        selectedItemsJson,
        extraItemsJson,
        extraAmount,
        finalAmount,
        packageAmount,
        companyPayAmount,
        employeePayAmount,
        couponClaimId,
        couponDiscountAmount,
        employeePayBeforeCoupon,
        settlementStatus,
        paymentChannel,
        now,
        now,
      );

      const insertItem = db.prepare(
        `INSERT INTO order_items
           (order_id, dish_id, dish_name, dish_image_url, dish_description,
            meal_type, price, quantity, subtotal)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      );
      for (const item of itemsToInsert) {
        let dishName = item.dishName;
        if (item.dishId) {
          const dishRow = db
            .prepare<[string], { name: string }>(
              'SELECT name FROM dishes WHERE id = ?',
            )
            .get(item.dishId);
          if (dishRow?.name && !isCorruptDisplayText(dishRow.name)) {
            dishName = dishRow.name;
          } else if (isCorruptDisplayText(dishName) && dishRow?.name) {
            dishName = dishRow.name;
          }
        }
        insertItem.run(
          id,
          item.dishId ?? null,
          dishName,
          item.dishImageUrl ?? null,
          item.dishDescription ?? '',
          item.mealType ?? null,
          item.price,
          item.quantity,
          Number((item.price * item.quantity).toFixed(2)),
        );
      }

      if (couponClaimId && input.userId && couponDiscountAmount > 0) {
        couponService.markClaimUsed({
          claimId: couponClaimId,
          orderId: id,
          userId: input.userId,
          discountAmount: couponDiscountAmount,
        });
      }
    });

    tx();

    const created = this.getById(id)!;

    if (
      orderMealType &&
      ['breakfast', 'lunch', 'dinner'].includes(orderMealType) &&
      companyPayAmount > 0 &&
      input.userId
    ) {
      try {
        const workDate = shanghaiDateString();
        const rosterId = overtimeRosterService.findRosterId({
          workDate,
          mealType: orderMealType,
          userId: input.userId,
          phone: userPhone,
          employeeNo: empCtx.employeeNo,
          employeeName: empCtx.employeeName,
          department: departmentName,
        });
        if (!rosterId) {
          console.warn('[order.create] roster usage skipped: no rosterId for', id);
        } else {
          overtimeMealUsageService.recordUsage({
            workDate,
            mealType: orderMealType,
            userId: input.userId,
            phone: userPhone,
            merchantId: input.merchantId,
            orderId: id,
            rosterId,
            companyPayAmount,
            employeePayAmount,
            orderTotalAmount: finalAmount,
          });
        }
      } catch (e) {
        console.warn('[order.create] roster usage record failed for', id, e);
      }
    }

    // 订单沟通：创建订单的同时建立会话 + 写入"订单已提交"系统消息
    try {
      conversationService.getOrCreateForOrder(created);
    } catch {
      // 会话创建失败不应影响下单主流程，但应在终端打印便于排查
      console.warn('[order.create] conversation bootstrap failed for', created.id);
    }

    return {
      order: created,
      items: this.itemsOfOrder(id),
    };
  }

  /**
   * 服务端权威：根据套餐 ID + 所选菜 ID + 加菜，重算价格并校验：
   * - 套餐属于该商家、is_enabled = 1
   * - 所选菜品都属于该商家、is_available = 1
   * - 按 category 聚合后，每个分类数量必须等于套餐 rules
   * - 加菜必须是 category=extra 且 is_available=1；若套餐配置了 extra_dish_ids 白名单则必须在内
   * - 加菜需 quantity >= 1
   * 计算：finalAmount = base_price + Σ(extra.unitPrice * extra.quantity)
   */
  private computePackageOrder(
    merchantId: string,
    p: PackageOrderInput,
  ): PackageOrderComputed {
    const db = getDb();
    const pkg = packageService.getById(p.packageId);
    if (!pkg) throw new Error('PACKAGE_NOT_FOUND');
    if (pkg.merchant_id !== merchantId) throw new Error('PACKAGE_MERCHANT_MISMATCH');
    if (!pkg.is_enabled) throw new Error('PACKAGE_DISABLED');

    const rawRules = parsePackageRules(pkg.rules_json);
    // 业务简化：套餐只校验荤菜和素菜数量；历史数据里如果有 staple/soup/drink，会被忽略
    const rules: PackageRules = {
      meat: rawRules.meat ?? 0,
      vegetable: rawRules.vegetable ?? 0,
    };

    // ---- 校验所选普通菜品 ----
    const selectedDishIds = (p.selectedDishIds ?? [])
      .map((s) => (typeof s === 'string' ? s.trim() : ''))
      .filter((s) => s.length > 0);

    const requiredCount = (rules.meat ?? 0) + (rules.vegetable ?? 0);
    if (selectedDishIds.length !== requiredCount) {
      throw new Error('PACKAGE_RULE_COUNT_MISMATCH');
    }

    const selectedDishes: DishRow[] = [];
    for (const dishId of selectedDishIds) {
      const dish = db
        .prepare<[string], DishRow>('SELECT * FROM dishes WHERE id = ?')
        .get(dishId);
      if (!dish) throw new Error('DISH_NOT_FOUND');
      if (dish.merchant_id !== merchantId) throw new Error('DISH_MERCHANT_MISMATCH');
      if (!dish.is_available) throw new Error('DISH_UNAVAILABLE');
      selectedDishes.push(dish);
    }

    // 按 category 聚合，套餐只允许选 meat / vegetable
    const countByCat: Partial<Record<DishCategory, number>> = {};
    for (const d of selectedDishes) {
      const cat = normalizeDishCategory(d.category);
      if (cat !== 'meat' && cat !== 'vegetable') {
        throw new Error('DISH_CATEGORY_INVALID');
      }
      countByCat[cat] = (countByCat[cat] ?? 0) + 1;
    }
    for (const cat of ['meat', 'vegetable'] as const) {
      const expected = rules[cat] ?? 0;
      const actual = countByCat[cat] ?? 0;
      if (expected !== actual) {
        throw new Error(`PACKAGE_RULE_MISMATCH:${cat}`);
      }
    }

    const selectedItems: OrderSelectedItemDto[] = selectedDishes.map((d) => ({
      dishId: d.id,
      name: d.name,
      category: normalizeDishCategory(d.category),
      mealType: d.meal_type ?? null,
    }));

    // ---- 校验加菜 ----
    // 业务简化：加菜不再受套餐 allow_extra 控制；
    // 只要订单选择的加菜属于当前商家、category=extra、is_available=1，就允许参与加价。
    // 如果历史套餐配置了 extra_dish_ids 白名单，仍然兼容生效。
    const extras: { dish: DishRow; quantity: number; subtotal: number }[] = [];
    let extraAmount = 0;
    if (p.extras && p.extras.length > 0) {
      const allowList = (() => {
        try {
          const a = JSON.parse(pkg.extra_dish_ids_json || '[]');
          return Array.isArray(a) ? a.map(String) : [];
        } catch {
          return [];
        }
      })();
      for (const x of p.extras) {
        if (!x || typeof x.dishId !== 'string' || !(x.quantity >= 1)) {
          throw new Error('INVALID_EXTRA_ITEM');
        }
        const dish = db
          .prepare<[string], DishRow>('SELECT * FROM dishes WHERE id = ?')
          .get(x.dishId.trim());
        if (!dish) throw new Error('EXTRA_DISH_NOT_FOUND');
        if (dish.merchant_id !== merchantId)
          throw new Error('EXTRA_DISH_MERCHANT_MISMATCH');
        if (!dish.is_available) throw new Error('EXTRA_DISH_UNAVAILABLE');
        if (normalizeDishCategory(dish.category) !== 'extra') {
          throw new Error('EXTRA_DISH_CATEGORY_INVALID');
        }
        if (allowList.length > 0 && !allowList.includes(dish.id)) {
          throw new Error('EXTRA_DISH_NOT_ALLOWED');
        }
        const unitPrice = typeof dish.extra_price === 'number' ? dish.extra_price : 0;
        const quantity = Math.floor(x.quantity);
        const subtotal = Number((unitPrice * quantity).toFixed(2));
        extras.push({ dish, quantity, subtotal });
        extraAmount += subtotal;
      }
    }
    extraAmount = Number(extraAmount.toFixed(2));

    const extraItems: OrderExtraItemDto[] = extras.map((e) => ({
      dishId: e.dish.id,
      name: e.dish.name,
      unitPrice:
        typeof e.dish.extra_price === 'number' ? e.dish.extra_price : 0,
      quantity: e.quantity,
      subtotal: e.subtotal,
    }));

    const basePrice = typeof pkg.base_price === 'number' ? pkg.base_price : 0;
    const finalAmount = Number((basePrice + extraAmount).toFixed(2));

    // ---- 同步写一份 order_items，保持旧查询兼容（商家订单列表/明细） ----
    const itemRows: OrderItemInput[] = [];
    // 套餐基础菜按 0 元入库（金额已包含在套餐基础价里），price=0 仅做明细展示
    for (const d of selectedDishes) {
      itemRows.push({
        dishId: d.id,
        dishName: d.name,
        dishImageUrl: d.image_url ?? undefined,
        dishDescription: d.description ?? '',
        mealType: d.meal_type ?? undefined,
        price: 0,
        quantity: 1,
      });
    }
    // 套餐基础价单独入一行，便于商家端订单详情展示总价
    itemRows.push({
      dishId: undefined,
      dishName: `【套餐】${pkg.name}`,
      dishImageUrl: undefined,
      dishDescription: pkg.description ?? '',
      mealType: undefined,
      price: basePrice,
      quantity: 1,
    });
    for (const e of extras) {
      itemRows.push({
        dishId: e.dish.id,
        dishName: `【加菜】${e.dish.name}`,
        dishImageUrl: e.dish.image_url ?? undefined,
        dishDescription: e.dish.description ?? '',
        mealType: e.dish.meal_type ?? undefined,
        price:
          typeof e.dish.extra_price === 'number' ? e.dish.extra_price : 0,
        quantity: e.quantity,
      });
    }

    return {
      pkg,
      rules,
      selectedDishes,
      selectedItems,
      extras,
      extraItems,
      extraAmount,
      finalAmount,
      itemRows,
    };
  }

  getById(id: string): OrderRow | undefined {
    return getDb()
      .prepare<[string], OrderRow>('SELECT * FROM orders WHERE id = ?')
      .get(id);
  }

  itemsOfOrder(orderId: string): OrderItemRow[] {
    return getDb()
      .prepare<[string], OrderItemRow>(
        'SELECT * FROM order_items WHERE order_id = ? ORDER BY id ASC',
      )
      .all(orderId);
  }

  private buildDisplayLookup(order: OrderRow, items: OrderItemRow[]) {
    const db = getDb();
    const merchantRow = db
      .prepare<[string], { name: string }>(
        'SELECT name FROM merchants WHERE id = ?',
      )
      .get(order.merchant_id);
    const dishNameById = new Map<string, string>();
    const rememberDish = (dishId?: string | null) => {
      if (!dishId || dishNameById.has(dishId)) return;
      const row = db
        .prepare<[string], { name: string }>(
          'SELECT name FROM dishes WHERE id = ?',
        )
        .get(dishId);
      if (row?.name) dishNameById.set(dishId, row.name);
    };
    for (const item of items) rememberDish(item.dish_id);
    try {
      const selected = JSON.parse(order.selected_items_json ?? '[]');
      if (Array.isArray(selected)) {
        for (const row of selected) {
          if (row && typeof row === 'object') {
            rememberDish(String((row as Record<string, unknown>).dishId ?? ''));
          }
        }
      }
    } catch {
      /* ignore */
    }
    try {
      const extras = JSON.parse(order.extra_items_json ?? '[]');
      if (Array.isArray(extras)) {
        for (const row of extras) {
          if (row && typeof row === 'object') {
            rememberDish(String((row as Record<string, unknown>).dishId ?? ''));
          }
        }
      }
    } catch {
      /* ignore */
    }
    return {
      merchantNameFromDb: merchantRow?.name ?? null,
      dishNameById,
    };
  }

  toDisplayDto(order: OrderRow): OrderDto {
    const items = this.itemsOfOrder(order.id);
    return orderToDto(order, items, this.buildDisplayLookup(order, items));
  }

  listByUser(userId: string): OrderRow[] {
    return getDb()
      .prepare<[string], OrderRow>(
        'SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC',
      )
      .all(userId);
  }

  listByMerchant(merchantId: string): OrderRow[] {
    return getDb()
      .prepare<[string], OrderRow>(
        'SELECT * FROM orders WHERE merchant_id = ? ORDER BY created_at DESC',
      )
      .all(merchantId);
  }

  /** 当前 Mock 环境下也可一次返回全部订单 */
  listAll(): OrderRow[] {
    return getDb()
      .prepare<[], OrderRow>('SELECT * FROM orders ORDER BY created_at DESC')
      .all();
  }

  updateStatus(
    orderId: string,
    status: OrderStatus,
    rejectReason?: string | null,
    actorRole?: import('../models/types').UserRole,
  ): OrderRow {
    if (!ALL_ORDER_STATUSES.includes(status)) {
      throw new Error('INVALID_STATUS');
    }
    const existing = this.getById(orderId);
    if (!existing) throw new Error('NOT_FOUND');
    orderPolicyService.assertStatusChange(existing, status, actorRole);

    const db = getDb();
    const r = db
      .prepare(
        'UPDATE orders SET status = ?, reject_reason = ?, updated_at = ? WHERE id = ?',
      )
      .run(status, rejectReason ?? null, nowIso(), orderId);
    if (r.changes === 0) throw new Error('NOT_FOUND');
    const next = this.getById(orderId)!;

    if (status === 'accepted' && existing.status !== 'accepted') {
      settlementService.markOrderInService(orderId);
    }
    if (status === 'completed' && existing.status !== 'completed') {
      settlementService.onOrderCompleted(next);
    }

    try {
      conversationService.appendStatusSystemMessage(next);
    } catch {
      // 系统消息写入失败不影响订单状态变更
    }
    return next;
  }

  /** 在线支付成功：pendingPayment → paymentSubmitted → pendingMerchantConfirm */
  confirmOnlinePayment(orderId: string, channel: string): OrderRow {
    const existing = this.getById(orderId);
    if (!existing) throw new Error('NOT_FOUND');
    if (existing.status !== 'pendingPayment') {
      throw new Error('ORDER_NOT_PENDING_PAYMENT');
    }

    const db = getDb();
    const now = nowIso();
    db.prepare(
      `UPDATE orders SET status = ?, payment_channel = ?, updated_at = ? WHERE id = ?`,
    ).run('paymentSubmitted', channel, now, orderId);

    settlementService.markOrderPaidToPlatform(orderId, channel);
    return this.updateStatus(orderId, 'pendingMerchantConfirm');
  }

  /** 历史订单缺少 user_id 时，由下单员工认领（仅当仍为空） */
  claimEmployeeOrder(orderId: string, userId: string): void {
    getDb()
      .prepare(
        `UPDATE orders SET user_id = ?, updated_at = ? WHERE id = ? AND user_id IS NULL`,
      )
      .run(userId, nowIso(), orderId);
  }

  /** 上传付款截图并推进支付流程：pendingPayment → paymentSubmitted → pendingMerchantConfirm */
  submitPaymentScreenshot(
    orderId: string,
    url: string,
    manualPayChannel?: 'wechat' | 'alipay',
  ): OrderRow {
    const existing = this.getById(orderId);
    if (!existing) throw new Error('NOT_FOUND');
    orderPolicyService.assertCanUploadPaymentScreenshot(existing);

    const db = getDb();
    const now = nowIso();
    const tx = db.transaction(() => {
      db.prepare(
        `UPDATE orders SET payment_screenshot_url = ?, status = ?,
           manual_pay_channel = ?, updated_at = ? WHERE id = ?`,
      ).run(
        url,
        'paymentSubmitted',
        manualPayChannel ?? null,
        now,
        orderId,
      );
    });
    tx();

    settlementService.markOrderPaidToPlatform(orderId, 'manual_qr');

    let next = this.getById(orderId)!;
    try {
      conversationService.appendPaymentScreenshotSystemMessage(next);
    } catch {
      // ignore
    }

    next = this.updateStatus(orderId, 'pendingMerchantConfirm');
    return next;
  }

  updatePaymentScreenshot(orderId: string, url: string): OrderRow {
    return this.submitPaymentScreenshot(orderId, url);
  }
}

export const orderService = new OrderService();
