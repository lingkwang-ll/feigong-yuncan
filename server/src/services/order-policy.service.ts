import {
  OrderRow,
  OrderStatus,
  PaymentType,
  UserRole,
} from '../models/types';
import { MealType } from '../models/types';
import { assertMealTypesOrderable } from '../utils/meal-deadline.util';
import { shanghaiDateString } from '../utils/date.util';
import { systemConfigService } from './system-config.service';
import { overtimeRosterService } from './overtime-roster.service';
import { overtimeMealUsageService } from './overtime-meal-usage.service';

import { COMPANY_PAY_SUBSIDY_CAP } from '../constants/company-pay.constants';

/** 合法状态转换表（from -> to[]） */
const STATUS_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  pendingPayment: ['paymentSubmitted', 'cancelled'],
  paymentSubmitted: ['pendingMerchantConfirm', 'cancelled'],
  pendingMerchantConfirm: ['accepted', 'cancelled'],
  accepted: ['delivering', 'completed', 'cancelled'],
  delivering: ['completed', 'cancelled'],
  completed: [],
  cancelled: [],
};

export interface PaymentSplitResult {
  packageAmount: number;
  extraAmount: number;
  companyPayAmount: number;
  employeePayAmount: number;
  totalAmount: number;
  paymentType: PaymentType;
  initialStatus: OrderStatus;
}

export { COMPANY_PAY_SUBSIDY_CAP } from '../constants/company-pay.constants';

export class OrderPolicyService {
  assertCreateAllowed(
    items: { mealType?: MealType }[],
    merchantId?: string | null,
  ): void {
    const mealTypes = items
      .map((i) => i.mealType)
      .filter((t): t is MealType => !!t);
    if (mealTypes.length > 0) {
      assertMealTypesOrderable(mealTypes, merchantId);
    }
  }

  /** 非加班餐：部门匹配企业代付规则（行政部/生产部等） */
  resolveDepartmentCompanyPay(departmentName?: string | null): boolean {
    const dept = (departmentName ?? '').trim();
    if (!dept) return false;
    const settings = systemConfigService.getAppSettings();
    const rules = settings.companyPayDepartments ?? [];
    return rules.some((r) => r.trim() === dept);
  }

  /**
   * 服务端权威计算支付拆分（不信任前端 paymentType / 金额字段）。
   */
  resolvePaymentSplit(input: {
    orderMealType?: MealType | null;
    userId?: string | null;
    userName?: string | null;
    userPhone?: string | null;
    employeeNo?: string | null;
    departmentName?: string | null;
    packageAmount: number;
    extraAmount: number;
  }): PaymentSplitResult {
    const packageAmount = Number(input.packageAmount.toFixed(2));
    const extraAmount = Number(input.extraAmount.toFixed(2));
    const totalAmount = Number((packageAmount + extraAmount).toFixed(2));

    const orderMealType = input.orderMealType ?? null;
    const workDate = shanghaiDateString();
    const rosterMealTypes: MealType[] = ['breakfast', 'lunch', 'dinner'];

    const rosterCompanyPay = (
      mealType: MealType,
    ): PaymentSplitResult | null => {
      const matchedRoster = overtimeRosterService.findMatchingRoster({
        workDate,
        mealType,
        userId: input.userId,
        phone: input.userPhone ?? '',
        employeeNo: input.employeeNo ?? '',
        employeeName: input.userName ?? '',
        department: input.departmentName ?? '',
      });
      const onRoster = matchedRoster != null;
      const matchedRosterId = matchedRoster?.id ?? null;

      const activeUsage = overtimeMealUsageService.getActiveUsage({
        workDate,
        mealType,
        userId: input.userId,
        phone: input.userPhone ?? '',
      });
      const alreadyUsed = activeUsage != null;

      console.log(
        `[company-pay] userId=${input.userId ?? ''} phone=${input.userPhone ?? ''} ` +
          `workDate=${workDate} mealType=${mealType} matchedRosterId=${matchedRosterId ?? 'none'} ` +
          `usageFound=${alreadyUsed ? activeUsage?.id ?? 'yes' : 'no'} totalAmount=${totalAmount}`,
      );

      if (!onRoster) return null;
      if (alreadyUsed) return null;

      const cap = COMPANY_PAY_SUBSIDY_CAP;
      const companyPayAmount = Number(Math.min(totalAmount, cap).toFixed(2));
      const employeePayAmount = Number((totalAmount - companyPayAmount).toFixed(2));
      const paymentType: PaymentType =
        employeePayAmount <= 0 ? 'company_pay' : 'mixed_pay';
      const initialStatus: OrderStatus =
        employeePayAmount <= 0 ? 'pendingMerchantConfirm' : 'pendingPayment';

      console.log(
        `[company-pay] companyPayAmount=${companyPayAmount} employeePayAmount=${employeePayAmount} paymentType=${paymentType}`,
      );

      return {
        packageAmount,
        extraAmount,
        companyPayAmount,
        employeePayAmount,
        totalAmount,
        paymentType,
        initialStatus,
      };
    };

    if (orderMealType && rosterMealTypes.includes(orderMealType)) {
      const split = rosterCompanyPay(orderMealType);
      if (split) return split;
      return {
        packageAmount,
        extraAmount,
        companyPayAmount: 0,
        employeePayAmount: totalAmount,
        totalAmount,
        paymentType: 'self_pay',
        initialStatus: 'pendingPayment',
      };
    }

    // 加班餐（历史兼容）：不再企业代付，全额自费
    if (orderMealType === 'overtime') {
      return {
        packageAmount,
        extraAmount,
        companyPayAmount: 0,
        employeePayAmount: totalAmount,
        totalAmount,
        paymentType: 'self_pay',
        initialStatus: 'pendingPayment',
      };
    }

    // 未指定餐段或其它：自费
    return {
      packageAmount,
      extraAmount,
      companyPayAmount: 0,
      employeePayAmount: totalAmount,
      totalAmount,
      paymentType: 'self_pay',
      initialStatus: 'pendingPayment',
    };
  }

  employeePayAmountOf(order: OrderRow): number {
    if (typeof order.employee_pay_amount === 'number') {
      return order.employee_pay_amount;
    }
    const pt: PaymentType = order.payment_type ?? 'self_pay';
    if (pt === 'company_pay') return 0;
    return order.total_amount ?? 0;
  }

  needsPaymentScreenshot(order: OrderRow): boolean {
    return this.employeePayAmountOf(order) > 0;
  }

  /** 微信/支付宝等在线支付已入账，无需付款截图 */
  hasOnlinePaymentVerified(order: OrderRow): boolean {
    const ch = order.payment_channel ?? '';
    if (ch !== 'wechat_pay' && ch !== 'alipay') return false;
    const st = order.settlement_status ?? 'not_paid';
    return (
      st === 'paid_to_platform' ||
      st === 'in_service' ||
      st === 'completed_pending_settlement' ||
      st === 'settlement_pending' ||
      st === 'settled'
    );
  }

  assertStatusChange(
    order: OrderRow,
    nextStatus: OrderStatus,
    actorRole?: UserRole,
  ): void {
    const settings = systemConfigService.getAppSettings();
    const current = order.status;
    const employeePay = this.employeePayAmountOf(order);

    if (nextStatus === current) return;

    const allowed = STATUS_TRANSITIONS[current] ?? [];
    if (!allowed.includes(nextStatus)) {
      throw new Error('INVALID_STATUS_TRANSITION');
    }

    if (nextStatus === 'cancelled' && !settings.allowCancelOrder) {
      throw new Error('CANCEL_NOT_ALLOWED');
    }

    // 无需员工支付时不允许走上传截图态
    if (employeePay <= 0 && nextStatus === 'paymentSubmitted') {
      throw new Error('COMPANY_PAY_NO_SCREENSHOT');
    }

    // 员工需支付时：商家接单前必须有付款截图或在线支付已确认
    if (
      settings.requirePaymentScreenshot &&
      nextStatus === 'accepted' &&
      employeePay > 0 &&
      !order.payment_screenshot_url &&
      !this.hasOnlinePaymentVerified(order)
    ) {
      throw new Error('PAYMENT_SCREENSHOT_REQUIRED');
    }

    if (
      employeePay > 0 &&
      nextStatus === 'accepted' &&
      current !== 'pendingMerchantConfirm'
    ) {
      throw new Error('PAYMENT_FLOW_INCOMPLETE');
    }

    if (actorRole === 'employee') {
      if (
        nextStatus === 'accepted' ||
        nextStatus === 'pendingMerchantConfirm' ||
        nextStatus === 'paymentSubmitted' ||
        nextStatus === 'delivering'
      ) {
        throw new Error('EMPLOYEE_STATUS_FORBIDDEN');
      }
      if (
        nextStatus === 'completed' &&
        current !== 'accepted' &&
        current !== 'delivering'
      ) {
        throw new Error('EMPLOYEE_COMPLETE_FORBIDDEN');
      }
    }
  }

  assertCanUploadPaymentScreenshot(order: OrderRow): void {
    if (!this.needsPaymentScreenshot(order)) {
      throw new Error('COMPANY_PAY_NO_SCREENSHOT');
    }
    if (
      order.status !== 'pendingPayment' &&
      order.status !== 'paymentSubmitted'
    ) {
      throw new Error('PAYMENT_UPLOAD_NOT_ALLOWED');
    }
  }
}

export const orderPolicyService = new OrderPolicyService();
