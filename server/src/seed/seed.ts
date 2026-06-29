import 'dotenv/config';
import { nanoid } from 'nanoid';
import { closeDb, getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MealType } from '../models/types';

interface NearbyMerchantSeed {
  id: string;
  name: string;
  distance: number;
  rating: number;
  monthSold: number;
  hygieneGrade: string;
  address: string;
  deliveryFee: number;
}

interface DishSeed {
  merchantId: string;
  name: string;
  description: string;
  price: number;
  mealType: MealType;
  tags: string[];
}

const nearbyMerchants: NearbyMerchantSeed[] = [
  {
    id: 'm_1',
    name: '绿禾餐饮',
    distance: 120,
    rating: 4.8,
    monthSold: 1288,
    hygieneGrade: 'A',
    address: '科技园 A 区 1 栋',
    deliveryFee: 3,
  },
  {
    id: 'm_2',
    name: '食光小厨',
    distance: 180,
    rating: 4.7,
    monthSold: 980,
    hygieneGrade: 'A',
    address: '科技园 A 区 3 栋',
    deliveryFee: 3,
  },
  {
    id: 'm_3',
    name: '轻食工坊',
    distance: 210,
    rating: 4.6,
    monthSold: 720,
    hygieneGrade: 'A',
    address: '科技园 B 区 2 栋',
    deliveryFee: 3,
  },
  {
    id: 'm_4',
    name: '家常味道',
    distance: 260,
    rating: 4.8,
    monthSold: 1500,
    hygieneGrade: 'A',
    address: '科技园 B 区 5 栋',
    deliveryFee: 3,
  },
];

function buildNearbyDishes(): DishSeed[] {
  const out: DishSeed[] = [];
  // m_1 绿禾餐饮
  out.push(
    { merchantId: 'm_1', name: '香煎鸡胸肉饭', description: '低脂高蛋白', price: 16.8, mealType: 'lunch', tags: ['健康', '推荐'] },
    { merchantId: 'm_1', name: '番茄牛腩饭', description: '番茄酸甜，牛腩软糯', price: 15.8, mealType: 'lunch', tags: ['实惠', '推荐'] },
    { merchantId: 'm_1', name: '清炒时蔬', description: '时令蔬菜，清淡爽口', price: 6.8, mealType: 'lunch', tags: ['健康'] },
    { merchantId: 'm_1', name: '玉米排骨汤', description: '小火慢炖', price: 4.8, mealType: 'lunch', tags: ['健康'] },
    { merchantId: 'm_1', name: '杂粮饭', description: '多种谷物', price: 2, mealType: 'lunch', tags: ['健康'] },
    { merchantId: 'm_1', name: '原味豆浆', description: '现磨豆浆', price: 3, mealType: 'breakfast', tags: ['健康'] },
  );
  // m_2 食光小厨
  out.push(
    { merchantId: 'm_2', name: '宫保鸡丁饭', description: '经典川菜', price: 18, mealType: 'lunch', tags: ['推荐'] },
    { merchantId: 'm_2', name: '冬瓜汤', description: '清爽冬瓜汤', price: 4, mealType: 'lunch', tags: ['健康'] },
  );
  // m_3 轻食工坊
  out.push(
    { merchantId: 'm_3', name: '鸡胸肉沙拉', description: '低脂高蛋白', price: 22, mealType: 'lunch', tags: ['健康', '推荐'] },
    { merchantId: 'm_3', name: '藜麦饭团', description: '藜麦杂粮', price: 12, mealType: 'lunch', tags: ['健康'] },
    { merchantId: 'm_3', name: '美式咖啡', description: '现磨美式', price: 8, mealType: 'breakfast', tags: ['推荐'] },
  );
  // m_4 家常味道
  out.push(
    { merchantId: 'm_4', name: '红烧肉饭', description: '肥而不腻', price: 19.8, mealType: 'lunch', tags: ['推荐'] },
    { merchantId: 'm_4', name: '麻婆豆腐饭', description: '麻辣鲜香', price: 14, mealType: 'lunch', tags: [] },
  );
  return out;
}

function buildSelfDishes(merchantId: string): DishSeed[] {
  return [
    // 早餐
    { merchantId, name: '皮蛋瘦肉粥', description: '咸香细腻', price: 6, mealType: 'breakfast', tags: ['推荐'] },
    { merchantId, name: '小笼包（6个）', description: '现蒸现吃', price: 8, mealType: 'breakfast', tags: [] },
    { merchantId, name: '豆浆', description: '现磨', price: 3, mealType: 'breakfast', tags: ['健康'] },
    // 中餐
    { merchantId, name: '黄焖鸡米饭', description: '鸡肉鲜嫩，酱香浓郁', price: 18, mealType: 'lunch', tags: ['推荐'] },
    { merchantId, name: '番茄炒蛋', description: '家常滋味', price: 12, mealType: 'lunch', tags: [] },
    { merchantId, name: '青椒牛肉丝', description: '下饭', price: 16, mealType: 'lunch', tags: [] },
    // 晚餐
    { merchantId, name: '清炒时蔬', description: '时令蔬菜', price: 6, mealType: 'dinner', tags: ['健康'] },
    { merchantId, name: '玉米排骨汤', description: '小火慢炖', price: 8, mealType: 'dinner', tags: ['健康'] },
    { merchantId, name: '杂粮饭', description: '膳食纤维丰富', price: 2, mealType: 'dinner', tags: ['健康'] },
    // 加班餐
    { merchantId, name: '鸡胸肉轻食', description: '低脂高蛋白', price: 22, mealType: 'overtime', tags: ['健康', '低脂'] },
    { merchantId, name: '牛肉饭团', description: '便于携带', price: 14, mealType: 'overtime', tags: ['推荐'] },
    { merchantId, name: '原味豆浆', description: '现磨', price: 3, mealType: 'overtime', tags: ['健康'] },
  ];
}

function run() {
  const db = getDb();
  const now = nowIso();

  console.log('[seed] 开始写入种子数据...');

  // 清空表（顺序：order_items → orders → dishes → merchants → users）
  db.exec(`
    DELETE FROM order_items;
    DELETE FROM orders;
    DELETE FROM dishes;
    DELETE FROM merchants;
    DELETE FROM users;
  `);

  // 员工
  const empId = 'u_emp_1';
  db.prepare(
    `INSERT INTO users (id, name, phone, role, created_at, updated_at)
     VALUES (?, ?, ?, 'employee', ?, ?)`,
  ).run(empId, '张三', '13800000000', now, now);

  // 商家账号 + 主商家（绿健食堂）
  const merUserId = 'u_mer_1';
  db.prepare(
    `INSERT INTO users (id, name, phone, role, created_at, updated_at)
     VALUES (?, ?, ?, 'merchant', ?, ?)`,
  ).run(merUserId, '绿健食堂', '13900000000', now, now);

  const selfMerchantId = 'm_self';
  db.prepare(
    `INSERT INTO merchants
       (id, user_id, name, logo_url, address, distance_text, distance,
        rating, month_sold, hygiene_grade, is_open,
        payment_qr_code_url, delivery_fee, created_at, updated_at)
     VALUES (?, ?, ?, 'logo', ?, '0m', 0, 4.8, 1860, 'A', 1, 'qr', 3, ?, ?)`,
  ).run(selfMerchantId, merUserId, '绿健食堂', '科技园 A 区 综合楼 1 层', now, now);

  // 附近商家
  for (const m of nearbyMerchants) {
    db.prepare(
      `INSERT INTO merchants
         (id, user_id, name, logo_url, address, distance_text, distance,
          rating, month_sold, hygiene_grade, is_open,
          payment_qr_code_url, delivery_fee, created_at, updated_at)
       VALUES (?, NULL, ?, 'logo', ?, ?, ?, ?, ?, ?, 1, 'qr', ?, ?, ?)`,
    ).run(
      m.id,
      m.name,
      m.address,
      `${m.distance}m`,
      m.distance,
      m.rating,
      m.monthSold,
      m.hygieneGrade,
      m.deliveryFee,
      now,
      now,
    );
  }

  // 菜品
  const allDishes = [...buildNearbyDishes(), ...buildSelfDishes(selfMerchantId)];
  for (const d of allDishes) {
    db.prepare(
      `INSERT INTO dishes
         (id, merchant_id, name, image_url, description, price, meal_type,
          tags_json, is_available, created_at, updated_at)
       VALUES (?, ?, ?, 'dish', ?, ?, ?, ?, 1, ?, ?)`,
    ).run(
      `d_${nanoid(8)}`,
      d.merchantId,
      d.name,
      d.description,
      d.price,
      d.mealType,
      JSON.stringify(d.tags),
      now,
      now,
    );
  }

  // 演示订单（绿健食堂 = m_self）
  function insertSeedOrder(args: {
    id: string;
    no: string;
    userName: string;
    userCompany: string;
    deliveryType: 'delivery' | 'selfPickup';
    address: string;
    phone: string;
    items: { name: string; price: number; qty: number; mealType: MealType }[];
    deliveryFee: number;
    status:
      | 'pendingMerchantConfirm'
      | 'accepted'
      | 'completed';
    minutesAgo: number;
  }) {
    const goods = args.items.reduce((s, it) => s + it.price * it.qty, 0);
    const total = Number((goods + args.deliveryFee).toFixed(2));
    const createdAt = new Date(Date.now() - args.minutesAgo * 60000).toISOString();
    db.prepare(
      `INSERT INTO orders
         (id, order_no, user_id, user_name, user_company,
          merchant_id, merchant_name, delivery_type,
          address, phone, remark,
          goods_amount, delivery_fee, total_amount, status,
          payment_screenshot_url, created_at, updated_at)
       VALUES (?, ?, NULL, ?, ?, ?, '绿健食堂', ?, ?, ?, '', ?, ?, ?, ?, NULL, ?, ?)`,
    ).run(
      args.id,
      args.no,
      args.userName,
      args.userCompany,
      selfMerchantId,
      args.deliveryType,
      args.address,
      args.phone,
      goods,
      args.deliveryFee,
      total,
      args.status,
      createdAt,
      createdAt,
    );
    for (const it of args.items) {
      db.prepare(
        `INSERT INTO order_items
           (order_id, dish_id, dish_name, dish_image_url, dish_description,
            meal_type, price, quantity, subtotal)
         VALUES (?, NULL, ?, 'dish', '', ?, ?, ?, ?)`,
      ).run(
        args.id,
        it.name,
        it.mealType,
        it.price,
        it.qty,
        Number((it.price * it.qty).toFixed(2)),
      );
    }
  }

  insertSeedOrder({
    id: 'O20240516001',
    no: '20240516001',
    userName: '王先生',
    userCompany: '北京创智科技有限公司',
    deliveryType: 'selfPickup',
    address: '科技园 A 区 综合楼 1 层',
    phone: '138 ****5678',
    items: [
      { name: '黄焖鸡米饭', price: 16, qty: 1, mealType: 'lunch' },
      { name: '清炒时蔬', price: 6, qty: 2, mealType: 'lunch' },
    ],
    deliveryFee: 0,
    status: 'pendingMerchantConfirm',
    minutesAgo: 25,
  });
  insertSeedOrder({
    id: 'O20240516002',
    no: '20240516002',
    userName: '李女士',
    userCompany: '北京智创科技有限公司',
    deliveryType: 'delivery',
    address: '北京市朝阳区望京街道望京 SOHO T2-B 座 1503 室',
    phone: '159 ****8888',
    items: [
      { name: '番茄炒蛋', price: 12, qty: 1, mealType: 'lunch' },
      { name: '玉米排骨汤', price: 8, qty: 1, mealType: 'lunch' },
      { name: '小笼包（6个）', price: 8, qty: 2, mealType: 'breakfast' },
    ],
    deliveryFee: 1.5,
    status: 'accepted',
    minutesAgo: 75,
  });
  insertSeedOrder({
    id: 'O20240516003',
    no: '20240516003',
    userName: '张先生',
    userCompany: '科技园 A 区 行政部',
    deliveryType: 'selfPickup',
    address: '科技园 A 区 综合楼 1 层',
    phone: '137 ****1234',
    items: [
      { name: '黄焖鸡米饭', price: 16, qty: 1, mealType: 'lunch' },
      { name: '清炒时蔬', price: 6, qty: 1, mealType: 'lunch' },
      { name: '杂粮饭', price: 2, qty: 2, mealType: 'lunch' },
    ],
    deliveryFee: 0,
    status: 'completed',
    minutesAgo: 170,
  });

  console.log('[seed] 完成 ✅');
  console.log('员工账号：13800000000');
  console.log('商家账号：13900000000');
}

try {
  run();
} finally {
  closeDb();
}
