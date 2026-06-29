# 非攻云餐 - 后端 API 接口契约

> 本文档列出 App 接入真实后端所需的全部接口。
>
> - 所有接口以 `apiBaseUrl`(`lib/api/api_config.dart`) 为根。
> - 占位地址：`http://localhost:3000/api`
> - 上线时统一替换为生产域名。
> - 鉴权方式：请求头 `Authorization: Bearer <token>`（登录后下发）。
> - 所有时间字段统一使用 ISO8601 字符串。
> - 所有金额字段统一使用人民币 `number`，单位为元（小数最多 2 位）。

---

## 通用响应结构

成功：

```json
{
  "code": 0,
  "message": "ok",
  "data": { ... 业务数据 ... }
}
```

失败：

```json
{
  "code": 40001,
  "message": "手机号格式错误",
  "data": null
}
```

> 前端约定：HTTP 2xx + `code == 0` 表示成功，其它视为业务/系统错误，由
> `ApiClient` 统一抛出 `ApiException`。

---

## 枚举对照

| 业务含义 | 枚举值（字符串）|
|---|---|
| 身份 - 员工 | `employee` |
| 身份 - 商家 | `merchant` |
| 餐段 - 早餐 | `breakfast` |
| 餐段 - 中餐 | `lunch` |
| 餐段 - 晚餐 | `dinner` |
| 餐段 - 加班餐 | `overtime` |
| 配送 - 配送 | `delivery` |
| 配送 - 自取 | `selfPickup` |
| 订单 - 待付款 | `pendingPayment` |
| 订单 - 待商家确认 | `pendingMerchantConfirm` |
| 订单 - 已接单 | `accepted` |
| 订单 - 配送中 | `delivering` |
| 订单 - 已完成 | `completed` |
| 订单 - 已取消 | `cancelled` |

---

## 1. 登录

- **方法**：`POST /api/auth/login`
- **对应前端页面**：`features/auth/login_page.dart`
- **对应 Repository**：`AuthRepository.loadCurrentUser` / `AuthApi.login`

请求：

```json
{
  "phone": "13812345678",
  "code": "1234",
  "role": "employee"
}
```

返回 `data`：

```json
{
  "user": {
    "id": "u_emp_1",
    "name": "张三",
    "phone": "138 1234 5678",
    "role": "employee"
  },
  "token": "<jwt>"
}
```

---

## 2. 获取当前登录用户（自动登录用）

- **方法**：`GET /api/auth/me`
- **对应前端页面**：启动引导 `_AppBootstrap`
- **对应 Repository**：`AuthRepository.loadCurrentUser`

返回 `data`：

```json
{
  "user": { "id": "...", "name": "...", "phone": "...", "role": "employee" }
}
```

---

## 3. 登出

- **方法**：`POST /api/auth/logout`
- **对应前端页面**：员工/商家"我的"页 → 设置 → 退出
- **对应 Repository**：`AuthRepository.clearCurrentUser`

请求：空
返回：空

---

## 4. 获取附近商家列表

- **方法**：`GET /api/merchants`
- **对应前端页面**：员工端首页 `EmployeeHomePage` 左侧"附近商家"
- **对应 Repository**：`MerchantRepository.fetchNearbyMerchants`
- **查询参数**：

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `area` | string | 否 | 区域，如"科技园A区" |
| `lat`/`lng` | number | 否 | 经纬度，按距离排序 |

返回 `data`：

```json
{
  "merchants": [
    {
      "id": "m_1",
      "name": "绿禾餐饮",
      "logo": "https://.../logo.png",
      "coverImage": "https://.../cover.jpg",
      "distance": 120,
      "rating": 4.8,
      "monthSold": 1288,
      "hygieneGrade": "A",
      "isOpen": true,
      "address": "科技园 A 区 1 栋",
      "paymentQrCode": "https://.../qr.png",
      "deliveryFee": 3.0
    }
  ]
}
```

---

## 5. 获取商家菜品（员工端）

- **方法**：`GET /api/merchants/:merchantId/dishes`
- **对应前端页面**：员工端首页右侧菜品列表
- **对应 Repository**：暂无（员工端目前直接读 `MockData`；接入后请补一个
  `DishRepository.fetchByMerchant` 与 `DishApi.getMerchantDishes`）

查询参数（可选）：

| 参数 | 类型 | 说明 |
|---|---|---|
| `mealType` | string | 餐段筛选，见枚举 |

返回 `data`：

```json
{
  "dishes": [
    {
      "id": "d_1_1",
      "merchantId": "m_1",
      "name": "香煎鸡胸肉饭",
      "image": "https://.../img.jpg",
      "description": "低脂高蛋白",
      "price": 16.8,
      "mealType": "lunch",
      "tags": ["健康", "推荐"],
      "isAvailable": true
    }
  ]
}
```

---

## 6. 获取商家自己的菜品（商家端）

- **方法**：`GET /api/merchant/dishes`（或复用 `/merchants/:merchantId/dishes`）
- **对应前端页面**：`MerchantDishManagePage`
- **对应 Repository**：`DishRepository.loadDishes` → `DishApi.getMerchantDishes`

返回结构同 §5。

---

## 7. 创建订单（员工提交订单）

- **方法**：`POST /api/orders`
- **对应前端页面**：`EmployeePaymentUploadPage._onSubmit`
- **对应 Repository**：`OrderRepository.createOrder` → `OrderApi.createOrder`

请求体：完整 `Order` 字段（与 `Order.toJson()` 一致）

```json
{
  "id": "Oxxxxx",
  "merchantId": "m_1",
  "merchantName": "绿禾餐饮",
  "customerName": "张三",
  "customerCompany": "科技园A区 行政部",
  "items": [
    { "dish": { ... Dish.toJson ... }, "quantity": 2 }
  ],
  "deliveryType": "delivery",
  "address": "综合楼A座 5层 行政部",
  "phone": "138 0000 0000",
  "remark": "少油",
  "goodsAmount": 22,
  "deliveryFee": 3,
  "totalAmount": 25,
  "status": "pendingMerchantConfirm",
  "paymentScreenshot": "https://.../shot.jpg",
  "createdAt": "2026-06-12T02:35:00.000Z"
}
```

返回 `data`：

```json
{ "order": { ...完整 Order... } }
```

> 后端可以自行覆盖 `id`、`createdAt`、`status` 等服务端权威字段。

---

## 8. 获取员工的订单列表

- **方法**：`GET /api/orders/my`
- **对应前端页面**：`EmployeeOrdersPage`
- **对应 Repository**：`OrderRepository.loadOrders`(`forMerchant=false`)
  → `OrderApi.getOrders(forMerchant: false)`

查询参数（可选）：

| 参数 | 类型 | 说明 |
|---|---|---|
| `status` | string | 见订单状态枚举 |
| `page`/`size` | int | 分页 |

返回 `data`：

```json
{ "orders": [ { ...Order... } ] }
```

---

## 9. 获取商家的订单列表

- **方法**：`GET /api/merchant/orders`
- **对应前端页面**：`MerchantDashboardPage`、`MerchantOrderProcessPage`
- **对应 Repository**：`OrderRepository.loadOrders`(`forMerchant=true`)
  → `OrderApi.getOrders(forMerchant: true)`

参数与返回同 §8。

---

## 10. 商家更新订单状态

- **方法**：`PUT /api/orders/:orderId/status`
- **对应前端页面**：`MerchantOrderProcessPage._ActionRow`（确认收款 / 开始配送 / 完成 / 拒绝）
- **对应 Repository**：`OrderRepository.updateOrderStatus`
  → `OrderApi.updateOrderStatus`

请求体：

```json
{ "status": "accepted" }
```

返回 `data`：

```json
{ "order": { ...更新后的 Order... } }
```

---

## 11. 上传付款截图

- **方法**：`POST /api/uploads/payment-screenshot`
- **对应前端页面**：`EmployeePaymentUploadPage`
- **对应 Repository**：`MerchantRepository.uploadPaymentScreenshot`
  → `OrderApi.uploadPaymentScreenshot`

请求：`multipart/form-data`

| 字段 | 类型 | 说明 |
|---|---|---|
| `file` | file | 截图文件 |
| `orderId` | string | 关联订单号 |

返回 `data`：

```json
{ "url": "https://oss/path/to/screenshot.jpg" }
```

---

## 12. 上传菜品图片

- **方法**：`POST /api/uploads/dish-image`
- **对应前端页面**：`DishEditorSheet`（新增/编辑菜品弹窗的图片占位区）
- **对应 Repository**：`DishRepository.uploadDishImage`
  → `DishApi.uploadDishImage`

请求：`multipart/form-data`

| 字段 | 类型 | 说明 |
|---|---|---|
| `file` | file | 图片文件 |

返回 `data`：

```json
{ "url": "https://oss/path/to/dish.jpg" }
```

---

## 13. 上传商家收款码

- **方法**：`POST /api/uploads/merchant-qr-code`
- **对应前端页面**：`MerchantProfilePage` 收款码弹窗"更换收款码"
- **对应 Repository**：`MerchantRepository.uploadMerchantQrCode`
  → `MerchantApi.uploadMerchantQrCode` + `MerchantApi.updatePaymentQrCode`

请求：`multipart/form-data`

| 字段 | 类型 | 说明 |
|---|---|---|
| `file` | file | 二维码图片 |

返回 `data`：

```json
{ "url": "https://oss/path/to/qr.png" }
```

---

## 14. 更新商家收款码字段

- **方法**：`PUT /api/merchant/payment-qr-code`
- **对应前端页面**：`MerchantProfilePage`（上一接口之后调用，把 URL 写回）
- **对应 Repository**：`MerchantRepository.uploadMerchantQrCode` 内部
  → `MerchantApi.updatePaymentQrCode`

请求体：

```json
{ "paymentQrCode": "https://oss/path/to/qr.png" }
```

返回 `data`：空或最新 Merchant 对象。

---

## 15. 新增菜品

- **方法**：`POST /api/dishes`
- **对应前端页面**：`DishEditorSheet`（新增）
- **对应 Repository**：`DishRepository.createDish` → `DishApi.createDish`

请求体：`Dish.toJson()`

```json
{
  "id": "本地生成的临时 id（后端可覆盖）",
  "merchantId": "m_self",
  "name": "小米粥",
  "image": "https://.../img.jpg",
  "description": "清淡养胃",
  "price": 4.0,
  "mealType": "breakfast",
  "tags": ["健康"],
  "isAvailable": true
}
```

返回 `data`：

```json
{ "dish": { ...最终 Dish... } }
```

---

## 16. 编辑菜品

- **方法**：`PUT /api/dishes/:dishId`
- **对应前端页面**：`DishEditorSheet`（编辑）
- **对应 Repository**：`DishRepository.updateDish` → `DishApi.updateDish`

请求体：`Dish.toJson()`（完整菜品对象）

返回 `data`：

```json
{ "dish": { ...更新后 Dish... } }
```

---

## 17. 上架 / 下架菜品

- **方法**：`PUT /api/dishes/:dishId/available`
- **对应前端页面**：`MerchantDishManagePage`（菜品开关 / 下架按钮）
- **对应 Repository**：`DishRepository.toggleDishAvailable`
  → `DishApi.toggleDishAvailable`

请求体：

```json
{ "isAvailable": false }
```

返回 `data`：空或最新 Dish 对象。

---

## 18. 获取商家自己的资料

- **方法**：`GET /api/merchant/profile`
- **对应前端页面**：`MerchantDashboardPage`、`MerchantProfilePage`
- **对应 Repository**：`MerchantRepository.currentMerchant`
  → `MerchantApi.getMerchantProfile`

返回 `data`：

```json
{ "merchant": { ...Merchant... } }
```

---

## 19. 更新商家资料

- **方法**：`PUT /api/merchant/profile`
- **对应前端页面**：`MerchantProfilePage`（店铺信息 / 配送设置 / 营业时间 等扩展功能）
- **对应 Repository**：暂无（接入时新增 `MerchantRepository.updateProfile`）
  → `MerchantApi.updateMerchantProfile`

请求体：完整 `Merchant` 对象

返回 `data`：

```json
{ "merchant": { ...更新后 Merchant... } }
```

---

## 切换 local / API 模式

只需修改：

```dart
// lib/api/api_config.dart
class AppConfig {
  static const DataSourceMode dataSourceMode = DataSourceMode.api; // 改这里
}
```

所有 Repository 已经内部判断模式并自动选择：

- `DataSourceMode.local` → 用 `SharedPreferences`（默认）
- `DataSourceMode.api` → 走 `ApiClient` 请求（接入真实后端时启用）

> 当 API 模式启用但后端不可用时，Repository 会自动降级到本地缓存，
> 保证 App 仍可继续运行。

---

## 接入真实后端的步骤

1. `pubspec.yaml` 增加 `http` 或 `dio` 依赖
2. 在 `lib/api/api_client.dart` 中把 `_send` 改为真实 HTTP 请求
   （示例代码已写在 `_send` 注释里）
3. 把 `lib/api/api_config.dart` 中 `apiBaseUrl` 改为生产地址
4. 把 `AppConfig.dataSourceMode` 改为 `DataSourceMode.api`
5. 后端按本文档实现 19 个接口
6. 完成 ✅
