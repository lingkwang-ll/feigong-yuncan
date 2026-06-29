import Database from 'better-sqlite3';
import { nanoid } from 'nanoid';
import { nowIso } from '../models/mappers';
import { defaultPasswordHash } from '../utils/password.util';

const MIGRATION_TEMP_TABLES = [
  'users_new',
  'merchants_new',
  'orders_new',
  'dishes_new',
  'companies_new',
  'reviews_new',
  'addresses_new',
] as const;

/** 为已有数据库补列 / 补表（CREATE TABLE IF NOT EXISTS 不会追加新列） */
export function runMigrations(db: Database.Database): void {
  cleanupMigrationTempTables(db);
  migrateCompanies(db);
  migrateUsers(db);
  migrateUsersRoleAndCompany(db);
  migrateSmsCodes(db);
  migrateEmployeeProfiles(db);
  migrateMerchantsCommercial(db);
  migrateMerchantsOnboarding(db);
  migrateMerchantsProfile(db);
  migrateMerchantsEnterpriseFields(db);
  migrateOrders(db);
  migrateOrdersPackageFields(db);
  migrateOrdersPaymentFlow(db);
  migrateOrdersPaymentSplit(db);
  migrateOvertimeRosters(db);
  migrateMealLabelPrints(db);
  migrateOvertimeMealUsages(db);
  migrateReviewsTable(db);
  migrateSystemConfig(db);
  migrateDishSortOrder(db);
  migrateDishCategory(db);
  migratePackagesTable(db);
  migrateMealBatchConfirmations(db);
  migrateDeliveryLocations(db);
  migrateAdminOperationLogs(db);
  migrateUsersCanOrder(db);
  migrateUsersPassword(db);
  migrateUsersAvatarUrl(db);
  migrateConversations(db);
  seedDefaultCompany(db);
  migrateReviewsDimensions(db);
  migrateReviewAnonymous(db);
  migrateOvertimeRosterMealType(db);
  migrateOvertimeMealUsageAmounts(db);
  migrateMerchantHygieneMeta(db);
  migrateOrdersSettlement(db);
  migratePaymentAndSettlementTables(db);
  migrateMerchantWithdrawals(db);
  migrateUxPrelaunchFields(db);
  migrateSupportChat(db);
  migrateCoupons(db);
  migrateMerchantAgreements(db);
}

function migrateMerchantAgreements(db: Database.Database): void {
  db.exec(`
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
  `);
}

/** 上线前体验：分渠道收款码、截图支付渠道记录 */
function migrateUxPrelaunchFields(db: Database.Database): void {
  if (tableExists(db, 'merchants')) {
    addColumnIfMissing(
      db,
      'merchants',
      'wechat_payment_qr_url',
      'ALTER TABLE merchants ADD COLUMN wechat_payment_qr_url TEXT',
    );
    addColumnIfMissing(
      db,
      'merchants',
      'alipay_payment_qr_url',
      'ALTER TABLE merchants ADD COLUMN alipay_payment_qr_url TEXT',
    );
  }
  if (tableExists(db, 'orders')) {
    addColumnIfMissing(
      db,
      'orders',
      'manual_pay_channel',
      'ALTER TABLE orders ADD COLUMN manual_pay_channel TEXT',
    );
  }
}

/** 平台客服会话与消息（独立于订单沟通） */
function migrateSupportChat(db: Database.Database): void {
  db.exec(`
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
  `);
}

function migrateCoupons(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS coupon_templates (
      id                TEXT PRIMARY KEY,
      merchant_id       TEXT NOT NULL,
      name              TEXT NOT NULL,
      coupon_type       TEXT NOT NULL
                          CHECK (coupon_type IN ('fixed', 'threshold', 'newcomer')),
      discount_amount   REAL NOT NULL,
      min_order_amount  REAL NOT NULL DEFAULT 0,
      meal_types_json   TEXT NOT NULL DEFAULT '[]',
      total_quantity    INTEGER NOT NULL,
      per_user_limit    INTEGER NOT NULL DEFAULT 1,
      claimed_count     INTEGER NOT NULL DEFAULT 0,
      used_count        INTEGER NOT NULL DEFAULT 0,
      start_at          TEXT NOT NULL,
      end_at            TEXT NOT NULL,
      status            TEXT NOT NULL DEFAULT 'enabled'
                          CHECK (status IN ('enabled', 'disabled')),
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_coupon_templates_merchant
      ON coupon_templates(merchant_id, status);
    CREATE TABLE IF NOT EXISTS coupon_claims (
      id           TEXT PRIMARY KEY,
      template_id  TEXT NOT NULL,
      merchant_id  TEXT NOT NULL,
      user_id      TEXT NOT NULL,
      status       TEXT NOT NULL DEFAULT 'claimed'
                     CHECK (status IN ('claimed', 'used', 'expired')),
      claimed_at   TEXT NOT NULL,
      used_at      TEXT,
      order_id     TEXT,
      FOREIGN KEY (template_id) REFERENCES coupon_templates(id)
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
    CREATE INDEX IF NOT EXISTS idx_coupon_usages_order
      ON coupon_usages(order_id);
  `);
  if (tableExists(db, 'orders')) {
    addColumnIfMissing(
      db,
      'orders',
      'coupon_claim_id',
      'ALTER TABLE orders ADD COLUMN coupon_claim_id TEXT',
    );
    addColumnIfMissing(
      db,
      'orders',
      'coupon_discount_amount',
      'ALTER TABLE orders ADD COLUMN coupon_discount_amount REAL DEFAULT 0',
    );
    addColumnIfMissing(
      db,
      'orders',
      'employee_pay_before_coupon',
      'ALTER TABLE orders ADD COLUMN employee_pay_before_coupon REAL DEFAULT 0',
    );
  }
}

function tableExists(db: Database.Database, name: string): boolean {
  const row = db
    .prepare<[string], { name: string }>(
      `SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?`,
    )
    .get(name);
  return !!row;
}

function getColumnNames(db: Database.Database, table: string): Set<string> {
  const columns = db
    .prepare(`PRAGMA table_info(${table})`)
    .all() as { name: string }[];
  return new Set(columns.map((c) => c.name));
}

/**
 * 清理迁移残留的 *_new 临时表。
 * users_new 特殊处理：若 users 已丢失而 users_new 仍在，则恢复为 users。
 */
function cleanupMigrationTempTables(db: Database.Database): void {
  const usersExists = tableExists(db, 'users');
  const usersNewExists = tableExists(db, 'users_new');

  if (!usersExists && usersNewExists) {
    db.exec(`ALTER TABLE users_new RENAME TO users`);
  } else if (usersNewExists) {
    db.exec(`DROP TABLE IF EXISTS users_new`);
  }

  for (const name of MIGRATION_TEMP_TABLES) {
    if (name === 'users_new') continue;
    db.exec(`DROP TABLE IF EXISTS ${name}`);
  }
}

function addColumn(db: Database.Database, sql: string): void {
  try {
    db.exec(sql);
  } catch {
    // 列已存在时忽略
  }
}

function addColumnIfMissing(
  db: Database.Database,
  table: string,
  column: string,
  sql: string,
): void {
  if (!tableExists(db, table)) return;
  const names = getColumnNames(db, table);
  if (!names.has(column)) {
    addColumn(db, sql);
  }
}

function migrateCompanies(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS companies (
      id              TEXT PRIMARY KEY,
      company_name    TEXT NOT NULL,
      admin_user_id   TEXT,
      status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'disabled')),
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_companies_admin ON companies(admin_user_id);
  `);
}

function migrateMealBatchConfirmations(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS meal_batch_confirmations (
      id            TEXT PRIMARY KEY,
      batch_date    TEXT NOT NULL,
      meal_type     TEXT NOT NULL,
      merchant_id   TEXT NOT NULL,
      status        TEXT NOT NULL DEFAULT 'confirmed',
      confirmed_by  TEXT,
      confirmed_at  TEXT NOT NULL,
      UNIQUE(batch_date, meal_type, merchant_id)
    );
  `);
}

function migrateDishSortOrder(db: Database.Database): void {
  addColumnIfMissing(
    db,
    'dishes',
    'sort_order',
    'ALTER TABLE dishes ADD COLUMN sort_order INTEGER DEFAULT 0',
  );
}

/**
 * 套餐体系：菜品扩展字段（仅新增，旧 price / meal_type / tags_json 保留）
 * - category: meat 荤 / vegetable 素 / staple 主食 / soup 汤品 / drink 饮品 / extra 加菜
 * - extra_price: 加菜单价（category=extra 时使用）
 * - meal_types_json: 适用餐段多选，旧 meal_type 单值仍保留作为兜底
 */
function migrateDishCategory(db: Database.Database): void {
  if (!tableExists(db, 'dishes')) return;
  addColumnIfMissing(
    db,
    'dishes',
    'category',
    "ALTER TABLE dishes ADD COLUMN category TEXT DEFAULT ''",
  );
  addColumnIfMissing(
    db,
    'dishes',
    'extra_price',
    'ALTER TABLE dishes ADD COLUMN extra_price REAL NOT NULL DEFAULT 0',
  );
  addColumnIfMissing(
    db,
    'dishes',
    'meal_types_json',
    "ALTER TABLE dishes ADD COLUMN meal_types_json TEXT DEFAULT '[]'",
  );
}

/** 套餐表：商家维护"几荤几素 + 基础价 + 是否允许加菜" */
function migratePackagesTable(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS packages (
      id                  TEXT PRIMARY KEY,
      merchant_id         TEXT NOT NULL,
      name                TEXT NOT NULL,
      description         TEXT DEFAULT '',
      base_price          REAL NOT NULL DEFAULT 0,
      meal_types_json     TEXT NOT NULL DEFAULT '[]',
      rules_json          TEXT NOT NULL DEFAULT '{}',
      allow_extra         INTEGER NOT NULL DEFAULT 1,
      extra_dish_ids_json TEXT NOT NULL DEFAULT '[]',
      is_enabled          INTEGER NOT NULL DEFAULT 1,
      created_at          TEXT NOT NULL,
      updated_at          TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_packages_merchant ON packages(merchant_id);
  `);
}

/**
 * 订单扩展字段：保留旧 goods_amount / total_amount / order_items 不动，
 * 仅新增 7 个套餐 / 加菜相关字段。
 */
function migrateOrdersPackageFields(db: Database.Database): void {
  if (!tableExists(db, 'orders')) return;
  const adds: [string, string][] = [
    ['package_id', 'ALTER TABLE orders ADD COLUMN package_id TEXT'],
    ['package_name', 'ALTER TABLE orders ADD COLUMN package_name TEXT'],
    [
      'package_base_price',
      'ALTER TABLE orders ADD COLUMN package_base_price REAL DEFAULT 0',
    ],
    [
      'selected_items_json',
      "ALTER TABLE orders ADD COLUMN selected_items_json TEXT DEFAULT '[]'",
    ],
    [
      'extra_items_json',
      "ALTER TABLE orders ADD COLUMN extra_items_json TEXT DEFAULT '[]'",
    ],
    ['extra_amount', 'ALTER TABLE orders ADD COLUMN extra_amount REAL DEFAULT 0'],
    ['final_amount', 'ALTER TABLE orders ADD COLUMN final_amount REAL DEFAULT 0'],
  ];
  const names = getColumnNames(db, 'orders');
  for (const [col, sql] of adds) {
    if (!names.has(col)) addColumn(db, sql);
  }
}

/**
 * 支付流程升级：paymentSubmitted 状态 + payment_type 字段。
 * SQLite 无法 ALTER CHECK，若旧表约束不含新状态则重建 orders 表（保留全部数据）。
 */
function migrateOrdersPaymentFlow(db: Database.Database): void {
  if (!tableExists(db, 'orders')) return;

  const names = getColumnNames(db, 'orders');
  if (!names.has('payment_type')) {
    addColumn(
      db,
      "ALTER TABLE orders ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'self_pay'",
    );
  }

  const ddlRow = db
    .prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'orders'`)
    .get() as { sql: string } | undefined;
  const ddl = ddlRow?.sql ?? '';
  if (ddl.includes('paymentSubmitted')) return;

  db.exec(`PRAGMA foreign_keys = OFF`);
  db.exec(`
    CREATE TABLE orders_new (
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
      collector_latitude      REAL,
      collector_longitude     REAL,
      collector_poi_name      TEXT,
      collector_address_text  TEXT,
      package_id              TEXT,
      package_name            TEXT,
      package_base_price      REAL DEFAULT 0,
      selected_items_json     TEXT DEFAULT '[]',
      extra_items_json        TEXT DEFAULT '[]',
      extra_amount            REAL DEFAULT 0,
      final_amount            REAL DEFAULT 0,
      created_at              TEXT NOT NULL,
      updated_at              TEXT NOT NULL
    );
  `);

  db.exec(`
    INSERT INTO orders_new (
      id, order_no, company_id, user_id, user_name, user_company,
      merchant_id, merchant_name, delivery_type, address, phone, remark,
      goods_amount, delivery_fee, total_amount, status, payment_type,
      payment_screenshot_url, reject_reason, is_meal_collector,
      collector_name, collector_phone, collector_address,
      collector_latitude, collector_longitude, collector_poi_name, collector_address_text,
      package_id, package_name, package_base_price,
      selected_items_json, extra_items_json, extra_amount, final_amount,
      created_at, updated_at
    )
    SELECT
      id, order_no, company_id, user_id, user_name, user_company,
      merchant_id, merchant_name, delivery_type, address, phone, remark,
      goods_amount, delivery_fee, total_amount, status,
      COALESCE(payment_type, 'self_pay'),
      payment_screenshot_url, reject_reason, is_meal_collector,
      collector_name, collector_phone, collector_address,
      collector_latitude, collector_longitude, collector_poi_name, collector_address_text,
      package_id, package_name, package_base_price,
      selected_items_json, extra_items_json, extra_amount, final_amount,
      created_at, updated_at
    FROM orders;
  `);

  db.exec(`DROP TABLE orders`);
  db.exec(`ALTER TABLE orders_new RENAME TO orders`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id)`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_orders_merchant ON orders(merchant_id)`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)`);
  db.exec(`PRAGMA foreign_keys = ON`);
}

/**
 * 支付拆分字段 + mixed_pay 类型（仅新增列/扩展约束，保留历史数据）。
 */
function migrateOrdersPaymentSplit(db: Database.Database): void {
  if (!tableExists(db, 'orders')) return;

  const names = getColumnNames(db, 'orders');
  if (!names.has('package_amount')) {
    addColumn(db, 'ALTER TABLE orders ADD COLUMN package_amount REAL DEFAULT 0');
  }
  if (!names.has('company_pay_amount')) {
    addColumn(
      db,
      'ALTER TABLE orders ADD COLUMN company_pay_amount REAL DEFAULT 0',
    );
  }
  if (!names.has('employee_pay_amount')) {
    addColumn(
      db,
      'ALTER TABLE orders ADD COLUMN employee_pay_amount REAL DEFAULT 0',
    );
  }

  // 回填历史订单拆分字段
  db.exec(`
    UPDATE orders SET package_amount = COALESCE(package_base_price, goods_amount, 0)
    WHERE package_amount IS NULL OR package_amount = 0;
    UPDATE orders SET company_pay_amount = total_amount
    WHERE payment_type = 'company_pay' AND (company_pay_amount IS NULL OR company_pay_amount = 0);
    UPDATE orders SET employee_pay_amount = total_amount
    WHERE payment_type = 'self_pay' AND (employee_pay_amount IS NULL OR employee_pay_amount = 0);
  `);

  const ddlRow = db
    .prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'orders'`)
    .get() as { sql: string } | undefined;
  const ddl = ddlRow?.sql ?? '';
  if (ddl.includes('mixed_pay')) return;

  db.exec(`PRAGMA foreign_keys = OFF`);
  db.exec(`
    CREATE TABLE orders_new (
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
                                CHECK (payment_type IN ('self_pay', 'company_pay', 'mixed_pay')),
      payment_screenshot_url  TEXT,
      reject_reason           TEXT,
      is_meal_collector       INTEGER DEFAULT 0,
      collector_name          TEXT,
      collector_phone         TEXT,
      collector_address       TEXT,
      collector_latitude      REAL,
      collector_longitude     REAL,
      collector_poi_name      TEXT,
      collector_address_text  TEXT,
      package_id              TEXT,
      package_name            TEXT,
      package_base_price      REAL DEFAULT 0,
      selected_items_json     TEXT DEFAULT '[]',
      extra_items_json        TEXT DEFAULT '[]',
      extra_amount            REAL DEFAULT 0,
      final_amount            REAL DEFAULT 0,
      package_amount          REAL DEFAULT 0,
      company_pay_amount      REAL DEFAULT 0,
      employee_pay_amount     REAL DEFAULT 0,
      created_at              TEXT NOT NULL,
      updated_at              TEXT NOT NULL
    );
  `);

  db.exec(`
    INSERT INTO orders_new (
      id, order_no, company_id, user_id, user_name, user_company,
      merchant_id, merchant_name, delivery_type, address, phone, remark,
      goods_amount, delivery_fee, total_amount, status, payment_type,
      payment_screenshot_url, reject_reason, is_meal_collector,
      collector_name, collector_phone, collector_address,
      collector_latitude, collector_longitude, collector_poi_name, collector_address_text,
      package_id, package_name, package_base_price,
      selected_items_json, extra_items_json, extra_amount, final_amount,
      package_amount, company_pay_amount, employee_pay_amount,
      created_at, updated_at
    )
    SELECT
      id, order_no, company_id, user_id, user_name, user_company,
      merchant_id, merchant_name, delivery_type, address, phone, remark,
      goods_amount, delivery_fee, total_amount, status,
      COALESCE(payment_type, 'self_pay'),
      payment_screenshot_url, reject_reason, is_meal_collector,
      collector_name, collector_phone, collector_address,
      collector_latitude, collector_longitude, collector_poi_name, collector_address_text,
      package_id, package_name, package_base_price,
      selected_items_json, extra_items_json, extra_amount, final_amount,
      COALESCE(package_amount, package_base_price, goods_amount, 0),
      COALESCE(company_pay_amount, CASE WHEN payment_type = 'company_pay' THEN total_amount ELSE 0 END),
      COALESCE(employee_pay_amount, CASE WHEN payment_type = 'self_pay' THEN total_amount ELSE 0 END),
      created_at, updated_at
    FROM orders;
  `);

  db.exec(`DROP TABLE orders`);
  db.exec(`ALTER TABLE orders_new RENAME TO orders`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id)`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_orders_merchant ON orders(merchant_id)`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)`);
  db.exec(`PRAGMA foreign_keys = ON`);
}

function migrateOvertimeRosters(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS overtime_rosters (
      id              TEXT PRIMARY KEY,
      work_date       TEXT NOT NULL,
      employee_name   TEXT NOT NULL,
      phone           TEXT NOT NULL,
      department      TEXT NOT NULL,
      employee_no     TEXT,
      is_enabled      INTEGER NOT NULL DEFAULT 1,
      source          TEXT NOT NULL DEFAULT 'manual',
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_overtime_rosters_date_phone
      ON overtime_rosters(work_date, phone);
    CREATE INDEX IF NOT EXISTS idx_overtime_rosters_work_date
      ON overtime_rosters(work_date);
  `);
}

function migrateMealLabelPrints(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS meal_label_prints (
      id              TEXT PRIMARY KEY,
      merchant_id     TEXT NOT NULL,
      order_id        TEXT NOT NULL,
      label_code      TEXT NOT NULL,
      meal_type       TEXT NOT NULL,
      business_date   TEXT NOT NULL,
      employee_name   TEXT NOT NULL DEFAULT '',
      department      TEXT NOT NULL DEFAULT '',
      package_name    TEXT NOT NULL DEFAULT '',
      label_hash      TEXT NOT NULL UNIQUE,
      printed_at      TEXT NOT NULL,
      print_count     INTEGER NOT NULL DEFAULT 1,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE,
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_meal_label_prints_merchant_batch
      ON meal_label_prints(merchant_id, business_date, meal_type);
    CREATE INDEX IF NOT EXISTS idx_meal_label_prints_order
      ON meal_label_prints(order_id);
  `);
}

function migrateOvertimeMealUsages(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS overtime_meal_usages (
      id                TEXT PRIMARY KEY,
      roster_id         TEXT,
      employee_user_id  TEXT NOT NULL,
      employee_phone    TEXT NOT NULL,
      work_date         TEXT NOT NULL,
      meal_type         TEXT NOT NULL DEFAULT 'overtime',
      merchant_id       TEXT NOT NULL,
      order_id          TEXT NOT NULL UNIQUE,
      used_at           TEXT NOT NULL,
      created_at        TEXT NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id),
      FOREIGN KEY (order_id) REFERENCES orders(id)
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_overtime_usage_user_date
      ON overtime_meal_usages(work_date, employee_user_id, meal_type);
    CREATE INDEX IF NOT EXISTS idx_overtime_usage_phone_date
      ON overtime_meal_usages(work_date, employee_phone);
  `);
}

function migrateReviewsTable(db: Database.Database): void {
  db.exec(`
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
    CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);
  `);
}

/** 多维度评价字段（保留 rating 兼容旧客户端） */
function migrateReviewsDimensions(db: Database.Database): void {
  if (!tableExists(db, 'reviews')) return;
  addColumnIfMissing(
    db,
    'reviews',
    'overall_rating',
    'ALTER TABLE reviews ADD COLUMN overall_rating INTEGER',
  );
  addColumnIfMissing(
    db,
    'reviews',
    'taste_rating',
    'ALTER TABLE reviews ADD COLUMN taste_rating INTEGER',
  );
  addColumnIfMissing(
    db,
    'reviews',
    'hygiene_rating',
    'ALTER TABLE reviews ADD COLUMN hygiene_rating INTEGER',
  );
  addColumnIfMissing(
    db,
    'reviews',
    'service_rating',
    'ALTER TABLE reviews ADD COLUMN service_rating INTEGER',
  );
  addColumnIfMissing(
    db,
    'reviews',
    'delivery_rating',
    'ALTER TABLE reviews ADD COLUMN delivery_rating INTEGER',
  );
  db.exec(`
    UPDATE reviews SET overall_rating = rating WHERE overall_rating IS NULL;
    UPDATE reviews SET hygiene_rating = rating WHERE hygiene_rating IS NULL;
    UPDATE reviews SET taste_rating = rating WHERE taste_rating IS NULL;
    UPDATE reviews SET service_rating = rating WHERE service_rating IS NULL;
    UPDATE reviews SET delivery_rating = rating WHERE delivery_rating IS NULL;
  `);
}

function migrateOvertimeRosterMealType(db: Database.Database): void {
  if (!tableExists(db, 'overtime_rosters')) return;
  addColumnIfMissing(
    db,
    'overtime_rosters',
    'meal_type',
    "ALTER TABLE overtime_rosters ADD COLUMN meal_type TEXT NOT NULL DEFAULT 'lunch'",
  );
  db.exec(`
    UPDATE overtime_rosters SET meal_type = 'lunch'
    WHERE meal_type IS NULL OR meal_type = '' OR meal_type = 'overtime';
  `);
  db.exec(`DROP INDEX IF EXISTS idx_overtime_rosters_date_phone`);
  db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_overtime_rosters_date_phone_meal
      ON overtime_rosters(work_date, phone, meal_type);
  `);
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_overtime_rosters_date_meal
      ON overtime_rosters(work_date, meal_type);
  `);
}

/** overtime_meal_usages 金额明细（兼容旧库，仅新增列） */
function migrateOvertimeMealUsageAmounts(db: Database.Database): void {
  if (!tableExists(db, 'overtime_meal_usages')) return;
  addColumnIfMissing(
    db,
    'overtime_meal_usages',
    'company_pay_amount',
    'ALTER TABLE overtime_meal_usages ADD COLUMN company_pay_amount REAL',
  );
  addColumnIfMissing(
    db,
    'overtime_meal_usages',
    'employee_pay_amount',
    'ALTER TABLE overtime_meal_usages ADD COLUMN employee_pay_amount REAL',
  );
  addColumnIfMissing(
    db,
    'overtime_meal_usages',
    'order_total_amount',
    'ALTER TABLE overtime_meal_usages ADD COLUMN order_total_amount REAL',
  );
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_overtime_usage_roster
      ON overtime_meal_usages(roster_id);
  `);
  db.exec(`
    UPDATE overtime_meal_usages
    SET order_total_amount = (
          SELECT COALESCE(o.final_amount, o.total_amount, 0)
          FROM orders o WHERE o.id = overtime_meal_usages.order_id
        ),
        company_pay_amount = (
          SELECT COALESCE(o.company_pay_amount, 0)
          FROM orders o WHERE o.id = overtime_meal_usages.order_id
        ),
        employee_pay_amount = (
          SELECT COALESCE(o.employee_pay_amount, 0)
          FROM orders o WHERE o.id = overtime_meal_usages.order_id
        )
    WHERE order_total_amount IS NULL OR company_pay_amount IS NULL;
  `);
}

function migrateReviewAnonymous(db: Database.Database): void {
  if (!tableExists(db, 'reviews')) return;
  addColumnIfMissing(
    db,
    'reviews',
    'is_anonymous',
    'ALTER TABLE reviews ADD COLUMN is_anonymous INTEGER NOT NULL DEFAULT 0',
  );
}

function migrateMerchantHygieneMeta(db: Database.Database): void {
  if (!tableExists(db, 'merchants')) return;
  addColumnIfMissing(
    db,
    'merchants',
    'hygiene_score',
    'ALTER TABLE merchants ADD COLUMN hygiene_score REAL',
  );
  addColumnIfMissing(
    db,
    'merchants',
    'hygiene_review_count',
    'ALTER TABLE merchants ADD COLUMN hygiene_review_count INTEGER NOT NULL DEFAULT 0',
  );
  addColumnIfMissing(
    db,
    'merchants',
    'hygiene_score_30d',
    'ALTER TABLE merchants ADD COLUMN hygiene_score_30d REAL',
  );
  addColumnIfMissing(
    db,
    'merchants',
    'hygiene_risk_status',
    "ALTER TABLE merchants ADD COLUMN hygiene_risk_status TEXT NOT NULL DEFAULT 'normal'",
  );
}

function migrateOrdersSettlement(db: Database.Database): void {
  if (!tableExists(db, 'orders')) return;
  addColumnIfMissing(
    db,
    'orders',
    'settlement_status',
    "ALTER TABLE orders ADD COLUMN settlement_status TEXT NOT NULL DEFAULT 'not_paid'",
  );
  addColumnIfMissing(
    db,
    'orders',
    'payment_channel',
    "ALTER TABLE orders ADD COLUMN payment_channel TEXT NOT NULL DEFAULT 'manual_qr'",
  );
  addColumnIfMissing(
    db,
    'orders',
    'completed_at',
    'ALTER TABLE orders ADD COLUMN completed_at TEXT',
  );
  addColumnIfMissing(
    db,
    'orders',
    'settlement_eligible_at',
    'ALTER TABLE orders ADD COLUMN settlement_eligible_at TEXT',
  );
}

function migratePaymentAndSettlementTables(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS payment_transactions (
      id                    TEXT PRIMARY KEY,
      order_id              TEXT NOT NULL,
      payment_no            TEXT NOT NULL UNIQUE,
      channel               TEXT NOT NULL CHECK (channel IN ('wechat_pay','alipay','manual_qr')),
      amount                REAL NOT NULL,
      status                TEXT NOT NULL DEFAULT 'created'
                              CHECK (status IN ('created','pending','paid','failed','closed','refunded')),
      provider_trade_no     TEXT,
      request_payload_json  TEXT DEFAULT '{}',
      notify_payload_json   TEXT DEFAULT '{}',
      paid_at               TEXT,
      created_at            TEXT NOT NULL,
      updated_at            TEXT NOT NULL,
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_payment_tx_order ON payment_transactions(order_id);
    CREATE INDEX IF NOT EXISTS idx_payment_tx_status ON payment_transactions(status);

    CREATE TABLE IF NOT EXISTS merchant_settlements (
      id                        TEXT PRIMARY KEY,
      merchant_id               TEXT NOT NULL,
      order_id                  TEXT NOT NULL UNIQUE,
      settlement_no             TEXT NOT NULL UNIQUE,
      order_amount              REAL NOT NULL,
      company_pay_amount        REAL NOT NULL DEFAULT 0,
      employee_pay_amount       REAL NOT NULL DEFAULT 0,
      platform_service_fee      REAL NOT NULL DEFAULT 0,
      merchant_receivable_amount REAL NOT NULL,
      status                    TEXT NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','eligible','settled','blocked','refunded')),
      completed_at              TEXT,
      settlement_eligible_at    TEXT,
      settled_at                TEXT,
      block_reason              TEXT,
      created_at                TEXT NOT NULL,
      updated_at                TEXT NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE,
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_settlements_merchant ON merchant_settlements(merchant_id);
    CREATE INDEX IF NOT EXISTS idx_settlements_status ON merchant_settlements(status);

    CREATE TABLE IF NOT EXISTS merchant_remediation_notices (
      id            TEXT PRIMARY KEY,
      merchant_id   TEXT NOT NULL,
      reason        TEXT NOT NULL,
      hygiene_avg   REAL,
      status        TEXT NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open','acknowledged','closed')),
      created_at    TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_remediation_merchant ON merchant_remediation_notices(merchant_id);
  `);
}

function migrateMerchantWithdrawals(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS merchant_withdrawals (
      id            TEXT PRIMARY KEY,
      merchant_id   TEXT NOT NULL,
      amount        REAL NOT NULL,
      status        TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','approved','rejected','paid')),
      account_name  TEXT NOT NULL DEFAULT '',
      account_type  TEXT NOT NULL DEFAULT '',
      account_no    TEXT NOT NULL DEFAULT '',
      remark        TEXT,
      created_at    TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      reviewed_at   TEXT,
      FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_withdrawals_merchant ON merchant_withdrawals(merchant_id);
    CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON merchant_withdrawals(status);
  `);
}

function migrateSystemConfig(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS system_config (
      key         TEXT PRIMARY KEY,
      value_json  TEXT NOT NULL,
      updated_at  TEXT NOT NULL
    );
  `);
  const row = db
    .prepare(`SELECT key FROM system_config WHERE key = 'meal_deadlines'`)
    .get();
  if (!row) {
    const defaults = {
      breakfast: '07:30',
      lunch: '09:30',
      dinner: '15:00',
      overtime: '17:30',
    };
    db.prepare(
      `INSERT INTO system_config (key, value_json, updated_at) VALUES (?, ?, ?)`,
    ).run('meal_deadlines', JSON.stringify(defaults), nowIso());
  }
  const appRow = db
    .prepare(`SELECT key FROM system_config WHERE key = 'app_settings'`)
    .get();
  if (!appRow) {
    const appDefaults = {
      allowCancelOrder: true,
      enableReview: false,
      enableMerchantAutoRefresh: false,
      requirePaymentScreenshot: true,
      allowMerchantReject: true,
      showSoldOutDishes: true,
      labelPrintWidthMm: 50,
      labelPrintFontSizePt: 12,
    };
    db.prepare(
      `INSERT INTO system_config (key, value_json, updated_at) VALUES (?, ?, ?)`,
    ).run('app_settings', JSON.stringify(appDefaults), nowIso());
  }
}

function migrateUsersCanOrder(db: Database.Database): void {
  addColumnIfMissing(
    db,
    'users',
    'can_order',
    'ALTER TABLE users ADD COLUMN can_order INTEGER NOT NULL DEFAULT 1',
  );
  db.prepare(
    `UPDATE users SET can_order = 1 WHERE can_order IS NULL`,
  ).run();
}

function migrateUsersPassword(db: Database.Database): void {
  addColumnIfMissing(
    db,
    'users',
    'password_hash',
    'ALTER TABLE users ADD COLUMN password_hash TEXT',
  );
  addColumnIfMissing(
    db,
    'users',
    'password_updated_at',
    'ALTER TABLE users ADD COLUMN password_updated_at TEXT',
  );
  const hash = defaultPasswordHash();
  const now = nowIso();
  db.prepare(
    `UPDATE users SET password_hash = ?, password_updated_at = ?
     WHERE password_hash IS NULL OR password_hash = ''`,
  ).run(hash, now);
}

function migrateUsersAvatarUrl(db: Database.Database): void {
  addColumnIfMissing(
    db,
    'users',
    'avatar_url',
    'ALTER TABLE users ADD COLUMN avatar_url TEXT',
  );
}

function migrateAdminOperationLogs(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS admin_operation_logs (
      id                TEXT PRIMARY KEY,
      operator_user_id  TEXT,
      operator_role     TEXT,
      action            TEXT NOT NULL,
      target_type       TEXT,
      target_id         TEXT,
      detail_json       TEXT,
      ip_address        TEXT,
      created_at        TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_admin_op_logs_created
      ON admin_operation_logs(created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_admin_op_logs_action
      ON admin_operation_logs(action);
  `);
}

/**
 * 订单沟通：会话 + 消息（仅新增，旧表/字段不动）。
 * 使用 ADD TABLE 风格，重复执行幂等。
 */
function migrateConversations(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS conversations (
      id                      TEXT PRIMARY KEY,
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
  `);
  db.exec(`
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
  `);
}

function seedDefaultCompany(db: Database.Database): void {
  const now = nowIso();
  const existing = db
    .prepare(`SELECT id FROM companies WHERE id = 'comp_default'`)
    .get();
  if (!existing) {
    db.prepare(
      `INSERT INTO companies (id, company_name, admin_user_id, status, created_at, updated_at)
       VALUES ('comp_default', '默认企业', NULL, 'active', ?, ?)`,
    ).run(now, now);
  }
  db.prepare(`UPDATE users SET company_id = 'comp_default' WHERE company_id IS NULL`).run();
  db.prepare(`UPDATE merchants SET company_id = 'comp_default' WHERE company_id IS NULL`).run();
  db.prepare(`UPDATE orders SET company_id = 'comp_default' WHERE company_id IS NULL`).run();
}

function migrateUsersRoleAndCompany(db: Database.Database): void {
  if (!tableExists(db, 'users')) {
    return;
  }

  const cols = getColumnNames(db, 'users');
  const hasTargetColumns =
    cols.has('role') &&
    cols.has('status') &&
    cols.has('company_id') &&
    cols.has('nickname');

  const ddl = db
    .prepare(`SELECT sql FROM sqlite_master WHERE type='table' AND name='users'`)
    .get() as { sql: string } | undefined;

  // 目标字段已通过 ADD COLUMN 补齐，或 DDL 已包含 admin 角色约束，无需重建
  if (hasTargetColumns) {
    if (!ddl?.sql || ddl.sql.includes("'admin'") || !ddl.sql.match(/role[^)]*CHECK/i)) {
      return;
    }
  } else if (ddl?.sql?.includes("'admin'")) {
    return;
  }

  db.exec(`PRAGMA foreign_keys = OFF`);
  const migrate = db.transaction(() => {
    db.exec(`DROP TABLE IF EXISTS users_new`);
    db.exec(`
      CREATE TABLE users_new (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        nickname    TEXT,
        phone       TEXT NOT NULL UNIQUE,
        role        TEXT NOT NULL DEFAULT 'employee',
        status      TEXT NOT NULL DEFAULT 'active',
        company_id  TEXT,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL
      );
    `);
    db.exec(`
      INSERT INTO users_new (id, name, nickname, phone, role, status, company_id, created_at, updated_at)
      SELECT id, name, nickname, phone, role, status, company_id, created_at, updated_at FROM users;
    `);
    db.exec(`DROP TABLE users`);
    db.exec(`ALTER TABLE users_new RENAME TO users`);
  });

  try {
    migrate();
  } finally {
    db.exec(`PRAGMA foreign_keys = ON`);
    db.exec(`DROP TABLE IF EXISTS users_new`);
  }
}

function migrateOrders(db: Database.Database): void {
  if (!tableExists(db, 'orders')) return;

  addColumnIfMissing(db, 'orders', 'company_id', 'ALTER TABLE orders ADD COLUMN company_id TEXT');
  addColumnIfMissing(
    db,
    'orders',
    'is_meal_collector',
    'ALTER TABLE orders ADD COLUMN is_meal_collector INTEGER DEFAULT 0',
  );
  addColumnIfMissing(db, 'orders', 'collector_name', 'ALTER TABLE orders ADD COLUMN collector_name TEXT');
  addColumnIfMissing(db, 'orders', 'collector_phone', 'ALTER TABLE orders ADD COLUMN collector_phone TEXT');
  addColumnIfMissing(
    db,
    'orders',
    'collector_address',
    'ALTER TABLE orders ADD COLUMN collector_address TEXT',
  );
  addColumnIfMissing(
    db,
    'orders',
    'collector_latitude',
    'ALTER TABLE orders ADD COLUMN collector_latitude REAL',
  );
  addColumnIfMissing(
    db,
    'orders',
    'collector_longitude',
    'ALTER TABLE orders ADD COLUMN collector_longitude REAL',
  );
  addColumnIfMissing(
    db,
    'orders',
    'collector_poi_name',
    'ALTER TABLE orders ADD COLUMN collector_poi_name TEXT',
  );
  addColumnIfMissing(
    db,
    'orders',
    'collector_address_text',
    'ALTER TABLE orders ADD COLUMN collector_address_text TEXT',
  );
}

function migrateDeliveryLocations(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS delivery_locations (
      id TEXT PRIMARY KEY,
      company_id TEXT,
      merchant_id TEXT NOT NULL,
      order_batch_key TEXT NOT NULL UNIQUE,
      date TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      latitude REAL,
      longitude REAL,
      address_text TEXT,
      status TEXT NOT NULL DEFAULT 'delivering',
      updated_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
  `);
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_delivery_locations_batch
    ON delivery_locations(order_batch_key);
  `);
}

function migrateUsers(db: Database.Database): void {
  if (!tableExists(db, 'users')) return;

  const names = getColumnNames(db, 'users');

  if (!names.has('nickname')) {
    addColumn(db, 'ALTER TABLE users ADD COLUMN nickname TEXT');
    db.exec(`UPDATE users SET nickname = name WHERE nickname IS NULL`);
  }
  if (!names.has('status')) {
    addColumn(
      db,
      "ALTER TABLE users ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
    );
  }
  if (!names.has('company_id')) {
    addColumn(db, 'ALTER TABLE users ADD COLUMN company_id TEXT');
  }
}

function migrateMerchantsCommercial(db: Database.Database): void {
  if (!tableExists(db, 'merchants')) return;

  addColumnIfMissing(db, 'merchants', 'company_id', 'ALTER TABLE merchants ADD COLUMN company_id TEXT');
  addColumnIfMissing(db, 'merchants', 'phone', 'ALTER TABLE merchants ADD COLUMN phone TEXT');
  addColumnIfMissing(
    db,
    'merchants',
    'onboarding_status',
    "ALTER TABLE merchants ADD COLUMN onboarding_status TEXT NOT NULL DEFAULT 'approved'",
  );
  addColumnIfMissing(
    db,
    'merchants',
    'menu_init',
    'ALTER TABLE merchants ADD COLUMN menu_init INTEGER DEFAULT 0',
  );
  addColumnIfMissing(
    db,
    'merchants',
    'is_enabled',
    'ALTER TABLE merchants ADD COLUMN is_enabled INTEGER DEFAULT 1',
  );
}

function migrateMerchantsOnboarding(db: Database.Database): void {
  if (!tableExists(db, 'merchants')) return;

  const names = getColumnNames(db, 'merchants');
  const adds: [string, string][] = [
    ['contact_name', 'ALTER TABLE merchants ADD COLUMN contact_name TEXT'],
    ['contact_phone', 'ALTER TABLE merchants ADD COLUMN contact_phone TEXT'],
    ['short_name', 'ALTER TABLE merchants ADD COLUMN short_name TEXT'],
    [
      'supported_meal_types_json',
      "ALTER TABLE merchants ADD COLUMN supported_meal_types_json TEXT DEFAULT '[]'",
    ],
    [
      'delivery_modes_json',
      "ALTER TABLE merchants ADD COLUMN delivery_modes_json TEXT DEFAULT '[]'",
    ],
    ['delivery_scope', 'ALTER TABLE merchants ADD COLUMN delivery_scope TEXT'],
    [
      'estimated_delivery_time',
      'ALTER TABLE merchants ADD COLUMN estimated_delivery_time TEXT',
    ],
    ['payment_method', 'ALTER TABLE merchants ADD COLUMN payment_method TEXT'],
    [
      'payment_receiver_name',
      'ALTER TABLE merchants ADD COLUMN payment_receiver_name TEXT',
    ],
    [
      'business_license_url',
      'ALTER TABLE merchants ADD COLUMN business_license_url TEXT',
    ],
    ['food_license_url', 'ALTER TABLE merchants ADD COLUMN food_license_url TEXT'],
    ['store_photo_url', 'ALTER TABLE merchants ADD COLUMN store_photo_url TEXT'],
    ['reject_reason', 'ALTER TABLE merchants ADD COLUMN reject_reason TEXT'],
    ['reviewed_by', 'ALTER TABLE merchants ADD COLUMN reviewed_by TEXT'],
    ['reviewed_at', 'ALTER TABLE merchants ADD COLUMN reviewed_at TEXT'],
    ['remark', 'ALTER TABLE merchants ADD COLUMN remark TEXT'],
  ];
  for (const [col, sql] of adds) {
    if (!names.has(col)) addColumn(db, sql);
  }
}

function migrateMerchantsProfile(db: Database.Database): void {
  if (!tableExists(db, 'merchants')) return;

  addColumnIfMissing(
    db,
    'merchants',
    'description',
    'ALTER TABLE merchants ADD COLUMN description TEXT',
  );
  addColumnIfMissing(
    db,
    'merchants',
    'meal_opening_hours_json',
    "ALTER TABLE merchants ADD COLUMN meal_opening_hours_json TEXT DEFAULT '{}'",
  );
}

/**
 * 企业级商家审核所需的扩展字段（向后兼容）。
 *
 * 注意：本迁移**只新增列**，不删除任何旧字段。
 * 旧的 delivery_scope / estimated_delivery_time / delivery_fee 仍然保留在表中，
 * 入驻页面不再展示和提交，但历史商家数据不受影响。
 */
function migrateMerchantsEnterpriseFields(db: Database.Database): void {
  if (!tableExists(db, 'merchants')) return;
  const adds: [string, string][] = [
    ['store_display_name', 'ALTER TABLE merchants ADD COLUMN store_display_name TEXT'],
    [
      'customer_service_phone',
      'ALTER TABLE merchants ADD COLUMN customer_service_phone TEXT',
    ],
    [
      'served_company_text',
      'ALTER TABLE merchants ADD COLUMN served_company_text TEXT',
    ],
    [
      'business_days_json',
      "ALTER TABLE merchants ADD COLUMN business_days_json TEXT DEFAULT '[]'",
    ],
    [
      'business_hours_start',
      'ALTER TABLE merchants ADD COLUMN business_hours_start TEXT',
    ],
    [
      'business_hours_end',
      'ALTER TABLE merchants ADD COLUMN business_hours_end TEXT',
    ],
    [
      'meal_order_deadlines_json',
      "ALTER TABLE merchants ADD COLUMN meal_order_deadlines_json TEXT DEFAULT '{}'",
    ],
    [
      'payment_subject_type',
      'ALTER TABLE merchants ADD COLUMN payment_subject_type TEXT',
    ],
    [
      'payment_subject_name',
      'ALTER TABLE merchants ADD COLUMN payment_subject_name TEXT',
    ],
    [
      'bank_account_name',
      'ALTER TABLE merchants ADD COLUMN bank_account_name TEXT',
    ],
    ['bank_name', 'ALTER TABLE merchants ADD COLUMN bank_name TEXT'],
    [
      'bank_account_number',
      'ALTER TABLE merchants ADD COLUMN bank_account_number TEXT',
    ],
    [
      'business_license_subject',
      'ALTER TABLE merchants ADD COLUMN business_license_subject TEXT',
    ],
    [
      'business_license_valid_until',
      'ALTER TABLE merchants ADD COLUMN business_license_valid_until TEXT',
    ],
    [
      'unified_social_credit_code',
      'ALTER TABLE merchants ADD COLUMN unified_social_credit_code TEXT',
    ],
    [
      'food_license_number',
      'ALTER TABLE merchants ADD COLUMN food_license_number TEXT',
    ],
    [
      'food_license_valid_until',
      'ALTER TABLE merchants ADD COLUMN food_license_valid_until TEXT',
    ],
    [
      'licensed_business_scope',
      'ALTER TABLE merchants ADD COLUMN licensed_business_scope TEXT',
    ],
    [
      'kitchen_photo_url',
      'ALTER TABLE merchants ADD COLUMN kitchen_photo_url TEXT',
    ],
    [
      'health_certificate_url',
      'ALTER TABLE merchants ADD COLUMN health_certificate_url TEXT',
    ],
    // 多图 / 多选向后兼容字段：仅新增，旧 *_url 字段保留
    [
      'payment_methods_json',
      "ALTER TABLE merchants ADD COLUMN payment_methods_json TEXT DEFAULT '[]'",
    ],
    [
      'wechat_payment_qr_urls_json',
      "ALTER TABLE merchants ADD COLUMN wechat_payment_qr_urls_json TEXT DEFAULT '[]'",
    ],
    [
      'alipay_payment_qr_urls_json',
      "ALTER TABLE merchants ADD COLUMN alipay_payment_qr_urls_json TEXT DEFAULT '[]'",
    ],
    [
      'business_license_urls_json',
      "ALTER TABLE merchants ADD COLUMN business_license_urls_json TEXT DEFAULT '[]'",
    ],
    [
      'food_license_urls_json',
      "ALTER TABLE merchants ADD COLUMN food_license_urls_json TEXT DEFAULT '[]'",
    ],
    [
      'kitchen_photo_urls_json',
      "ALTER TABLE merchants ADD COLUMN kitchen_photo_urls_json TEXT DEFAULT '[]'",
    ],
    [
      'health_certificate_urls_json',
      "ALTER TABLE merchants ADD COLUMN health_certificate_urls_json TEXT DEFAULT '[]'",
    ],
    [
      'store_photo_urls_json',
      "ALTER TABLE merchants ADD COLUMN store_photo_urls_json TEXT DEFAULT '[]'",
    ],
  ];
  const names = getColumnNames(db, 'merchants');
  for (const [col, sql] of adds) {
    if (!names.has(col)) addColumn(db, sql);
  }
}

function migrateSmsCodes(db: Database.Database): void {
  db.exec(`
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
  `);
}

function migrateEmployeeProfiles(db: Database.Database): void {
  db.exec(`
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
  `);
}

/** 商用初始化：平台管理员 + 演示企业（可重复执行） */
export function seedCommercialDefaults(db: Database.Database): void {
  const now = nowIso();
  seedDefaultCompany(db);

  const platformAdminPhone = process.env.PLATFORM_ADMIN_PHONE || '13700000000';
  let admin = db
    .prepare<[string], { id: string }>(
      'SELECT id FROM users WHERE phone = ?',
    )
    .get(platformAdminPhone);

  if (!admin) {
    const adminId = `u_admin_${nanoid(6)}`;
    const pwdHash = defaultPasswordHash();
    db.prepare(
      `INSERT INTO users (id, name, nickname, phone, role, status, company_id, password_hash, password_updated_at, created_at, updated_at)
       VALUES (?, '平台管理员', '平台管理员', ?, 'admin', 'active', NULL, ?, ?, ?, ?)`,
    ).run(adminId, platformAdminPhone, pwdHash, now, now, now);
    admin = { id: adminId };
  } else {
    db.prepare(
      `UPDATE users SET role = 'admin', status = 'active', company_id = NULL, updated_at = ? WHERE id = ?`,
    ).run(now, admin.id);
    const pwdHash = defaultPasswordHash();
    db.prepare(
      `UPDATE users SET password_hash = COALESCE(password_hash, ?), password_updated_at = COALESCE(password_updated_at, ?) WHERE id = ?`,
    ).run(pwdHash, now, admin.id);
  }
}
