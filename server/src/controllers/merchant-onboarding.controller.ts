import { Request, Response } from 'express';
import {
  BadRequest,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { ALL_MEAL_TYPES, MealType } from '../models/types';
import {
  MerchantApplyInput,
  merchantOnboardingService,
  AgreementSignContext,
} from '../services/merchant-onboarding.service';
import { normalizePhone } from '../utils/phone.util';

function buildApplyInput(
  body: Record<string, unknown>,
  userId: string | undefined,
): MerchantApplyInput {
  const supportedMealTypes = (body.supportedMealTypes ?? []) as MealType[];
  return {
    merchantName: String(body.merchantName ?? ''),
    shortName: body.shortName as string | undefined,
    contactName: String(body.contactName ?? ''),
    contactPhone: String(body.contactPhone ?? ''),
    address: String(body.address ?? ''),
    companyId: body.companyId as string | undefined,
    supportedMealTypes,
    deliveryModes: (body.deliveryModes as string[] | undefined) ?? [],
    // 旧字段：入驻页已不再提交；如果调用方仍传，则透传以兼容
    deliveryScope: body.deliveryScope as string | undefined,
    estimatedDeliveryTime: body.estimatedDeliveryTime as string | undefined,
    deliveryFee:
      body.deliveryFee != null ? Number(body.deliveryFee) : undefined,
    paymentMethod: body.paymentMethod as string | undefined,
    paymentQr: body.paymentQr as string | undefined,
    paymentReceiverName: body.paymentReceiverName as string | undefined,
    businessLicenseUrl: body.businessLicenseUrl as string | undefined,
    foodLicenseUrl: body.foodLicenseUrl as string | undefined,
    storePhotoUrl: body.storePhotoUrl as string | undefined,
    remark: body.remark as string | undefined,
    userId,
    // 企业级商家审核扩展字段
    storeDisplayName: body.storeDisplayName as string | undefined,
    customerServicePhone: body.customerServicePhone as string | undefined,
    servedCompanyText: body.servedCompanyText as string | undefined,
    businessDays: body.businessDays as string[] | undefined,
    businessHoursStart: body.businessHoursStart as string | undefined,
    businessHoursEnd: body.businessHoursEnd as string | undefined,
    mealOrderDeadlines: body.mealOrderDeadlines as
      | Partial<Record<MealType, string>>
      | undefined,
    paymentSubjectType: body.paymentSubjectType as string | undefined,
    paymentSubjectName: body.paymentSubjectName as string | undefined,
    bankAccountName: body.bankAccountName as string | undefined,
    bankName: body.bankName as string | undefined,
    bankAccountNumber: body.bankAccountNumber as string | undefined,
    businessLicenseSubject: body.businessLicenseSubject as string | undefined,
    businessLicenseValidUntil: body.businessLicenseValidUntil as
      | string
      | undefined,
    unifiedSocialCreditCode: body.unifiedSocialCreditCode as
      | string
      | undefined,
    foodLicenseNumber: body.foodLicenseNumber as string | undefined,
    foodLicenseValidUntil: body.foodLicenseValidUntil as string | undefined,
    licensedBusinessScope: body.licensedBusinessScope as string | undefined,
    kitchenPhotoUrl: body.kitchenPhotoUrl as string | undefined,
    healthCertificateUrl: body.healthCertificateUrl as string | undefined,
    // 多图 / 多选字段
    paymentMethods: toStringArray(body.paymentMethods),
    wechatPaymentQrUrls: toStringArray(body.wechatPaymentQrUrls),
    alipayPaymentQrUrls: toStringArray(body.alipayPaymentQrUrls),
    businessLicenseUrls: toStringArray(body.businessLicenseUrls),
    foodLicenseUrls: toStringArray(body.foodLicenseUrls),
    kitchenPhotoUrls: toStringArray(body.kitchenPhotoUrls),
    healthCertificateUrls: toStringArray(body.healthCertificateUrls),
    storePhotoUrls: toStringArray(body.storePhotoUrls),
    agreementVersion: body.agreementVersion as string | undefined,
    clientTime: body.clientTime as string | undefined,
    deviceInfo: body.deviceInfo as string | undefined,
  };
}

function agreementContextFromRequest(
  req: Request,
  body: Record<string, unknown>,
): AgreementSignContext {
  const deviceInfo =
    typeof body.deviceInfo === 'string' ? body.deviceInfo.trim() : '';
  return {
    ipAddress: req.ip || (req.socket.remoteAddress as string | undefined),
    userAgent: deviceInfo || req.get('user-agent') || undefined,
  };
}

function toStringArray(v: unknown): string[] | undefined {
  if (v == null) return undefined;
  if (!Array.isArray(v)) return undefined;
  return v.filter((s): s is string => typeof s === 'string');
}

function mapApplyError(err: unknown): never {
  const code = (err as Error).message;
  switch (code) {
    case 'INVALID_PHONE':
      throw BadRequest('手机号格式不正确');
    case 'INVALID_NAME':
      throw BadRequest('商家名称不能为空');
    case 'INVALID_CONTACT':
      throw BadRequest('联系人姓名不能为空');
    case 'INVALID_ADDRESS':
      throw BadRequest('店铺地址不能为空');
    case 'INVALID_MEALS':
      throw BadRequest('请至少选择一个支持餐段');
    case 'ALREADY_APPROVED':
      throw BadRequest('该手机号商家已审核通过，请直接登录');
    case 'USER_DISABLED':
      throw BadRequest('账号已被禁用');
    case 'NOT_FOUND':
      throw NotFound('入驻申请不存在');
    case 'NOT_REJECTED':
      throw BadRequest('仅被拒绝的申请可重新提交');
    case 'FORBIDDEN':
      throw Unauthorized('无权操作');
    case 'AGREEMENT_VERSION_MISMATCH':
      throw BadRequest('协议版本已更新，请刷新页面后重新同意');
    default:
      throw err;
  }
}

export const merchantOnboardingPublicController = {
  apply(req: Request, res: Response) {
    const body = req.body ?? {};
    const supportedMealTypes = (body.supportedMealTypes ?? []) as MealType[];
    if (supportedMealTypes.some((m) => !ALL_MEAL_TYPES.includes(m))) {
      throw BadRequest('supportedMealTypes 非法');
    }
    try {
      const data = merchantOnboardingService.apply(
        buildApplyInput(body, req.user?.id),
        agreementContextFromRequest(req, body),
      );
      res.json({ data });
    } catch (e) {
      mapApplyError(e);
    }
  },

  status(req: Request, res: Response) {
    const phone = req.query.phone as string;
    if (!phone) throw BadRequest('phone 必填');
    const data = merchantOnboardingService.getStatusByPhone(phone);
    res.json({ data });
  },

  resubmit(req: Request, res: Response) {
    const body = req.body ?? {};
    const supportedMealTypes = (body.supportedMealTypes ?? []) as MealType[];
    if (supportedMealTypes.some((m) => !ALL_MEAL_TYPES.includes(m))) {
      throw BadRequest('supportedMealTypes 非法');
    }
    try {
      const data = merchantOnboardingService.resubmit(
        req.params.id,
        buildApplyInput(body, req.user?.id),
        req.user ?? undefined,
        agreementContextFromRequest(req, body),
      );
      res.json({ data });
    } catch (e) {
      mapApplyError(e);
    }
  },

  /** 兼容旧路径 */
  register(req: Request, res: Response) {
    return merchantOnboardingPublicController.apply(req, res);
  },
};

export { normalizePhone };
