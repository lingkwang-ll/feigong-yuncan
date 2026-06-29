import {
  ALL_DISH_CATEGORIES,
  ConversationDto,
  ConversationMessageDto,
  ConversationMessageRow,
  ConversationRow,
  DeliveryLocationDto,
  DeliveryLocationRow,
  DishCategory,
  DishDto,
  DishRow,
  EmployeeProfileDto,
  EmployeeProfileRow,
  MealType,
  MerchantDto,
  MerchantRow,
  OrderDto,
  OrderExtraItemDto,
  OrderItemRow,
  OrderRow,
  OrderSelectedItemDto,
  PackageDto,
  PackageRow,
  PackageRules,
  ReviewDto,
  ReviewRow,
  UserDto,
  UserRow,
} from './types';
import { resolveEmployeeProfileStatus } from '../utils/employee-profile.util';
import {
  buildOrderItemsSummary,
  OrderDisplayLookup,
  resolveDishDisplayName,
  resolveMerchantDisplayName,
  resolvePackageDisplayName,
} from '../utils/display-text.util';

export function userToDto(
  row: UserRow,
  employeeProfileStatus?: import('./types').EmployeeProfileBindStatus,
): UserDto {
  const nickname = row.nickname ?? row.name;
  const dto: UserDto = {
    id: row.id,
    name: nickname,
    nickname,
    phone: row.phone,
    role: row.role,
    status: row.status ?? 'active',
    companyId: row.company_id ?? null,
    avatarUrl: row.avatar_url ?? null,
  };
  if (employeeProfileStatus) {
    dto.employeeProfileStatus = employeeProfileStatus;
  }
  return dto;
}

export function companyToDto(row: import('./types').CompanyRow): import('./types').CompanyDto {
  return {
    id: row.id,
    companyName: row.company_name,
    adminUserId: row.admin_user_id,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function parseJsonArray<T = string>(raw: string | null | undefined): T[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

export function merchantOnboardingToDto(row: MerchantRow): import('./types').MerchantOnboardingDto {
  return {
    id: row.id,
    merchantName: row.name,
    address: row.address ?? '',
    phone: row.contact_phone ?? row.phone ?? '',
    companyId: row.company_id ?? '',
    status: row.onboarding_status ?? 'approved',
    menuInit: !!row.menu_init,
    paymentQr: row.payment_qr_code_url ?? '',
    userId: row.user_id,
    isOpen: !!row.is_open,
    isEnabled: !!row.is_enabled,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function merchantOnboardingDetailToDto(
  row: MerchantRow,
): import('./types').MerchantOnboardingDetailDto {
  const base = merchantOnboardingToDto(row);
  const storedMeals = parseJsonArray<MealType>(row.supported_meal_types_json);
  let mealOrderDeadlines: Partial<Record<MealType, string>> = {};
  try {
    const parsed = JSON.parse(row.meal_order_deadlines_json || '{}');
    if (parsed && typeof parsed === 'object') {
      mealOrderDeadlines = parsed as Partial<Record<MealType, string>>;
    }
  } catch {
    mealOrderDeadlines = {};
  }
  return {
    ...base,
    shortName: row.short_name ?? '',
    contactName: row.contact_name ?? '',
    contactPhone: row.contact_phone ?? row.phone ?? '',
    supportedMealTypes: storedMeals,
    deliveryModes: parseJsonArray(row.delivery_modes_json),
    deliveryScope: row.delivery_scope ?? '',
    estimatedDeliveryTime: row.estimated_delivery_time ?? '',
    deliveryFee: row.delivery_fee ?? 0,
    paymentMethod: row.payment_method ?? '',
    paymentReceiverName: row.payment_receiver_name ?? '',
    businessLicenseUrl: row.business_license_url ?? '',
    foodLicenseUrl: row.food_license_url ?? '',
    storePhotoUrl: row.store_photo_url ?? '',
    rejectReason: row.reject_reason ?? '',
    reviewedBy: row.reviewed_by ?? null,
    reviewedAt: row.reviewed_at ?? null,
    remark: row.remark ?? '',
    storeDisplayName: row.store_display_name ?? '',
    customerServicePhone: row.customer_service_phone ?? '',
    servedCompanyText: row.served_company_text ?? '',
    businessDays: parseJsonArray<string>(row.business_days_json),
    businessHoursStart: row.business_hours_start ?? '',
    businessHoursEnd: row.business_hours_end ?? '',
    mealOrderDeadlines,
    paymentSubjectType: row.payment_subject_type ?? '',
    paymentSubjectName: row.payment_subject_name ?? '',
    bankAccountName: row.bank_account_name ?? '',
    bankName: row.bank_name ?? '',
    bankAccountNumber: row.bank_account_number ?? '',
    businessLicenseSubject: row.business_license_subject ?? '',
    businessLicenseValidUntil: row.business_license_valid_until ?? '',
    unifiedSocialCreditCode: row.unified_social_credit_code ?? '',
    foodLicenseNumber: row.food_license_number ?? '',
    foodLicenseValidUntil: row.food_license_valid_until ?? '',
    licensedBusinessScope: row.licensed_business_scope ?? '',
    kitchenPhotoUrl: row.kitchen_photo_url ?? '',
    healthCertificateUrl: row.health_certificate_url ?? '',
    paymentMethods: resolvePaymentMethods(row),
    wechatPaymentQrUrls: resolveUrlList(
      row.wechat_payment_qr_urls_json,
      // 旧库未来有微信收款码时落在 payment_qr_code_url 上
      row.payment_qr_code_url,
    ),
    alipayPaymentQrUrls: resolveUrlList(row.alipay_payment_qr_urls_json),
    businessLicenseUrls: resolveUrlList(
      row.business_license_urls_json,
      row.business_license_url,
    ),
    foodLicenseUrls: resolveUrlList(
      row.food_license_urls_json,
      row.food_license_url,
    ),
    kitchenPhotoUrls: resolveUrlList(
      row.kitchen_photo_urls_json,
      row.kitchen_photo_url,
    ),
    healthCertificateUrls: resolveUrlList(
      row.health_certificate_urls_json,
      row.health_certificate_url,
    ),
    storePhotoUrls: resolveUrlList(
      row.store_photo_urls_json,
      row.store_photo_url,
    ),
  };
}

/**
 * 解析多图 JSON 列；若数组为空且老的单图字段非空，则把老字段作为兜底返回，
 * 保证历史商家在后台详情页仍能看到图片。
 */
function resolveUrlList(json: string | null, legacy?: string | null): string[] {
  const arr = parseJsonArray<string>(json)
    .map((s) => (typeof s === 'string' ? s.trim() : ''))
    .filter((s) => s.length > 0);
  if (arr.length) return arr;
  if (legacy && legacy.trim() && !isPlaceholderImage(legacy.trim())) {
    return [legacy.trim()];
  }
  return [];
}

function resolvePrimaryPaymentQrUrl(
  singular: string | null | undefined,
  json: string | null | undefined,
  legacy?: string | null,
): string {
  const s = singular?.trim();
  if (s && !isPlaceholderImage(s)) return s;
  const fromList = resolveUrlList(json ?? null);
  if (fromList.length > 0) return fromList[0]!;
  if (legacy && legacy.trim() && !isPlaceholderImage(legacy.trim())) {
    return legacy.trim();
  }
  return '';
}

/** 老 seed 数据里 payment_qr_code_url 可能写 'qr' 占位，不应作为图片返回 */
function isPlaceholderImage(url: string): boolean {
  return url === 'qr' || url === 'logo' || url === 'dish' || url === 'cover';
}

function resolvePaymentMethods(row: MerchantRow): string[] {
  const arr = parseJsonArray<string>(row.payment_methods_json)
    .map((s) => (typeof s === 'string' ? s.trim() : ''))
    .filter((s) => s.length > 0);
  if (arr.length) return arr;
  const legacy = (row.payment_method ?? '').trim();
  if (legacy) {
    // 老字段可能存了逗号分隔或单值
    return legacy
      .split(/[,，;；\s]+/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  }
  return [];
}

export function employeeProfileToDto(row: EmployeeProfileRow): EmployeeProfileDto {
  return {
    id: row.id,
    userId: row.user_id,
    employeeName: row.employee_name,
    employeeNo: row.employee_no,
    phone: row.phone,
    departmentId: row.department_id ?? '',
    departmentName: row.department_name,
    roleType: row.role_type,
    bindStatus: row.bind_status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function userToDtoWithProfileStatus(
  row: UserRow,
  profile?: EmployeeProfileRow,
): UserDto {
  return userToDto(row, resolveEmployeeProfileStatus(profile));
}

export function merchantToDto(row: MerchantRow): MerchantDto {
  let deliveryModes: string[] = [];
  let supportedMealTypes: MealType[] = [];
  let mealOpeningHours: Record<string, { enabled?: boolean; hours?: string }> =
    {};
  try {
    const dm = JSON.parse(row.delivery_modes_json || '[]');
    if (Array.isArray(dm)) deliveryModes = dm.map(String);
  } catch {
    deliveryModes = [];
  }
  try {
    const sm = JSON.parse(row.supported_meal_types_json || '[]');
    if (Array.isArray(sm)) supportedMealTypes = sm as MealType[];
  } catch {
    supportedMealTypes = [];
  }
  try {
    const mh = JSON.parse(row.meal_opening_hours_json || '{}');
    if (mh && typeof mh === 'object') {
      mealOpeningHours = mh as Record<
        string,
        { enabled?: boolean; hours?: string }
      >;
    }
  } catch {
    mealOpeningHours = {};
  }
  // 商家自定义订餐截止时间（员工端首页 / 后端下单校验都会优先使用）
  let mealOrderDeadlines: Partial<Record<MealType, string>> = {};
  try {
    const parsed = JSON.parse(row.meal_order_deadlines_json || '{}');
    if (parsed && typeof parsed === 'object') {
      mealOrderDeadlines = parsed as Partial<Record<MealType, string>>;
    }
  } catch {
    mealOrderDeadlines = {};
  }
  const storePhoto = row.store_photo_url?.trim();
  const wechatPaymentQrUrl = resolvePrimaryPaymentQrUrl(
    row.wechat_payment_qr_url,
    row.wechat_payment_qr_urls_json,
    row.payment_qr_code_url,
  );
  const alipayPaymentQrUrl = resolvePrimaryPaymentQrUrl(
    row.alipay_payment_qr_url,
    row.alipay_payment_qr_urls_json,
  );
  return {
    id: row.id,
    name: row.name,
    logo: row.logo_url ?? 'logo',
    coverImage: storePhoto && storePhoto.length ? storePhoto : 'cover',
    distance: row.distance ?? 0,
    rating: row.rating ?? 0,
    monthSold: row.month_sold ?? 0,
    hygieneGrade: row.hygiene_grade ?? '—',
    hygieneScore: row.hygiene_score ?? null,
    hygieneScore30d: row.hygiene_score_30d ?? null,
    hygieneReviewCount: row.hygiene_review_count ?? 0,
    hygieneRiskStatus: row.hygiene_risk_status ?? 'normal',
    isOpen: !!row.is_open && !!row.is_enabled && row.onboarding_status === 'approved',
    address: row.address ?? '',
    paymentQrCode: row.payment_qr_code_url ?? 'qr',
    wechatPaymentQrUrl,
    alipayPaymentQrUrl,
    deliveryFee: row.delivery_fee ?? 0,
    contactName: row.contact_name ?? '',
    contactPhone: row.contact_phone ?? row.phone ?? '',
    description: row.description ?? '',
    deliveryModes,
    deliveryScope: row.delivery_scope ?? '',
    estimatedDeliveryTime: row.estimated_delivery_time ?? '',
    supportedMealTypes,
    mealOpeningHours,
    mealOrderDeadlines,
  };
}

export function dishToDto(row: DishRow): DishDto {
  let tags: string[] = [];
  try {
    const parsed = JSON.parse(row.tags_json || '[]');
    if (Array.isArray(parsed)) tags = parsed.map(String);
  } catch {
    tags = [];
  }
  // mealTypes：优先用 meal_types_json 数组，否则兜底 meal_type 单值
  const mealTypes = parseJsonArray<MealType>(row.meal_types_json).filter(
    (m): m is MealType =>
      m === 'breakfast' || m === 'lunch' || m === 'dinner' || m === 'overtime',
  );
  if (mealTypes.length === 0 && row.meal_type) mealTypes.push(row.meal_type);
  return {
    id: row.id,
    merchantId: row.merchant_id,
    name: row.name,
    image: row.image_url ?? 'dish',
    description: row.description ?? '',
    price: row.price,
    mealType: row.meal_type,
    tags,
    isAvailable: !!row.is_available,
    isSoldOut: !!row.is_sold_out,
    sortOrder: row.sort_order ?? 0,
    category: normalizeDishCategory(row.category),
    extraPrice: typeof row.extra_price === 'number' ? row.extra_price : 0,
    mealTypes,
  };
}

export function normalizeDishCategory(
  raw: string | null | undefined,
): DishCategory {
  const v = (raw ?? '').trim();
  if (!v) return '';
  if (ALL_DISH_CATEGORIES.includes(v as DishCategory)) {
    return v as DishCategory;
  }
  // 兼容历史/手工录入的中文分类
  switch (v) {
    case '荤菜':
    case '荤':
      return 'meat';
    case '素菜':
    case '素':
      return 'vegetable';
    case '主食':
      return 'staple';
    case '汤品':
    case '汤':
      return 'soup';
    case '饮品':
      return 'drink';
    case '加菜':
      return 'extra';
    default:
      return '';
  }
}

/**
 * 解析套餐规则：保证 value 为非负整数；非法 key 跳过。
 */
export function parsePackageRules(json: string | null | undefined): PackageRules {
  if (!json) return {};
  try {
    const obj = JSON.parse(json);
    if (!obj || typeof obj !== 'object') return {};
    const out: PackageRules = {};
    for (const cat of ['meat', 'vegetable', 'staple', 'soup', 'drink'] as const) {
      const v = (obj as Record<string, unknown>)[cat];
      if (typeof v === 'number' && v >= 0 && Number.isFinite(v)) {
        const n = Math.floor(v);
        if (n > 0) out[cat] = n;
      }
    }
    return out;
  } catch {
    return {};
  }
}

export function packageToDto(row: PackageRow): PackageDto {
  return {
    id: row.id,
    merchantId: row.merchant_id,
    name: row.name,
    description: row.description ?? '',
    basePrice: typeof row.base_price === 'number' ? row.base_price : 0,
    mealTypes: parseJsonArray<MealType>(row.meal_types_json).filter(
      (m): m is MealType =>
        m === 'breakfast' || m === 'lunch' || m === 'dinner' || m === 'overtime',
    ),
    rules: parsePackageRules(row.rules_json),
    allowExtra: !!row.allow_extra,
    extraDishIds: parseJsonArray<string>(row.extra_dish_ids_json),
    isEnabled: !!row.is_enabled,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** 解析订单的 selected_items_json，做基础防御 */
export function parseOrderSelectedItems(
  json: string | null | undefined,
): OrderSelectedItemDto[] {
  if (!json) return [];
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((x) => x && typeof x === 'object')
      .map((x) => {
        const o = x as Record<string, unknown>;
        return {
          dishId: String(o.dishId ?? ''),
          name: String(o.name ?? ''),
          category: normalizeDishCategory(
            typeof o.category === 'string' ? o.category : '',
          ),
          mealType: (typeof o.mealType === 'string'
            ? (o.mealType as MealType)
            : null) ?? null,
        };
      });
  } catch {
    return [];
  }
}

export function parseOrderExtraItems(
  json: string | null | undefined,
): OrderExtraItemDto[] {
  if (!json) return [];
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((x) => x && typeof x === 'object')
      .map((x) => {
        const o = x as Record<string, unknown>;
        const unitPrice =
          typeof o.unitPrice === 'number' ? o.unitPrice : 0;
        const quantity = typeof o.quantity === 'number' ? o.quantity : 0;
        return {
          dishId: String(o.dishId ?? ''),
          name: String(o.name ?? ''),
          unitPrice,
          quantity,
          subtotal:
            typeof o.subtotal === 'number'
              ? o.subtotal
              : Number((unitPrice * quantity).toFixed(2)),
        };
      });
  } catch {
    return [];
  }
}

export function orderToDto(
  order: OrderRow,
  items: OrderItemRow[],
  lookup: OrderDisplayLookup = {},
): OrderDto {
  const displayMerchantName = resolveMerchantDisplayName(
    order.merchant_name,
    lookup.merchantNameFromDb,
  );
  const displayPackageName = order.package_id
    ? resolvePackageDisplayName(order.package_name)
    : null;
  const itemsSummary = buildOrderItemsSummary(order, items, lookup);

  const selectedItems = parseOrderSelectedItems(order.selected_items_json).map(
    (s) => ({
      ...s,
      name: resolveDishDisplayName(
        s.name,
        s.dishId ? lookup.dishNameById?.get(s.dishId) : undefined,
      ),
    }),
  );
  const extraItems = parseOrderExtraItems(order.extra_items_json).map((e) => ({
    ...e,
    name: resolveDishDisplayName(
      e.name,
      e.dishId ? lookup.dishNameById?.get(e.dishId) : undefined,
    ),
  }));

  return {
    id: order.id,
    orderNo: order.order_no,
    merchantId: order.merchant_id,
    merchantName: displayMerchantName,
    displayMerchantName,
    displayPackageName,
    itemsSummary,
    customerName: order.user_name ?? '',
    customerCompany: order.user_company ?? '',
    items: items.map((item) => ({
      dish: {
        id: item.dish_id ?? '',
        merchantId: order.merchant_id,
        name: resolveDishDisplayName(
          item.dish_name,
          item.dish_id ? lookup.dishNameById?.get(item.dish_id) : undefined,
        ),
        image: item.dish_image_url ?? 'dish',
        description: item.dish_description ?? '',
        price: item.price,
        mealType: item.meal_type ?? 'lunch',
        tags: [],
        isAvailable: true,
        isSoldOut: false,
        sortOrder: 0,
        category: '',
        extraPrice: 0,
        mealTypes: item.meal_type ? [item.meal_type] : [],
      },
      quantity: item.quantity,
    })),
    deliveryType: order.delivery_type,
    address: order.address ?? '',
    phone: order.phone ?? '',
    remark: order.remark ?? '',
    goodsAmount: order.goods_amount,
    deliveryFee: order.delivery_fee,
    totalAmount: order.total_amount,
    status: order.status,
    paymentType: order.payment_type ?? 'self_pay',
    paymentScreenshot: order.payment_screenshot_url,
    manualPayChannel: order.manual_pay_channel ?? null,
    rejectReason: order.reject_reason,
    isMealCollector: !!order.is_meal_collector,
    collectorName: order.collector_name ?? '',
    collectorPhone: order.collector_phone ?? '',
    collectorAddress: order.collector_address ?? '',
    collectorLatitude: order.collector_latitude,
    collectorLongitude: order.collector_longitude,
    collectorPoiName: order.collector_poi_name ?? '',
    collectorAddressText: order.collector_address_text ?? '',
    // 套餐订单扩展字段；非套餐订单回退到 null / 空数组 / 0
    packageId: order.package_id ?? null,
    packageName: order.package_id
      ? resolvePackageDisplayName(order.package_name)
      : order.package_name ?? null,
    packageBasePrice:
      typeof order.package_base_price === 'number'
        ? order.package_base_price
        : 0,
    selectedItems,
    extraItems,
    extraAmount:
      typeof order.extra_amount === 'number' ? order.extra_amount : 0,
    finalAmount:
      typeof order.final_amount === 'number'
        ? order.final_amount
        : order.total_amount,
    packageAmount:
      typeof order.package_amount === 'number'
        ? order.package_amount
        : typeof order.package_base_price === 'number'
          ? order.package_base_price
          : order.goods_amount,
    companyPayAmount:
      typeof order.company_pay_amount === 'number'
        ? order.company_pay_amount
        : order.payment_type === 'company_pay'
          ? order.total_amount
          : 0,
    employeePayAmount:
      typeof order.employee_pay_amount === 'number'
        ? order.employee_pay_amount
        : order.payment_type === 'self_pay' || order.payment_type === 'mixed_pay'
          ? order.total_amount
          : 0,
    couponClaimId: order.coupon_claim_id ?? null,
    couponDiscountAmount:
      typeof order.coupon_discount_amount === 'number'
        ? order.coupon_discount_amount
        : 0,
    employeePayBeforeCoupon:
      typeof order.employee_pay_before_coupon === 'number'
        ? order.employee_pay_before_coupon
        : typeof order.employee_pay_amount === 'number'
          ? order.employee_pay_amount
          : 0,
    settlementStatus: order.settlement_status ?? 'not_paid',
    paymentChannel: order.payment_channel ?? 'manual_qr',
    completedAt: order.completed_at ?? null,
    settlementEligibleAt: order.settlement_eligible_at ?? null,
    createdAt: order.created_at,
  };
}

export function reviewToDto(
  row: ReviewRow,
  images: string[],
  extra?: {
    displayUserName?: string;
    departmentName?: string;
    orderNo?: string;
  },
): ReviewDto {
  const overall = row.overall_rating ?? row.rating;
  const taste = row.taste_rating ?? overall;
  const hygiene = row.hygiene_rating ?? overall;
  const service = row.service_rating ?? overall;
  const delivery = row.delivery_rating ?? overall;
  const isAnonymous = !!row.is_anonymous;
  return {
    id: row.id,
    orderId: row.order_id,
    merchantId: row.merchant_id,
    userId: row.user_id,
    rating: overall,
    overallRating: overall,
    tasteRating: taste,
    hygieneRating: hygiene,
    serviceRating: service,
    deliveryRating: delivery,
    content: row.content ?? '',
    images,
    isAnonymous,
    displayUserName: extra?.displayUserName ?? (isAnonymous ? '匿名用户' : '员工'),
    departmentName: extra?.departmentName ?? '',
    orderNo: extra?.orderNo ?? '',
    createdAt: row.created_at,
  };
}

export function deliveryLocationToDto(row: DeliveryLocationRow): DeliveryLocationDto {
  return {
    latitude: row.latitude,
    longitude: row.longitude,
    addressText: row.address_text ?? '',
    status: row.status,
    updatedAt: row.updated_at,
    orderBatchKey: row.order_batch_key,
    date: row.date,
    mealType: row.meal_type,
    merchantId: row.merchant_id,
  };
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function conversationToDto(
  row: ConversationRow,
  extra?: {
    orderNo?: string | null;
    orderStatus?: import('./types').OrderStatus | null;
    employeeName?: string | null;
    merchantName?: string | null;
  },
): ConversationDto {
  return {
    id: row.id,
    type: row.type,
    orderId: row.order_id,
    merchantId: row.merchant_id,
    employeeId: row.employee_id,
    lastMessageText: row.last_message_text,
    lastMessageAt: row.last_message_at,
    employeeUnreadCount: row.employee_unread_count,
    merchantUnreadCount: row.merchant_unread_count,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    orderNo: extra?.orderNo ?? null,
    orderStatus: extra?.orderStatus ?? null,
    employeeName: extra?.employeeName ?? null,
    merchantName: extra?.merchantName ?? null,
  };
}

export function conversationMessageToDto(
  row: ConversationMessageRow,
): ConversationMessageDto {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    senderType: row.sender_type,
    senderId: row.sender_id,
    messageType: row.message_type,
    content: row.content,
    imageUrl: row.image_url,
    createdAt: row.created_at,
    readAt: row.read_at,
  };
}

export function supportConversationToDto(
  row: import('./types').SupportConversationRow,
  extra?: {
    userName?: string | null;
    userPhone?: string | null;
    merchantName?: string | null;
  },
): import('./types').SupportConversationDto {
  return {
    id: row.id,
    userId: row.user_id,
    userRole: row.user_role,
    merchantId: row.merchant_id,
    title: row.title,
    status: row.status,
    lastMessageText: row.last_message_text,
    lastMessageAt: row.last_message_at,
    userUnreadCount: row.user_unread_count,
    adminUnreadCount: row.admin_unread_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    userName: extra?.userName ?? null,
    userPhone: extra?.userPhone ?? null,
    merchantName: extra?.merchantName ?? null,
  };
}

export function supportMessageToDto(
  row: import('./types').SupportMessageRow,
): import('./types').SupportMessageDto {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    senderType: row.sender_type,
    senderId: row.sender_id,
    messageType: row.message_type,
    content: row.content,
    imageUrl: row.image_url,
    createdAt: row.created_at,
    readAt: row.read_at,
  };
}
