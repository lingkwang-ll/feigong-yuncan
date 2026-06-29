import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import {
  merchantOnboardingDetailToDto,
  merchantOnboardingToDto,
  nowIso,
  parseJsonArray,
} from '../models/mappers';
import {
  AdminMerchantDto,
  MealType,
  MerchantOnboardingDetailDto,
  MerchantOnboardingPhoneStatus,
  MerchantOnboardingStatus,
  MerchantOnboardingStatusDto,
  MerchantRow,
  UserRow,
} from '../models/types';
import {
  assertMerchantAccess,
  companyFilterSql,
  DEFAULT_COMPANY_ID,
  resolveAdminScope,
} from '../utils/company-scope.util';
import { isValidPhone, normalizePhone } from '../utils/phone.util';
import {
  deriveMealOrderDeadlinesFromOpeningHours,
  MealOpeningHoursEntry,
  normalizeMealOpeningHours,
  validateMealOpeningHours,
} from '../utils/meal-opening-hours.util';
import { defaultPasswordHash } from '../utils/password.util';
import { passwordAuthService } from './password-auth.service';
import { merchantAgreementService } from './merchant-agreement.service';

export interface AgreementSignContext {
  ipAddress?: string;
  userAgent?: string;
}

export interface MerchantRegisterInput {
  merchantName: string;
  address: string;
  phone: string;
  companyId: string;
  userId?: string;
  paymentQr?: string;
  menuInit?: boolean;
}

export interface MerchantApplyInput {
  merchantName: string;
  shortName?: string;
  contactName: string;
  contactPhone: string;
  address: string;
  companyId?: string;
  supportedMealTypes: MealType[];
  deliveryModes: string[];
  /** @deprecated 入驻页不再提交，保留以兼容旧调用 */
  deliveryScope?: string;
  /** @deprecated 入驻页不再提交，保留以兼容旧调用 */
  estimatedDeliveryTime?: string;
  /** @deprecated 入驻页不再提交，保留以兼容旧调用 */
  deliveryFee?: number;
  paymentMethod?: string;
  paymentQr?: string;
  paymentReceiverName?: string;
  businessLicenseUrl?: string;
  foodLicenseUrl?: string;
  storePhotoUrl?: string;
  remark?: string;
  userId?: string;
  // 企业级商家审核扩展字段
  storeDisplayName?: string;
  customerServicePhone?: string;
  servedCompanyText?: string;
  businessDays?: string[];
  businessHoursStart?: string;
  businessHoursEnd?: string;
  mealOpeningHours?: Record<string, MealOpeningHoursEntry>;
  mealOrderDeadlines?: Partial<Record<MealType, string>>;
  paymentSubjectType?: string;
  paymentSubjectName?: string;
  bankAccountName?: string;
  bankName?: string;
  bankAccountNumber?: string;
  businessLicenseSubject?: string;
  businessLicenseValidUntil?: string;
  unifiedSocialCreditCode?: string;
  foodLicenseNumber?: string;
  foodLicenseValidUntil?: string;
  licensedBusinessScope?: string;
  kitchenPhotoUrl?: string;
  healthCertificateUrl?: string;
  // 多图 / 多选输入（新提交时优先使用，旧单值字段会自动从第一张取兼容）
  paymentMethods?: string[];
  wechatPaymentQrUrls?: string[];
  alipayPaymentQrUrls?: string[];
  businessLicenseUrls?: string[];
  foodLicenseUrls?: string[];
  kitchenPhotoUrls?: string[];
  healthCertificateUrls?: string[];
  storePhotoUrls?: string[];
  /** 协议签署：版本号（与客户端 legalVersion 对齐） */
  agreementVersion?: string;
  /** 客户端本地时间 ISO 字符串 */
  clientTime?: string;
  /** 设备信息（写入 user_agent 列） */
  deviceInfo?: string;
}

const ALLOWED_PAYMENT_METHODS = new Set(['wechat', 'alipay', 'bankTransfer']);

function sanitizeUrls(urls?: string[]): string[] {
  if (!urls || !Array.isArray(urls)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const u of urls) {
    if (typeof u !== 'string') continue;
    const t = u.trim();
    if (!t) continue;
    if (!(t.startsWith('/uploads/') || t.startsWith('http'))) continue;
    if (seen.has(t)) continue;
    seen.add(t);
    out.push(t);
  }
  return out;
}

function sanitizePaymentMethods(methods?: string[]): string[] {
  if (!methods || !Array.isArray(methods)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const m of methods) {
    if (typeof m !== 'string') continue;
    const t = m.trim();
    if (!ALLOWED_PAYMENT_METHODS.has(t) || seen.has(t)) continue;
    seen.add(t);
    out.push(t);
  }
  return out;
}

const ALL_BUSINESS_DAYS = new Set([
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
]);

function normalizeBusinessDays(input?: string[]): string[] {
  if (!input || !Array.isArray(input)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const d of input) {
    const k = String(d).trim().toLowerCase();
    if (ALL_BUSINESS_DAYS.has(k) && !seen.has(k)) {
      seen.add(k);
      out.push(k);
    }
  }
  return out;
}

function normalizeDeadlines(
  input?: Partial<Record<MealType, string>>,
): Partial<Record<MealType, string>> {
  if (!input || typeof input !== 'object') return {};
  const out: Partial<Record<MealType, string>> = {};
  const meals: MealType[] = ['breakfast', 'lunch', 'dinner', 'overtime'];
  for (const m of meals) {
    const v = (input as Record<string, unknown>)[m];
    if (typeof v === 'string' && /^\d{1,2}:\d{2}$/.test(v.trim())) {
      out[m] = v.trim();
    }
  }
  return out;
}

const ALL_MEALS: MealType[] = ['breakfast', 'lunch', 'dinner', 'overtime'];

function findByPhone(phone: string): MerchantRow | undefined {
  const normalized = normalizePhone(phone);
  return getDb()
    .prepare(
      `SELECT m.* FROM merchants m
       LEFT JOIN users u ON u.id = m.user_id
       WHERE m.phone = ? OR m.contact_phone = ? OR u.phone = ?
       ORDER BY m.updated_at DESC LIMIT 1`,
    )
    .get(normalized, normalized, normalized) as MerchantRow | undefined;
}

function mealTypesFromRow(row: MerchantRow, merchantId: string): MealType[] {
  const stored = parseJsonArray<MealType>(row.supported_meal_types_json);
  if (stored.length) return stored;
  const db = getDb();
  return db
    .prepare<[string], { meal_type: MealType }>(
      'SELECT DISTINCT meal_type FROM dishes WHERE merchant_id = ?',
    )
    .all(merchantId)
    .map((r) => r.meal_type);
}

export class MerchantOnboardingService {
  listPending(user: UserRow): MerchantRow[] {
    const db = getDb();
    const { clause, params } = companyFilterSql(user, 'company_id');
    return db
      .prepare(
        `SELECT * FROM merchants WHERE onboarding_status = 'pending' AND ${clause} ORDER BY created_at DESC`,
      )
      .all(...params) as MerchantRow[];
  }

  listAllForAdmin(user: UserRow, status?: MerchantOnboardingStatus): MerchantRow[] {
    const scope = resolveAdminScope(user);
    if (scope.isMerchant && scope.merchantId) {
      const m = this.getById(scope.merchantId);
      return m ? [m] : [];
    }
    const db = getDb();
    const { clause, params } = companyFilterSql(user, 'company_id');
    if (status) {
      return db
        .prepare(
          `SELECT * FROM merchants WHERE onboarding_status = ? AND ${clause} ORDER BY created_at DESC`,
        )
        .all(status, ...params) as MerchantRow[];
    }
    return db
      .prepare(
        `SELECT * FROM merchants WHERE ${clause} ORDER BY created_at DESC`,
      )
      .all(...params) as MerchantRow[];
  }

  toAdminDto(row: MerchantRow): AdminMerchantDto {
    const dto = merchantOnboardingDetailToDto(row);
    if (!dto.contactName && row.user_id) {
      const u = getDb()
        .prepare<[string], { name: string }>('SELECT name FROM users WHERE id = ?')
        .get(row.user_id);
      if (u?.name) dto.contactName = u.name;
    }
    dto.supportedMealTypes = mealTypesFromRow(row, row.id);
    return dto;
  }

  listAdminDtos(user: UserRow, status?: MerchantOnboardingStatus): AdminMerchantDto[] {
    return this.listAllForAdmin(user, status).map((m) => this.toAdminDto(m));
  }

  getDetail(id: string, user?: UserRow): MerchantOnboardingDetailDto {
    const row = this.getById(id);
    if (!row) throw new Error('NOT_FOUND');
    if (user) assertMerchantAccess(user, id);
    return this.toAdminDto(row);
  }

  getStatusByPhone(phone: string): MerchantOnboardingStatusDto {
    const normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) {
      return {
        status: 'none',
        merchantId: null,
        rejectReason: '',
        message: '手机号格式不正确',
      };
    }
    const row = findByPhone(normalized);
    if (!row) {
      return {
        status: 'none',
        merchantId: null,
        rejectReason: '',
        message: '该手机号暂无商家账号，请先申请入驻',
      };
    }
    const st = row.onboarding_status;
    if (st === 'pending') {
      return {
        status: 'pending',
        merchantId: row.id,
        rejectReason: '',
        message: '入驻申请审核中，请等待管理员审核',
      };
    }
    if (st === 'rejected') {
      const reason = row.reject_reason?.trim() || '未说明原因';
      return {
        status: 'rejected',
        merchantId: row.id,
        rejectReason: reason,
        message: `入驻申请未通过：${reason}，可重新提交`,
      };
    }
    if (!row.is_enabled) {
      return {
        status: 'approved',
        merchantId: row.id,
        rejectReason: '',
        message: '商家账号已停用，请联系管理员',
      };
    }
    return {
      status: 'approved',
      merchantId: row.id,
      rejectReason: '',
      message: '已审核通过，可正常登录',
    };
  }

  assertMerchantCanLogin(phone: string): MerchantRow {
    const info = this.getStatusByPhone(phone);
    if (info.status === 'none') throw new Error('MERCHANT_NOT_FOUND');
    if (info.status === 'pending') throw new Error('MERCHANT_PENDING');
    if (info.status === 'rejected') {
      const err = new Error('MERCHANT_REJECTED') as Error & {
        rejectReason?: string;
      };
      err.rejectReason = info.rejectReason;
      throw err;
    }
    const row = findByPhone(phone);
    if (!row || !row.is_enabled) throw new Error('MERCHANT_DISABLED');
    if (row.onboarding_status !== 'approved') throw new Error('MERCHANT_PENDING');
    return row;
  }

  linkMerchantUser(merchant: MerchantRow, user: UserRow): void {
    const db = getDb();
    const now = nowIso();
    if (merchant.user_id !== user.id) {
      db.prepare('UPDATE merchants SET user_id = ?, updated_at = ? WHERE id = ?').run(
        user.id,
        now,
        merchant.id,
      );
    }
    if (user.role !== 'merchant') {
      db.prepare('UPDATE users SET role = ?, updated_at = ? WHERE id = ?').run(
        'merchant',
        now,
        user.id,
      );
    }
  }

  createByAdmin(
    user: UserRow,
    input: MerchantRegisterInput & { autoApprove?: boolean },
  ): AdminMerchantDto {
    if (user.role === 'company_admin' && input.companyId !== user.company_id) {
      throw new Error('FORBIDDEN');
    }
    const dto = this.register(input);
    if (input.autoApprove && user.role !== 'merchant') {
      this.review(dto.id, 'approved', user);
    }
    return this.toAdminDto(this.getById(dto.id)!);
  }

  updateByAdmin(
    user: UserRow,
    id: string,
    patch: {
      merchantName?: string;
      address?: string;
      phone?: string;
      companyId?: string;
    },
  ): AdminMerchantDto {
    assertMerchantAccess(user, id);
    const fields: string[] = [];
    const vals: unknown[] = [];
    if (patch.merchantName) {
      fields.push('name = ?');
      vals.push(patch.merchantName.trim());
    }
    if (patch.address) {
      fields.push('address = ?');
      vals.push(patch.address.trim());
    }
    if (patch.phone) {
      fields.push('phone = ?', 'contact_phone = ?');
      vals.push(patch.phone.trim(), patch.phone.trim());
    }
    if (patch.companyId && user.role === 'admin') {
      fields.push('company_id = ?');
      vals.push(patch.companyId);
    }
    if (fields.length) {
      fields.push('updated_at = ?');
      vals.push(nowIso(), id);
      getDb()
        .prepare(`UPDATE merchants SET ${fields.join(', ')} WHERE id = ?`)
        .run(...(vals as never[]));
    }
    return this.toAdminDto(this.getById(id)!);
  }

  private ensureApplicantUser(phone: string, contactName: string): UserRow {
    const db = getDb();
    const normalized = normalizePhone(phone);
    let user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(normalized);
    const now = nowIso();
    if (!user) {
      const id = `u_${nanoid(8)}`;
      const name = contactName.trim() || `商家${normalized.slice(-4)}`;
      const pwdHash = defaultPasswordHash();
      db.prepare(
        `INSERT INTO users
           (id, name, nickname, phone, role, status, company_id, password_hash, password_updated_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'merchant', 'active', ?, ?, ?, ?, ?)`,
      ).run(id, name, name, normalized, DEFAULT_COMPANY_ID, pwdHash, now, now, now);
      user = db.prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?').get(id)!;
    } else if ((user.status ?? 'active') !== 'active') {
      throw new Error('USER_DISABLED');
    }
    return user;
  }

  apply(
    input: MerchantApplyInput,
    audit?: AgreementSignContext,
  ): MerchantOnboardingDetailDto {
    const contactPhone = normalizePhone(input.contactPhone);
    if (!isValidPhone(contactPhone)) throw new Error('INVALID_PHONE');
    if (!input.merchantName?.trim()) throw new Error('INVALID_NAME');
    if (!input.contactName?.trim()) throw new Error('INVALID_CONTACT');
    if (!input.address?.trim()) throw new Error('INVALID_ADDRESS');
    const meals = (input.supportedMealTypes ?? []).filter((m) =>
      ALL_MEALS.includes(m),
    );
    if (!meals.length) throw new Error('INVALID_MEALS');

    const user = this.ensureApplicantUser(contactPhone, input.contactName);
    const existing = findByPhone(contactPhone);
    if (existing?.onboarding_status === 'approved') {
      throw new Error('ALREADY_APPROVED');
    }

    const now = nowIso();
    const companyId = input.companyId ?? DEFAULT_COMPANY_ID;
    const businessDays = normalizeBusinessDays(input.businessDays);
    let mealOpeningHoursJson = '{}';
    let deadlines: Partial<Record<MealType, string>> = {};
    if (
      input.mealOpeningHours &&
      typeof input.mealOpeningHours === 'object' &&
      Object.keys(input.mealOpeningHours).length > 0
    ) {
      validateMealOpeningHours(input.mealOpeningHours);
      const normalized = normalizeMealOpeningHours(input.mealOpeningHours);
      mealOpeningHoursJson = JSON.stringify(normalized);
      deadlines = deriveMealOrderDeadlinesFromOpeningHours(normalized);
    } else {
      deadlines = normalizeDeadlines(input.mealOrderDeadlines);
    }
    // 收款主体类型只接受 individual / company；空字符串视为未填
    const paymentSubjectType =
      input.paymentSubjectType === 'company' || input.paymentSubjectType === 'individual'
        ? input.paymentSubjectType
        : '';

    // 多图字段：优先用 *_Urls 数组，否则回退到单值字段（保证旧调用仍能写入）
    const businessLicenseUrls =
      sanitizeUrls(input.businessLicenseUrls).length
        ? sanitizeUrls(input.businessLicenseUrls)
        : sanitizeUrls(input.businessLicenseUrl ? [input.businessLicenseUrl] : []);
    const foodLicenseUrls =
      sanitizeUrls(input.foodLicenseUrls).length
        ? sanitizeUrls(input.foodLicenseUrls)
        : sanitizeUrls(input.foodLicenseUrl ? [input.foodLicenseUrl] : []);
    const kitchenPhotoUrls =
      sanitizeUrls(input.kitchenPhotoUrls).length
        ? sanitizeUrls(input.kitchenPhotoUrls)
        : sanitizeUrls(input.kitchenPhotoUrl ? [input.kitchenPhotoUrl] : []);
    const healthCertificateUrls =
      sanitizeUrls(input.healthCertificateUrls).length
        ? sanitizeUrls(input.healthCertificateUrls)
        : sanitizeUrls(input.healthCertificateUrl ? [input.healthCertificateUrl] : []);
    const storePhotoUrls =
      sanitizeUrls(input.storePhotoUrls).length
        ? sanitizeUrls(input.storePhotoUrls)
        : sanitizeUrls(input.storePhotoUrl ? [input.storePhotoUrl] : []);
    const wechatQrUrls = sanitizeUrls(input.wechatPaymentQrUrls);
    const alipayQrUrls = sanitizeUrls(input.alipayPaymentQrUrls);

    // 收款方式：优先 paymentMethods 数组；若空则降级 paymentMethod 单值
    const paymentMethods = (() => {
      const arr = sanitizePaymentMethods(input.paymentMethods);
      if (arr.length) return arr;
      if (input.paymentMethod && ALLOWED_PAYMENT_METHODS.has(input.paymentMethod)) {
        return [input.paymentMethod];
      }
      return [];
    })();

    // 兼容旧字段：取每类第一张写回老的单值字段（保证未升级的旧前端 / 旧详情页能看到图）
    const firstOr = (list: string[], fallback: string) =>
      list.length ? list[0] : fallback;
    const legacyPaymentMethod = paymentMethods[0] ?? input.paymentMethod ?? '';
    // 微信收款码兼容写到 payment_qr_code_url；若没有微信但选了支付宝，则用支付宝；否则用兜底
    const legacyPaymentQr =
      firstOr(wechatQrUrls,
        firstOr(alipayQrUrls, input.paymentQr?.trim() || 'qr')) || 'qr';
    const payload = {
      name: input.merchantName.trim(),
      short_name: input.shortName?.trim() || input.merchantName.trim(),
      contact_name: input.contactName.trim(),
      contact_phone: contactPhone,
      phone: contactPhone,
      address: input.address.trim(),
      company_id: companyId,
      supported_meal_types_json: JSON.stringify(meals),
      delivery_modes_json: JSON.stringify(input.deliveryModes ?? []),
      // 兼容旧库字段：入驻页已不再提交这三个字段，写空字符串/0 即可
      delivery_scope: input.deliveryScope?.trim() ?? '',
      estimated_delivery_time: input.estimatedDeliveryTime?.trim() ?? '',
      delivery_fee: input.deliveryFee ?? 0,
      // 旧 payment_method 字段：取多选数组的第一项做兼容
      payment_method: legacyPaymentMethod,
      // 旧单图字段：从对应多图数组取第一张写回，保证旧详情页能看到图
      payment_qr_code_url: legacyPaymentQr,
      payment_receiver_name: input.paymentReceiverName?.trim() ?? '',
      business_license_url: firstOr(businessLicenseUrls,
          input.businessLicenseUrl?.trim() ?? ''),
      food_license_url: firstOr(foodLicenseUrls,
          input.foodLicenseUrl?.trim() ?? ''),
      store_photo_url: firstOr(storePhotoUrls,
          input.storePhotoUrl?.trim() ?? ''),
      remark: input.remark?.trim() ?? '',
      user_id: input.userId ?? user.id,
      onboarding_status: 'pending' as const,
      is_open: 0,
      is_enabled: 0,
      reject_reason: null,
      reviewed_by: null,
      reviewed_at: null,
      updated_at: now,
      // 企业级商家审核扩展字段
      store_display_name: input.storeDisplayName?.trim() ?? '',
      customer_service_phone: input.customerServicePhone?.trim() ?? '',
      served_company_text: input.servedCompanyText?.trim() ?? '',
      business_days_json: JSON.stringify(businessDays),
      business_hours_start: input.businessHoursStart?.trim() ?? '',
      business_hours_end: input.businessHoursEnd?.trim() ?? '',
      meal_opening_hours_json: mealOpeningHoursJson,
      meal_order_deadlines_json: JSON.stringify(deadlines),
      payment_subject_type: paymentSubjectType,
      payment_subject_name: input.paymentSubjectName?.trim() ?? '',
      bank_account_name: input.bankAccountName?.trim() ?? '',
      bank_name: input.bankName?.trim() ?? '',
      bank_account_number: input.bankAccountNumber?.trim() ?? '',
      business_license_subject: input.businessLicenseSubject?.trim() ?? '',
      business_license_valid_until: input.businessLicenseValidUntil?.trim() ?? '',
      unified_social_credit_code: input.unifiedSocialCreditCode?.trim() ?? '',
      food_license_number: input.foodLicenseNumber?.trim() ?? '',
      food_license_valid_until: input.foodLicenseValidUntil?.trim() ?? '',
      licensed_business_scope: input.licensedBusinessScope?.trim() ?? '',
      kitchen_photo_url: firstOr(kitchenPhotoUrls,
          input.kitchenPhotoUrl?.trim() ?? ''),
      health_certificate_url: firstOr(healthCertificateUrls,
          input.healthCertificateUrl?.trim() ?? ''),
      // 多图 / 多选 JSON 列
      payment_methods_json: JSON.stringify(paymentMethods),
      wechat_payment_qr_urls_json: JSON.stringify(wechatQrUrls),
      alipay_payment_qr_urls_json: JSON.stringify(alipayQrUrls),
      business_license_urls_json: JSON.stringify(businessLicenseUrls),
      food_license_urls_json: JSON.stringify(foodLicenseUrls),
      kitchen_photo_urls_json: JSON.stringify(kitchenPhotoUrls),
      health_certificate_urls_json: JSON.stringify(healthCertificateUrls),
      store_photo_urls_json: JSON.stringify(storePhotoUrls),
    };

    const db = getDb();
    if (existing && (existing.onboarding_status === 'rejected' || existing.onboarding_status === 'pending')) {
      db.prepare(
        `UPDATE merchants SET
           user_id = ?, company_id = ?, name = ?, short_name = ?, contact_name = ?, contact_phone = ?,
           phone = ?, address = ?, supported_meal_types_json = ?, delivery_modes_json = ?,
           delivery_scope = ?, estimated_delivery_time = ?, delivery_fee = ?,
           payment_method = ?, payment_qr_code_url = ?, payment_receiver_name = ?,
           business_license_url = ?, food_license_url = ?, store_photo_url = ?, remark = ?,
           store_display_name = ?, customer_service_phone = ?, served_company_text = ?,
           business_days_json = ?, business_hours_start = ?, business_hours_end = ?,
           meal_opening_hours_json = ?, meal_order_deadlines_json = ?,
           payment_subject_type = ?, payment_subject_name = ?,
           bank_account_name = ?, bank_name = ?, bank_account_number = ?,
           business_license_subject = ?, business_license_valid_until = ?,
           unified_social_credit_code = ?, food_license_number = ?,
           food_license_valid_until = ?, licensed_business_scope = ?,
           kitchen_photo_url = ?, health_certificate_url = ?,
           payment_methods_json = ?, wechat_payment_qr_urls_json = ?,
           alipay_payment_qr_urls_json = ?, business_license_urls_json = ?,
           food_license_urls_json = ?, kitchen_photo_urls_json = ?,
           health_certificate_urls_json = ?, store_photo_urls_json = ?,
           onboarding_status = 'pending', is_open = 0, is_enabled = 0,
           reject_reason = NULL, reviewed_by = NULL, reviewed_at = NULL, updated_at = ?
         WHERE id = ?`,
      ).run(
        payload.user_id,
        payload.company_id,
        payload.name,
        payload.short_name,
        payload.contact_name,
        payload.contact_phone,
        payload.phone,
        payload.address,
        payload.supported_meal_types_json,
        payload.delivery_modes_json,
        payload.delivery_scope,
        payload.estimated_delivery_time,
        payload.delivery_fee,
        payload.payment_method,
        payload.payment_qr_code_url,
        payload.payment_receiver_name,
        payload.business_license_url,
        payload.food_license_url,
        payload.store_photo_url,
        payload.remark,
        payload.store_display_name,
        payload.customer_service_phone,
        payload.served_company_text,
        payload.business_days_json,
        payload.business_hours_start,
        payload.business_hours_end,
        payload.meal_opening_hours_json,
        payload.meal_order_deadlines_json,
        payload.payment_subject_type,
        payload.payment_subject_name,
        payload.bank_account_name,
        payload.bank_name,
        payload.bank_account_number,
        payload.business_license_subject,
        payload.business_license_valid_until,
        payload.unified_social_credit_code,
        payload.food_license_number,
        payload.food_license_valid_until,
        payload.licensed_business_scope,
        payload.kitchen_photo_url,
        payload.health_certificate_url,
        payload.payment_methods_json,
        payload.wechat_payment_qr_urls_json,
        payload.alipay_payment_qr_urls_json,
        payload.business_license_urls_json,
        payload.food_license_urls_json,
        payload.kitchen_photo_urls_json,
        payload.health_certificate_urls_json,
        payload.store_photo_urls_json,
        now,
        existing.id,
      );
      this.recordAgreementIfPresent(existing.id, input, audit);
      return merchantOnboardingDetailToDto(this.getById(existing.id)!);
    }

    const id = `m_${nanoid(8)}`;
    db.prepare(
      `INSERT INTO merchants
         (id, user_id, company_id, name, short_name, contact_name, contact_phone, phone, address,
          logo_url, distance_text, distance, rating, month_sold, hygiene_grade,
          is_open, is_enabled, onboarding_status, menu_init, payment_qr_code_url,
          delivery_fee, supported_meal_types_json, delivery_modes_json, delivery_scope,
          estimated_delivery_time, payment_method, payment_receiver_name,
          business_license_url, food_license_url, store_photo_url, remark,
          store_display_name, customer_service_phone, served_company_text,
          business_days_json, business_hours_start, business_hours_end,
          meal_opening_hours_json, meal_order_deadlines_json,
          payment_subject_type, payment_subject_name,
          bank_account_name, bank_name, bank_account_number,
          business_license_subject, business_license_valid_until,
          unified_social_credit_code, food_license_number,
          food_license_valid_until, licensed_business_scope,
          kitchen_photo_url, health_certificate_url,
          payment_methods_json, wechat_payment_qr_urls_json,
          alipay_payment_qr_urls_json, business_license_urls_json,
          food_license_urls_json, kitchen_photo_urls_json,
          health_certificate_urls_json, store_photo_urls_json,
          reject_reason, reviewed_by, reviewed_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'logo', '0m', 0, 0, 0, 'A',
               0, 0, 'pending', 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?, ?, ?,
               NULL, NULL, NULL, ?, ?)`,
    ).run(
      id,
      payload.user_id,
      payload.company_id,
      payload.name,
      payload.short_name,
      payload.contact_name,
      payload.contact_phone,
      payload.phone,
      payload.address,
      payload.payment_qr_code_url,
      payload.delivery_fee,
      payload.supported_meal_types_json,
      payload.delivery_modes_json,
      payload.delivery_scope,
      payload.estimated_delivery_time,
      payload.payment_method,
      payload.payment_receiver_name,
      payload.business_license_url,
      payload.food_license_url,
      payload.store_photo_url,
      payload.remark,
      payload.store_display_name,
      payload.customer_service_phone,
      payload.served_company_text,
      payload.business_days_json,
      payload.business_hours_start,
      payload.business_hours_end,
      payload.meal_opening_hours_json,
      payload.meal_order_deadlines_json,
      payload.payment_subject_type,
      payload.payment_subject_name,
      payload.bank_account_name,
      payload.bank_name,
      payload.bank_account_number,
      payload.business_license_subject,
      payload.business_license_valid_until,
      payload.unified_social_credit_code,
      payload.food_license_number,
      payload.food_license_valid_until,
      payload.licensed_business_scope,
      payload.kitchen_photo_url,
      payload.health_certificate_url,
      payload.payment_methods_json,
      payload.wechat_payment_qr_urls_json,
      payload.alipay_payment_qr_urls_json,
      payload.business_license_urls_json,
      payload.food_license_urls_json,
      payload.kitchen_photo_urls_json,
      payload.health_certificate_urls_json,
      payload.store_photo_urls_json,
      now,
      now,
    );
    this.recordAgreementIfPresent(id, input, audit);
    return merchantOnboardingDetailToDto(this.getById(id)!);
  }

  private recordAgreementIfPresent(
    merchantId: string,
    input: MerchantApplyInput,
    audit?: AgreementSignContext,
  ): void {
    const version = input.agreementVersion?.trim();
    if (!version) return;
    merchantAgreementService.recordSign({
      merchantId,
      agreementVersion: version,
      ipAddress: audit?.ipAddress,
      userAgent: input.deviceInfo?.trim() || audit?.userAgent,
      clientTime: input.clientTime,
    });
  }

  resubmit(
    id: string,
    input: MerchantApplyInput,
    user?: UserRow,
    audit?: AgreementSignContext,
  ): MerchantOnboardingDetailDto {
    const row = this.getById(id);
    if (!row) throw new Error('NOT_FOUND');
    if (row.onboarding_status !== 'rejected') throw new Error('NOT_REJECTED');
    if (user) {
      const phone = normalizePhone(input.contactPhone);
      const linked =
        row.user_id === user.id ||
        normalizePhone(row.contact_phone ?? row.phone ?? '') === phone ||
        user.phone === phone;
      if (!linked) throw new Error('FORBIDDEN');
    }
    return this.apply(
      { ...input, userId: row.user_id ?? input.userId },
      audit,
    );
  }

  register(input: MerchantRegisterInput): ReturnType<typeof merchantOnboardingToDto> {
    const db = getDb();
    const now = nowIso();
    const id = `m_${nanoid(8)}`;
    const phone = normalizePhone(input.phone);
    db.prepare(
      `INSERT INTO merchants
         (id, user_id, company_id, name, address, phone, contact_phone,
          logo_url, distance_text, distance, rating, month_sold,
          hygiene_grade, is_open, is_enabled, onboarding_status,
          menu_init, payment_qr_code_url, delivery_fee, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'logo', '0m', 0, 0, 0, 'A', 0, 0, 'pending', ?, ?, 3, ?, ?)`,
    ).run(
      id,
      input.userId ?? null,
      input.companyId,
      input.merchantName.trim(),
      input.address.trim(),
      phone,
      phone,
      input.menuInit ? 1 : 0,
      input.paymentQr ?? 'qr',
      now,
      now,
    );
    return merchantOnboardingToDto(this.getById(id)!);
  }

  getById(id: string): MerchantRow | undefined {
    return getDb()
      .prepare<[string], MerchantRow>('SELECT * FROM merchants WHERE id = ?')
      .get(id);
  }

  review(
    id: string,
    status: 'approved' | 'rejected',
    reviewer: UserRow,
    rejectReason?: string,
  ): MerchantRow {
    const merchant = this.getById(id);
    if (!merchant) throw new Error('NOT_FOUND');
    if (reviewer.role === 'company_admin') {
      if (merchant.company_id !== reviewer.company_id) {
        throw new Error('FORBIDDEN');
      }
    }
    if (reviewer.role === 'merchant') {
      throw new Error('FORBIDDEN');
    }
    if (status === 'rejected' && !rejectReason?.trim()) {
      throw new Error('REJECT_REASON_REQUIRED');
    }
    const now = nowIso();
    const db = getDb();
    const isEnabled = status === 'approved' ? 1 : 0;
    const isOpen = status === 'approved' ? 1 : 0;
    db.prepare(
      `UPDATE merchants SET onboarding_status = ?, is_enabled = ?, is_open = ?,
         reject_reason = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ?
       WHERE id = ?`,
    ).run(
      status,
      isEnabled,
      isOpen,
      status === 'rejected' ? rejectReason!.trim() : null,
      reviewer.id,
      now,
      now,
      id,
    );

    const updated = this.getById(id)!;
    if (status === 'approved') {
      const phone = updated.contact_phone ?? updated.phone ?? '';
      let user =
        (updated.user_id
          ? db.prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?').get(updated.user_id)
          : undefined) ??
        (phone
          ? db.prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?').get(phone)
          : undefined);
      if (!user && phone) {
        const contactName = updated.contact_name ?? updated.name ?? '';
        user = this.ensureApplicantUser(phone, contactName);
      }
      if (user) {
        passwordAuthService.ensureUserHasPassword(user.id);
        this.linkMerchantUser(updated, user);
      }
    }
    return updated;
  }

  setEnabled(id: string, enabled: boolean, user: UserRow): MerchantRow {
    const merchant = this.getById(id);
    if (!merchant) throw new Error('NOT_FOUND');
    this.assertMerchantRowAccess(user, merchant);
    if (user.role === 'merchant') throw new Error('FORBIDDEN');
    getDb()
      .prepare('UPDATE merchants SET is_enabled = ?, updated_at = ? WHERE id = ?')
      .run(enabled ? 1 : 0, nowIso(), id);
    return this.getById(id)!;
  }

  updatePaymentQr(id: string, paymentQr: string, user: UserRow): MerchantRow {
    const merchant = this.getById(id);
    if (!merchant) throw new Error('NOT_FOUND');
    assertMerchantAccess(user, id);
    getDb()
      .prepare(
        'UPDATE merchants SET payment_qr_code_url = ?, updated_at = ? WHERE id = ?',
      )
      .run(paymentQr, nowIso(), id);
    return this.getById(id)!;
  }

  updateOpen(id: string, isOpen: boolean, user: UserRow): MerchantRow {
    const merchant = this.getById(id);
    if (!merchant) throw new Error('NOT_FOUND');
    assertMerchantAccess(user, id);
    getDb()
      .prepare('UPDATE merchants SET is_open = ?, updated_at = ? WHERE id = ?')
      .run(isOpen ? 1 : 0, nowIso(), id);
    return this.getById(id)!;
  }

  private assertMerchantRowAccess(user: UserRow, merchant: MerchantRow): void {
    if (user.role === 'merchant') {
      if (merchant.user_id !== user.id) throw new Error('FORBIDDEN');
      return;
    }
    if (user.role === 'company_admin' && merchant.company_id !== user.company_id) {
      throw new Error('FORBIDDEN');
    }
  }
}

export const merchantOnboardingService = new MerchantOnboardingService();
