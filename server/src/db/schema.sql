-- 非攻云餐数据库结构
-- SQLite

CREATE TABLE IF NOT EXISTS companies (
  id              TEXT PRIMARY KEY,
  company_name    TEXT NOT NULL,
  admin_user_id   TEXT,
  status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'disabled')),
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS system_config (
  key         TEXT PRIMARY KEY,
  value_json  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  nickname    TEXT,
  phone       TEXT NOT NULL UNIQUE,
  role        TEXT NOT NULL DEFAULT 'employee',
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  company_id  TEXT,
  can_order   INTEGER NOT NULL DEFAULT 1,
  password_hash TEXT,
  password_updated_at TEXT,
  avatar_url  TEXT,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sms_codes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  phone       TEXT NOT NULL,
  code        TEXT NOT NULL,
  scene       TEXT NOT NULL DEFAULT 'login',
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  ip          TEXT,
  created_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sms_codes_phone_created
  ON sms_codes(phone, created_at DESC);

CREATE TABLE IF NOT EXISTS employee_profiles (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL UNIQUE,
  employee_name     TEXT NOT NULL,
  employee_no       TEXT NOT NULL,
  phone             TEXT NOT NULL,
  department_id     TEXT,
  department_name   TEXT NOT NULL,
  role_type         TEXT NOT NULL DEFAULT 'employee'
                      CHECK (role_type IN ('employee')),
  bind_status       TEXT NOT NULL DEFAULT 'unbound'
                      CHECK (bind_status IN ('unbound', 'pending', 'bound', 'rejected')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_employee_profiles_user
  ON employee_profiles(user_id);

CREATE TABLE IF NOT EXISTS merchants (
  id                    TEXT PRIMARY KEY,
  user_id               TEXT,
  company_id            TEXT,
  name                  TEXT NOT NULL,
  logo_url              TEXT,
  address               TEXT,
  phone                 TEXT,
  distance_text         TEXT,
  distance              INTEGER DEFAULT 0,
  rating                REAL DEFAULT 0,
  month_sold            INTEGER DEFAULT 0,
  hygiene_grade         TEXT DEFAULT 'A',
  is_open               INTEGER DEFAULT 1,
  is_enabled            INTEGER DEFAULT 1,
  onboarding_status     TEXT NOT NULL DEFAULT 'approved',
  menu_init             INTEGER DEFAULT 0,
  payment_qr_code_url   TEXT,
  delivery_fee          REAL DEFAULT 0,
  contact_name          TEXT,
  contact_phone         TEXT,
  short_name            TEXT,
  supported_meal_types_json TEXT DEFAULT '[]',
  delivery_modes_json   TEXT DEFAULT '[]',
  delivery_scope        TEXT,
  estimated_delivery_time TEXT,
  payment_method        TEXT,
  payment_receiver_name TEXT,
  business_license_url  TEXT,
  food_license_url      TEXT,
  store_photo_url       TEXT,
  reject_reason         TEXT,
  reviewed_by           TEXT,
  reviewed_at           TEXT,
  remark                TEXT,
  -- 企业级商家审核扩展字段（向后兼容新增，旧的 delivery_scope/estimated_delivery_time/delivery_fee 保留不动）
  store_display_name        TEXT,
  customer_service_phone    TEXT,
  served_company_text       TEXT,
  business_days_json        TEXT DEFAULT '[]',
  business_hours_start      TEXT,
  business_hours_end        TEXT,
  meal_order_deadlines_json TEXT DEFAULT '{}',
  payment_subject_type      TEXT,
  payment_subject_name      TEXT,
  bank_account_name         TEXT,
  bank_name                 TEXT,
  bank_account_number       TEXT,
  business_license_subject  TEXT,
  business_license_valid_until TEXT,
  unified_social_credit_code   TEXT,
  food_license_number          TEXT,
  food_license_valid_until     TEXT,
  licensed_business_scope      TEXT,
  kitchen_photo_url         TEXT,
  health_certificate_url    TEXT,
  -- 多图 / 多选向后兼容字段（旧 *_url 单图字段保留不删，新提交时取第一张写回旧字段）
  payment_methods_json              TEXT DEFAULT '[]',
  wechat_payment_qr_urls_json       TEXT DEFAULT '[]',
  alipay_payment_qr_urls_json       TEXT DEFAULT '[]',
  business_license_urls_json        TEXT DEFAULT '[]',
  food_license_urls_json            TEXT DEFAULT '[]',
  kitchen_photo_urls_json           TEXT DEFAULT '[]',
  health_certificate_urls_json      TEXT DEFAULT '[]',
  store_photo_urls_json             TEXT DEFAULT '[]',
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS dishes (
  id            TEXT PRIMARY KEY,
  merchant_id   TEXT NOT NULL,
  name          TEXT NOT NULL,
  image_url     TEXT,
  description   TEXT DEFAULT '',
  price         REAL NOT NULL,
  meal_type     TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'overtime')),
  tags_json     TEXT DEFAULT '[]',
  is_available  INTEGER DEFAULT 1,  -- 1/0
  is_sold_out   INTEGER DEFAULT 0,  -- 1/0
  -- 套餐体系扩展字段（仅新增，旧 meal_type / price / tags_json 保留）
  -- category: meat 荤 / vegetable 素 / staple 主食 / soup 汤品 / drink 饮品 / extra 加菜
  category      TEXT DEFAULT '' ,
  extra_price   REAL NOT NULL DEFAULT 0,
  -- 适用餐段多选：JSON 数组，旧 meal_type 仍存单值，回退时兜底
  meal_types_json TEXT DEFAULT '[]',
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE
);

-- 套餐表（一荤一素、一荤两素、两荤两素…）
CREATE TABLE IF NOT EXISTS packages (
  id                  TEXT PRIMARY KEY,
  merchant_id         TEXT NOT NULL,
  name                TEXT NOT NULL,
  description         TEXT DEFAULT '',
  base_price          REAL NOT NULL DEFAULT 0,
  -- 适用餐段，JSON 数组
  meal_types_json     TEXT NOT NULL DEFAULT '[]',
  -- 套餐选择规则，JSON：{"meat":1,"vegetable":2,"staple":1,"soup":1,"drink":0}
  rules_json          TEXT NOT NULL DEFAULT '{}',
  -- 是否允许加菜
  allow_extra         INTEGER NOT NULL DEFAULT 1,
  -- 可选加菜白名单 dishId 数组；为空数组代表"全部 category=extra"
  extra_dish_ids_json TEXT NOT NULL DEFAULT '[]',
  is_enabled          INTEGER NOT NULL DEFAULT 1,
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_packages_merchant ON packages(merchant_id);

CREATE TABLE IF NOT EXISTS coupon_templates (
  id                TEXT PRIMARY KEY,
  merchant_id       TEXT NOT NULL,
  name              TEXT NOT NULL,
  coupon_type       TEXT NOT NULL CHECK (coupon_type IN ('fixed', 'threshold', 'newcomer')),
  discount_amount   REAL NOT NULL,
  min_order_amount  REAL NOT NULL DEFAULT 0,
  meal_types_json   TEXT NOT NULL DEFAULT '["breakfast","lunch","dinner"]',
  total_quantity    INTEGER NOT NULL,
  per_user_limit    INTEGER NOT NULL DEFAULT 1,
  claimed_count     INTEGER NOT NULL DEFAULT 0,
  used_count        INTEGER NOT NULL DEFAULT 0,
  start_at          TEXT NOT NULL,
  end_at            TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'enabled' CHECK (status IN ('enabled', 'disabled')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_coupon_templates_merchant
  ON coupon_templates(merchant_id, status);

CREATE TABLE IF NOT EXISTS coupon_claims (
  id          TEXT PRIMARY KEY,
  template_id TEXT NOT NULL,
  merchant_id TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'claimed' CHECK (status IN ('claimed', 'used', 'expired')),
  claimed_at  TEXT NOT NULL,
  used_at     TEXT,
  order_id    TEXT,
  FOREIGN KEY (template_id) REFERENCES coupon_templates(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_coupon_claims_user
  ON coupon_claims(user_id, merchant_id, status);

CREATE TABLE IF NOT EXISTS coupon_usages (
  id              TEXT PRIMARY KEY,
  claim_id        TEXT NOT NULL,
  template_id     TEXT NOT NULL,
  merchant_id     TEXT NOT NULL,
  user_id         TEXT NOT NULL,
  order_id        TEXT NOT NULL,
  discount_amount REAL NOT NULL,
  created_at      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_coupon_usages_order ON coupon_usages(order_id);

CREATE TABLE IF NOT EXISTS orders (
  id                      TEXT PRIMARY KEY,
  order_no                TEXT NOT NULL UNIQUE,
  company_id              TEXT,
  user_id                 TEXT,
  user_name               TEXT,
  user_company            TEXT,
  merchant_id             TEXT NOT NULL,
  merchant_name           TEXT NOT NULL,
  delivery_type           TEXT NOT NULL CHECK (delivery_type IN ('delivery', 'selfPickup')),
  address                 TEXT,
  phone                   TEXT,
  remark                  TEXT,
  goods_amount            REAL NOT NULL,
  delivery_fee            REAL NOT NULL DEFAULT 0,
  total_amount            REAL NOT NULL,
  status                  TEXT NOT NULL CHECK (status IN (
                            'pendingPayment',
                            'paymentSubmitted',
                            'pendingMerchantConfirm',
                            'accepted',
                            'delivering',
                            'completed',
                            'cancelled')),
  payment_type            TEXT NOT NULL DEFAULT 'self_pay'
                            CHECK (payment_type IN ('self_pay', 'company_pay')),
  payment_screenshot_url  TEXT,
  reject_reason           TEXT,
  is_meal_collector       INTEGER DEFAULT 0,
  collector_name          TEXT,
  collector_phone         TEXT,
  collector_address       TEXT,
  -- 套餐订单扩展字段（仅新增，旧 goods_amount / total_amount 保留）
  package_id              TEXT,
  package_name            TEXT,
  package_base_price      REAL DEFAULT 0,
  -- 所选普通菜（按分类聚合）：JSON 数组
  -- [{ dishId, name, category, mealType, quantity:1 }]
  selected_items_json     TEXT DEFAULT '[]',
  -- 所选加菜：JSON 数组
  -- [{ dishId, name, unitPrice, quantity, subtotal }]
  extra_items_json        TEXT DEFAULT '[]',
  extra_amount            REAL DEFAULT 0,
  final_amount            REAL DEFAULT 0,
  coupon_claim_id         TEXT,
  coupon_discount_amount  REAL DEFAULT 0,
  employee_pay_before_coupon REAL DEFAULT 0,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS order_items (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id          TEXT NOT NULL,
  dish_id           TEXT,
  dish_name         TEXT NOT NULL,
  dish_image_url    TEXT,
  dish_description  TEXT DEFAULT '',
  meal_type         TEXT,
  price             REAL NOT NULL,
  quantity          INTEGER NOT NULL,
  subtotal          REAL NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_dishes_merchant     ON dishes(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_user         ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_merchant     ON orders(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_status       ON orders(status);
CREATE INDEX IF NOT EXISTS idx_order_items_order   ON order_items(order_id);

-- =============================================================
-- 商家评价（订单完成后，一单一评）
-- =============================================================
CREATE TABLE IF NOT EXISTS reviews (
  id            TEXT PRIMARY KEY,
  order_id      TEXT NOT NULL UNIQUE,
  merchant_id   TEXT NOT NULL,
  user_id       TEXT NOT NULL,
  rating        INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  content       TEXT NOT NULL DEFAULT '',
  images_json   TEXT NOT NULL DEFAULT '[]',
  created_at    TEXT NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_reviews_merchant ON reviews(merchant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user     ON reviews(user_id);

-- =============================================================
-- 订单沟通：会话 + 消息（HTTP + 轮询，未引入 WebSocket）
-- 仅新增，不删除旧表/字段，便于向后兼容。
-- =============================================================
CREATE TABLE IF NOT EXISTS conversations (
  id                      TEXT PRIMARY KEY,
  -- 目前只有 order 类型，预留扩展
  type                    TEXT NOT NULL DEFAULT 'order'
                            CHECK (type IN ('order')),
  order_id                TEXT NOT NULL,
  merchant_id             TEXT NOT NULL,
  employee_id             TEXT,
  last_message_text       TEXT,
  last_message_at         TEXT,
  employee_unread_count   INTEGER NOT NULL DEFAULT 0,
  merchant_unread_count   INTEGER NOT NULL DEFAULT 0,
  status                  TEXT NOT NULL DEFAULT 'open'
                            CHECK (status IN ('open', 'closed')),
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL,
  UNIQUE(order_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_merchant
  ON conversations(merchant_id, status);
CREATE INDEX IF NOT EXISTS idx_conversations_employee
  ON conversations(employee_id, status);

CREATE TABLE IF NOT EXISTS conversation_messages (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  sender_type     TEXT NOT NULL
                    CHECK (sender_type IN ('employee', 'merchant', 'system', 'admin')),
  sender_id       TEXT,
  message_type    TEXT NOT NULL
                    CHECK (message_type IN ('text', 'image', 'emoji', 'system')),
  content         TEXT,
  image_url       TEXT,
  metadata_json   TEXT DEFAULT '{}',
  created_at      TEXT NOT NULL,
  read_at         TEXT,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_conversation_messages_conv
  ON conversation_messages(conversation_id, created_at ASC);

CREATE TABLE IF NOT EXISTS support_conversations (
  id                  TEXT PRIMARY KEY,
  user_id             TEXT NOT NULL,
  user_role           TEXT NOT NULL
                        CHECK (user_role IN ('employee', 'merchant')),
  merchant_id         TEXT,
  title               TEXT NOT NULL DEFAULT '平台客服',
  status              TEXT NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open', 'pending', 'resolved', 'closed')),
  last_message_text   TEXT,
  last_message_at     TEXT,
  user_unread_count   INTEGER NOT NULL DEFAULT 0,
  admin_unread_count  INTEGER NOT NULL DEFAULT 0,
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  UNIQUE(user_id, user_role)
);

CREATE INDEX IF NOT EXISTS idx_support_conversations_status
  ON support_conversations(status, last_message_at DESC);

CREATE TABLE IF NOT EXISTS support_messages (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  sender_type     TEXT NOT NULL
                    CHECK (sender_type IN ('user', 'admin', 'system')),
  sender_id       TEXT,
  message_type    TEXT NOT NULL
                    CHECK (message_type IN ('text', 'image', 'emoji', 'system')),
  content         TEXT,
  image_url       TEXT,
  created_at      TEXT NOT NULL,
  read_at         TEXT,
  FOREIGN KEY (conversation_id) REFERENCES support_conversations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_support_messages_conv
  ON support_messages(conversation_id, created_at ASC);

CREATE TABLE IF NOT EXISTS merchant_agreements (
  id                          TEXT PRIMARY KEY,
  merchant_id                 TEXT NOT NULL,
  agreement_version           TEXT NOT NULL,
  agreement_content_snapshot  TEXT NOT NULL,
  ip_address                  TEXT,
  user_agent                  TEXT,
  signed_at                   TEXT NOT NULL,
  signature_hash              TEXT NOT NULL,
  FOREIGN KEY (merchant_id) REFERENCES merchants(id)
);

CREATE INDEX IF NOT EXISTS idx_merchant_agreements_merchant
  ON merchant_agreements(merchant_id, signed_at DESC);
