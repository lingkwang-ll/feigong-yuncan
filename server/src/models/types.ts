/* eslint-disable @typescript-eslint/no-explicit-any */

export type UserRole = 'admin' | 'company_admin' | 'employee' | 'merchant';

export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'overtime';

export type DeliveryType = 'delivery' | 'selfPickup';

export type OrderStatus =
  | 'pendingPayment'
  | 'paymentSubmitted'
  | 'pendingMerchantConfirm'
  | 'accepted'
  | 'delivering'
  | 'completed'
  | 'cancelled';

export const ALL_ORDER_STATUSES: OrderStatus[] = [
  'pendingPayment',
  'paymentSubmitted',
  'pendingMerchantConfirm',
  'accepted',
  'delivering',
  'completed',
  'cancelled',
];

export type PaymentType = 'self_pay' | 'company_pay' | 'mixed_pay';

export const ALL_PAYMENT_TYPES: PaymentType[] = [
  'self_pay',
  'company_pay',
  'mixed_pay',
];

export type SettlementStatus =
  | 'not_paid'
  | 'paid_to_platform'
  | 'in_service'
  | 'completed_pending_settlement'
  | 'settlement_pending'
  | 'settled'
  | 'refund_pending'
  | 'refunded'
  | 'settlement_blocked';

export type PaymentChannel =
  | 'manual_qr'
  | 'wechat_pay'
  | 'alipay'
  | 'company_pay'
  | 'mixed_pay';

export type PaymentTransactionStatus =
  | 'created'
  | 'pending'
  | 'paid'
  | 'failed'
  | 'closed'
  | 'refunded';

export type MerchantSettlementStatus =
  | 'pending'
  | 'eligible'
  | 'settled'
  | 'blocked'
  | 'refunded';

export type HygieneRiskStatus = 'normal' | 'remediation' | 'suspended' | 'insufficient';

export const ALL_MEAL_TYPES: MealType[] = [
  'breakfast',
  'lunch',
  'dinner',
  'overtime',
];

/** 菜品/套餐上架与订餐展示可用餐段（不含加班餐） */
export const DISH_LISTING_MEAL_TYPES: MealType[] = [
  'breakfast',
  'lunch',
  'dinner',
];

export interface UserRow {
  id: string;
  name: string;
  nickname: string | null;
  phone: string;
  role: UserRole;
  status: string;
  company_id: string | null;
  /** 1=允许订餐 0=禁止 */
  can_order: number;
  password_hash: string | null;
  password_updated_at: string | null;
  avatar_url: string | null;
  created_at: string;
  updated_at: string;
}

export interface CompanyRow {
  id: string;
  company_name: string;
  admin_user_id: string | null;
  status: string;
  created_at: string;
  updated_at: string;
}

export type MerchantOnboardingStatus = 'pending' | 'approved' | 'rejected';

export interface SmsCodeRow {
  id: number;
  phone: string;
  code: string;
  scene: string;
  expires_at: string;
  used_at: string | null;
  ip: string | null;
  created_at: string;
}

export interface MerchantRow {
  id: string;
  user_id: string | null;
  company_id: string | null;
  name: string;
  logo_url: string | null;
  address: string | null;
  phone: string | null;
  distance_text: string | null;
  distance: number;
  rating: number;
  month_sold: number;
  hygiene_grade: string;
  hygiene_score?: number | null;
  hygiene_review_count?: number;
  hygiene_score_30d?: number | null;
  hygiene_risk_status?: string;
  is_open: number; // 0/1
  is_enabled: number; // 0/1 平台启用
  onboarding_status: MerchantOnboardingStatus;
  menu_init: number; // 0/1
  payment_qr_code_url: string | null;
  wechat_payment_qr_url: string | null;
  alipay_payment_qr_url: string | null;
  delivery_fee: number;
  contact_name: string | null;
  contact_phone: string | null;
  short_name: string | null;
  supported_meal_types_json: string | null;
  delivery_modes_json: string | null;
  delivery_scope: string | null;
  estimated_delivery_time: string | null;
  payment_method: string | null;
  payment_receiver_name: string | null;
  business_license_url: string | null;
  food_license_url: string | null;
  store_photo_url: string | null;
  reject_reason: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  remark: string | null;
  description: string | null;
  meal_opening_hours_json: string | null;
  // 企业级商家审核扩展字段（向后兼容；旧 delivery_* 字段保留不动）
  store_display_name: string | null;
  customer_service_phone: string | null;
  served_company_text: string | null;
  business_days_json: string | null;
  business_hours_start: string | null;
  business_hours_end: string | null;
  meal_order_deadlines_json: string | null;
  payment_subject_type: string | null;
  payment_subject_name: string | null;
  bank_account_name: string | null;
  bank_name: string | null;
  bank_account_number: string | null;
  business_license_subject: string | null;
  business_license_valid_until: string | null;
  unified_social_credit_code: string | null;
  food_license_number: string | null;
  food_license_valid_until: string | null;
  licensed_business_scope: string | null;
  kitchen_photo_url: string | null;
  health_certificate_url: string | null;
  // 多图 / 多选 JSON 字段（向后兼容新增）
  payment_methods_json: string | null;
  wechat_payment_qr_urls_json: string | null;
  alipay_payment_qr_urls_json: string | null;
  business_license_urls_json: string | null;
  food_license_urls_json: string | null;
  kitchen_photo_urls_json: string | null;
  health_certificate_urls_json: string | null;
  store_photo_urls_json: string | null;
  created_at: string;
  updated_at: string;
}

/** 套餐体系：菜品分类
 * - `''` 表示历史数据未分类（不影响旧 UI 与下单）
 * - `meat`/`vegetable`/`staple`/`soup`/`drink` 用于套餐选菜规则
 * - `extra` 用于"加菜"
 */
export type DishCategory =
  | ''
  | 'meat'
  | 'vegetable'
  | 'staple'
  | 'soup'
  | 'drink'
  | 'extra';

export const ALL_DISH_CATEGORIES: DishCategory[] = [
  'meat',
  'vegetable',
  'staple',
  'soup',
  'drink',
  'extra',
];

/** 套餐选择规则：每个分类需要选择的数量，0 或省略表示该分类无需选择 */
export type PackageRules = Partial<Record<Exclude<DishCategory, ''>, number>>;

export interface DishRow {
  id: string;
  merchant_id: string;
  name: string;
  image_url: string | null;
  description: string;
  price: number;
  meal_type: MealType;
  tags_json: string;
  is_available: number; // 0/1
  is_sold_out: number; // 0/1
  sort_order?: number;
  // 套餐体系扩展字段（迁移时通过 ADD COLUMN 加入，老数据可能为 null/''）
  category: DishCategory | null;
  extra_price: number;
  meal_types_json: string | null;
  created_at: string;
  updated_at: string;
}

export interface PackageRow {
  id: string;
  merchant_id: string;
  name: string;
  description: string;
  base_price: number;
  meal_types_json: string;
  rules_json: string;
  allow_extra: number; // 0/1
  extra_dish_ids_json: string;
  is_enabled: number; // 0/1
  created_at: string;
  updated_at: string;
}

export interface OrderRow {
  id: string;
  order_no: string;
  company_id: string | null;
  user_id: string | null;
  user_name: string | null;
  user_company: string | null;
  merchant_id: string;
  merchant_name: string;
  delivery_type: DeliveryType;
  address: string | null;
  phone: string | null;
  remark: string | null;
  goods_amount: number;
  delivery_fee: number;
  total_amount: number;
  status: OrderStatus;
  payment_type: PaymentType;
  payment_screenshot_url: string | null;
  reject_reason: string | null;
  is_meal_collector: number;
  collector_name: string | null;
  collector_phone: string | null;
  collector_address: string | null;
  collector_latitude: number | null;
  collector_longitude: number | null;
  collector_poi_name: string | null;
  collector_address_text: string | null;
  // 套餐订单扩展字段（仅新增）
  package_id: string | null;
  package_name: string | null;
  package_base_price: number | null;
  selected_items_json: string | null;
  extra_items_json: string | null;
  extra_amount: number | null;
  final_amount: number | null;
  package_amount: number | null;
  company_pay_amount: number | null;
  employee_pay_amount: number | null;
  settlement_status?: SettlementStatus | string | null;
  payment_channel?: PaymentChannel | string | null;
  /** manual_qr 截图支付时员工选择的扫码渠道：wechat | alipay */
  manual_pay_channel?: string | null;
  completed_at?: string | null;
  settlement_eligible_at?: string | null;
  coupon_claim_id?: string | null;
  coupon_discount_amount?: number | null;
  employee_pay_before_coupon?: number | null;
  created_at: string;
  updated_at: string;
}

export interface OrderItemRow {
  id: number;
  order_id: string;
  dish_id: string | null;
  dish_name: string;
  dish_image_url: string | null;
  dish_description: string;
  meal_type: MealType | null;
  price: number;
  quantity: number;
  subtotal: number;
}

// ===== DTO（与 Flutter 端 toJson/fromJson 字段对齐）=====

export type EmployeeProfileBindStatus =
  | 'unbound'
  | 'pending'
  | 'bound'
  | 'rejected';

export interface EmployeeProfileRow {
  id: string;
  user_id: string;
  employee_name: string;
  employee_no: string;
  phone: string;
  department_id: string | null;
  department_name: string;
  role_type: string;
  bind_status: EmployeeProfileBindStatus;
  created_at: string;
  updated_at: string;
}

export interface UserDto {
  id: string;
  name: string;
  nickname: string;
  phone: string;
  role: UserRole;
  status: string;
  companyId?: string | null;
  employeeProfileStatus?: EmployeeProfileBindStatus;
  avatarUrl?: string | null;
}

export interface CompanyDto {
  id: string;
  companyName: string;
  adminUserId: string | null;
  status: string;
  createdAt: string;
  updatedAt: string;
}

export interface MerchantOnboardingDto {
  id: string;
  merchantName: string;
  address: string;
  phone: string;
  companyId: string;
  status: MerchantOnboardingStatus;
  menuInit: boolean;
  paymentQr: string;
  userId: string | null;
  isOpen: boolean;
  isEnabled: boolean;
  createdAt: string;
  updatedAt: string;
}

export type MerchantOnboardingPhoneStatus =
  | 'none'
  | 'pending'
  | 'approved'
  | 'rejected';

export interface MerchantOnboardingStatusDto {
  status: MerchantOnboardingPhoneStatus;
  merchantId: string | null;
  rejectReason: string;
  message: string;
}

export interface MerchantOnboardingDetailDto extends MerchantOnboardingDto {
  shortName: string;
  contactName: string;
  contactPhone: string;
  supportedMealTypes: MealType[];
  deliveryModes: string[];
  /** @deprecated 入驻页不再展示，仅为兼容旧数据保留 */
  deliveryScope: string;
  /** @deprecated 入驻页不再展示，仅为兼容旧数据保留 */
  estimatedDeliveryTime: string;
  /** @deprecated 入驻页不再展示，仅为兼容旧数据保留 */
  deliveryFee: number;
  paymentMethod: string;
  paymentReceiverName: string;
  businessLicenseUrl: string;
  foodLicenseUrl: string;
  storePhotoUrl: string;
  rejectReason: string;
  reviewedBy: string | null;
  reviewedAt: string | null;
  remark: string;
  // 企业级商家审核扩展字段
  storeDisplayName: string;
  customerServicePhone: string;
  servedCompanyText: string;
  businessDays: string[];
  businessHoursStart: string;
  businessHoursEnd: string;
  mealOrderDeadlines: Partial<Record<MealType, string>>;
  paymentSubjectType: string;
  paymentSubjectName: string;
  bankAccountName: string;
  bankName: string;
  bankAccountNumber: string;
  businessLicenseSubject: string;
  businessLicenseValidUntil: string;
  unifiedSocialCreditCode: string;
  foodLicenseNumber: string;
  foodLicenseValidUntil: string;
  licensedBusinessScope: string;
  kitchenPhotoUrl: string;
  healthCertificateUrl: string;
  // 多图 / 多选返回
  paymentMethods: string[];
  wechatPaymentQrUrls: string[];
  alipayPaymentQrUrls: string[];
  businessLicenseUrls: string[];
  foodLicenseUrls: string[];
  kitchenPhotoUrls: string[];
  healthCertificateUrls: string[];
  storePhotoUrls: string[];
}

export interface AppSettingsDto {
  allowCancelOrder: boolean;
  enableReview: boolean;
  enableMerchantAutoRefresh: boolean;
  requirePaymentScreenshot: boolean;
  allowMerchantReject: boolean;
  showSoldOutDishes: boolean;
  labelPrintWidthMm: number;
  labelPrintFontSizePt: number;
  /** 企业代付适用部门名称列表（与 employee_profiles.department_name 匹配） */
  companyPayDepartments: string[];
  /** 在线支付方式开关（首期 manualQr=true，wechat/alipay=false） */
  onlinePaymentEnabled: OnlinePaymentEnabledDto;
}

export interface OnlinePaymentEnabledDto {
  wechat: boolean;
  alipay: boolean;
  manualQr: boolean;
}

export const DEFAULT_ONLINE_PAYMENT_ENABLED: OnlinePaymentEnabledDto = {
  wechat: false,
  alipay: false,
  manualQr: true,
};

export interface ReviewRow {
  id: string;
  order_id: string;
  merchant_id: string;
  user_id: string;
  rating: number;
  overall_rating?: number | null;
  taste_rating?: number | null;
  hygiene_rating?: number | null;
  service_rating?: number | null;
  delivery_rating?: number | null;
  content: string;
  images_json: string;
  is_anonymous?: number;
  created_at: string;
}

export type ReviewListFilter = 'all' | 'good' | 'medium' | 'bad' | 'with_images';

export interface ReviewDto {
  id: string;
  orderId: string;
  merchantId: string;
  userId: string;
  rating: number;
  overallRating: number;
  tasteRating: number;
  hygieneRating: number;
  serviceRating: number;
  deliveryRating: number;
  content: string;
  images: string[];
  isAnonymous: boolean;
  displayUserName: string;
  departmentName?: string;
  orderNo?: string;
  createdAt: string;
}

export interface MerchantReviewsListDto {
  stats: MerchantHygieneStatsDto;
  reviews: ReviewDto[];
}

export interface PaymentTransactionRow {
  id: string;
  order_id: string;
  payment_no: string;
  channel: string;
  amount: number;
  status: PaymentTransactionStatus | string;
  provider_trade_no: string | null;
  request_payload_json: string | null;
  notify_payload_json: string | null;
  paid_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface MerchantSettlementRow {
  id: string;
  merchant_id: string;
  order_id: string;
  settlement_no: string;
  order_amount: number;
  company_pay_amount: number;
  employee_pay_amount: number;
  platform_service_fee: number;
  merchant_receivable_amount: number;
  status: MerchantSettlementStatus | string;
  completed_at: string | null;
  settlement_eligible_at: string | null;
  settled_at: string | null;
  block_reason: string | null;
  created_at: string;
  updated_at: string;
}

export type MerchantWithdrawalStatus =
  | 'pending'
  | 'approved'
  | 'rejected'
  | 'paid';

export interface MerchantWithdrawalRow {
  id: string;
  merchant_id: string;
  amount: number;
  status: MerchantWithdrawalStatus | string;
  account_name: string;
  account_type: string;
  account_no: string;
  remark: string | null;
  created_at: string;
  updated_at: string;
  reviewed_at: string | null;
}

export interface MerchantRemediationNoticeRow {
  id: string;
  merchant_id: string;
  reason: string;
  hygiene_avg: number | null;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface MerchantHygieneStatsDto {
  hygieneGrade: string;
  hygieneScore: number | null;
  hygieneScore30d: number | null;
  reviewCount: number;
  overallRating: number | null;
  riskStatus: HygieneRiskStatus | string;
  needsRemediation: boolean;
  gradeLabel: string;
}

export interface SystemConfigDto {
  mealDeadlines: Record<MealType, string>;
  appSettings: AppSettingsDto;
  updatedAt: string;
}

export type AdminMerchantDto = MerchantOnboardingDetailDto;

export interface AdminUserDto {
  id: string;
  name: string;
  phone: string;
  role: UserRole;
  companyId: string | null;
  status: string;
  createdAt: string;
}

export interface EmployeeProfileDto {
  id: string;
  userId: string;
  employeeName: string;
  employeeNo: string;
  phone: string;
  departmentId: string;
  departmentName: string;
  roleType: string;
  bindStatus: EmployeeProfileBindStatus;
  createdAt: string;
  updatedAt: string;
}

export interface AuthMeDto {
  user: UserDto;
  employeeProfile: EmployeeProfileDto | null;
  employeeProfileStatus: EmployeeProfileBindStatus;
}

export interface MerchantDto {
  id: string;
  name: string;
  logo: string;
  coverImage: string;
  distance: number;
  rating: number;
  monthSold: number;
  hygieneGrade: string;
  hygieneScore?: number | null;
  hygieneScore30d?: number | null;
  hygieneReviewCount?: number;
  hygieneRiskStatus?: string;
  isOpen: boolean;
  address: string;
  paymentQrCode: string;
  wechatPaymentQrUrl: string;
  alipayPaymentQrUrl: string;
  deliveryFee: number;
  contactName?: string;
  contactPhone?: string;
  description?: string;
  deliveryModes?: string[];
  deliveryScope?: string;
  estimatedDeliveryTime?: string;
  supportedMealTypes?: MealType[];
  mealOpeningHours?: Record<
    string,
    { enabled?: boolean; hours?: string }
  >;
  /**
   * 商家自定义的"各餐段订餐截止时间"，格式 `HH:mm`。
   *
   * - 空对象或缺省键：员工端 / 后端都会回退到 `systemConfig.mealDeadlines` 的全局默认值；
   * - 仅新增字段，不删除旧字段，旧客户端忽略即可。
   */
  mealOrderDeadlines?: Partial<Record<MealType, string>>;
}

export interface DishDto {
  id: string;
  merchantId: string;
  name: string;
  image: string;
  description: string;
  price: number;
  mealType: MealType;
  tags: string[];
  isAvailable: boolean;
  isSoldOut: boolean;
  sortOrder: number;
  // 套餐体系扩展字段（可空兼容历史）
  category: DishCategory;
  extraPrice: number;
  mealTypes: MealType[];
}

export interface PackageDto {
  id: string;
  merchantId: string;
  name: string;
  description: string;
  basePrice: number;
  mealTypes: MealType[];
  rules: PackageRules;
  allowExtra: boolean;
  extraDishIds: string[];
  isEnabled: boolean;
  createdAt: string;
  updatedAt: string;
}

/** 套餐订单中"按规则选择的菜品"明细 */
export interface OrderSelectedItemDto {
  dishId: string;
  name: string;
  category: DishCategory;
  mealType: MealType | null;
}

/** 套餐订单中"加菜"明细 */
export interface OrderExtraItemDto {
  dishId: string;
  name: string;
  unitPrice: number;
  quantity: number;
  subtotal: number;
}

export interface CartItemDto {
  dish: DishDto;
  quantity: number;
}

export interface OrderDto {
  id: string;
  orderNo: string;
  merchantId: string;
  merchantName: string;
  /** 展示用商家名（已兜底，不含 ????） */
  displayMerchantName: string;
  /** 展示用套餐名（非套餐订单为 null） */
  displayPackageName: string | null;
  /** 展示用菜品摘要 */
  itemsSummary: string;
  customerName: string;
  customerCompany: string;
  items: CartItemDto[];
  deliveryType: DeliveryType;
  address: string;
  phone: string;
  remark: string;
  goodsAmount: number;
  deliveryFee: number;
  totalAmount: number;
  status: OrderStatus;
  paymentType: PaymentType;
  paymentScreenshot: string | null;
  manualPayChannel: string | null;
  rejectReason: string | null;
  isMealCollector: boolean;
  collectorName: string;
  collectorPhone: string;
  collectorAddress: string;
  collectorLatitude?: number | null;
  collectorLongitude?: number | null;
  collectorPoiName?: string;
  collectorAddressText?: string;
  // 套餐订单扩展字段（普通菜品订单为 null / 空数组 / 0）
  packageId: string | null;
  packageName: string | null;
  packageBasePrice: number;
  selectedItems: OrderSelectedItemDto[];
  extraItems: OrderExtraItemDto[];
  extraAmount: number;
  finalAmount: number;
  packageAmount: number;
  companyPayAmount: number;
  employeePayAmount: number;
  couponClaimId?: string | null;
  couponDiscountAmount?: number;
  employeePayBeforeCoupon?: number;
  settlementStatus: SettlementStatus | string;
  paymentChannel: PaymentChannel | string;
  completedAt: string | null;
  settlementEligibleAt: string | null;
  createdAt: string;
}

export type DeliveryLocationStatus = 'delivering' | 'stopped';

export interface DeliveryLocationRow {
  id: string;
  company_id: string | null;
  merchant_id: string;
  order_batch_key: string;
  date: string;
  meal_type: MealType;
  latitude: number | null;
  longitude: number | null;
  address_text: string | null;
  status: DeliveryLocationStatus;
  updated_at: string;
  created_at: string;
}

export interface DeliveryLocationDto {
  latitude: number | null;
  longitude: number | null;
  addressText: string;
  status: DeliveryLocationStatus;
  updatedAt: string;
  orderBatchKey: string;
  date: string;
  mealType: MealType;
  merchantId: string;
}

// =============================================================
// 订单沟通：会话 & 消息
// =============================================================

export type ConversationType = 'order';
export type ConversationStatus = 'open' | 'closed';

export type ConversationSenderType =
  | 'employee'
  | 'merchant'
  | 'system'
  | 'admin';

export type ConversationMessageType = 'text' | 'image' | 'emoji' | 'system';

export const ALL_CONVERSATION_MESSAGE_TYPES: ConversationMessageType[] = [
  'text',
  'image',
  'emoji',
  'system',
];

export interface ConversationRow {
  id: string;
  type: ConversationType;
  order_id: string;
  merchant_id: string;
  employee_id: string | null;
  last_message_text: string | null;
  last_message_at: string | null;
  employee_unread_count: number;
  merchant_unread_count: number;
  status: ConversationStatus;
  created_at: string;
  updated_at: string;
}

export interface ConversationMessageRow {
  id: string;
  conversation_id: string;
  sender_type: ConversationSenderType;
  sender_id: string | null;
  message_type: ConversationMessageType;
  content: string | null;
  image_url: string | null;
  metadata_json: string | null;
  created_at: string;
  read_at: string | null;
}

export interface ConversationDto {
  id: string;
  type: ConversationType;
  orderId: string;
  merchantId: string;
  employeeId: string | null;
  lastMessageText: string | null;
  lastMessageAt: string | null;
  employeeUnreadCount: number;
  merchantUnreadCount: number;
  status: ConversationStatus;
  createdAt: string;
  updatedAt: string;
  // 给商家会话列表用，便于一眼定位订单
  orderNo?: string | null;
  orderStatus?: OrderStatus | null;
  employeeName?: string | null;
  merchantName?: string | null;
}

export interface ConversationMessageDto {
  id: string;
  conversationId: string;
  senderType: ConversationSenderType;
  senderId: string | null;
  messageType: ConversationMessageType;
  content: string | null;
  imageUrl: string | null;
  createdAt: string;
  readAt: string | null;
}

// ---------- 平台客服 ----------

export type SupportUserRole = 'employee' | 'merchant';
export type SupportConversationStatus =
  | 'open'
  | 'pending'
  | 'resolved'
  | 'closed';
export type SupportSenderType = 'user' | 'admin' | 'system';
export type SupportMessageType = 'text' | 'image' | 'emoji' | 'system';

export const ALL_SUPPORT_MESSAGE_TYPES: SupportMessageType[] = [
  'text',
  'image',
  'emoji',
  'system',
];

export interface SupportConversationRow {
  id: string;
  user_id: string;
  user_role: SupportUserRole;
  merchant_id: string | null;
  title: string;
  status: SupportConversationStatus;
  last_message_text: string | null;
  last_message_at: string | null;
  user_unread_count: number;
  admin_unread_count: number;
  created_at: string;
  updated_at: string;
}

export interface SupportMessageRow {
  id: string;
  conversation_id: string;
  sender_type: SupportSenderType;
  sender_id: string | null;
  message_type: SupportMessageType;
  content: string | null;
  image_url: string | null;
  created_at: string;
  read_at: string | null;
}

export interface SupportConversationDto {
  id: string;
  userId: string;
  userRole: SupportUserRole;
  merchantId: string | null;
  title: string;
  status: SupportConversationStatus;
  lastMessageText: string | null;
  lastMessageAt: string | null;
  userUnreadCount: number;
  adminUnreadCount: number;
  createdAt: string;
  updatedAt: string;
  userName?: string | null;
  userPhone?: string | null;
  merchantName?: string | null;
}

export interface SupportMessageDto {
  id: string;
  conversationId: string;
  senderType: SupportSenderType;
  senderId: string | null;
  messageType: SupportMessageType;
  content: string | null;
  imageUrl: string | null;
  createdAt: string;
  readAt: string | null;
}
