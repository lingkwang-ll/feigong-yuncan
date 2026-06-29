# 非攻云餐 UI 锁定规则

> 本文件定义"非攻云餐"前端 UI 的锁定基线。后续任何 UI 变更必须先阅读本文件,并遵守其中的禁止 / 允许清单。
>
> 适用范围:Flutter 前端(`lib/` 目录),不涉及后端 API / 数据模型。

---

## 1. UI 参考图路径

所有 UI 还原以下目录的 10 张图为唯一基准:

```
design_reference/feigong_yuncan_ui/
```

任何"我觉得这样更好看"的改动都必须先在 PR / 任务说明里贴出参考图与现状对比,经过确认后再动手。

---

## 2. 核心页面 ↔ 参考图对应关系

| 参考图                                   | Flutter 页面                          | 文件位置                                                   |
| ---------------------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| `01_login.png`                           | `LoginPage`                           | `lib/features/auth/login_page.dart`                        |
| `02_employee_home.png`                   | `EmployeeHomePage`                    | `lib/features/employee/employee_home_page.dart`            |
| `03_employee_confirm_order.png`          | `EmployeeConfirmOrderPage`            | `lib/features/employee/employee_confirm_order_page.dart`   |
| `04_employee_payment_upload.png`         | `EmployeePaymentUploadPage`           | `lib/features/employee/employee_payment_upload_page.dart`  |
| `05_employee_orders.png`                 | `EmployeeOrdersPage`                  | `lib/features/employee/employee_orders_page.dart`          |
| `06_employee_profile.png`                | `EmployeeProfilePage`                 | `lib/features/employee/employee_profile_page.dart`         |
| `07_merchant_dashboard.png`              | `MerchantDashboardPage`               | `lib/features/merchant/merchant_dashboard_page.dart`       |
| `08_merchant_order_process.png`          | `MerchantOrderProcessPage`            | `lib/features/merchant/merchant_order_process_page.dart`   |
| `09_merchant_dish_manage.png`            | `MerchantDishManagePage`              | `lib/features/merchant/merchant_dish_manage_page.dart`     |
| `10_merchant_profile_payment_code.png`   | `MerchantProfilePage`                 | `lib/features/merchant/merchant_profile_page.dart`         |

> 当前"严格还原"已完成的页面:`LoginPage` / `EmployeeHomePage`。
> 其余 8 个页面已按参考图初稿对齐,但**不属于"像素级锁定"**,后续仍可继续精修——
> 任何精修都必须遵守下面的"禁止 / 允许"清单。

---

## 3. 禁止事项(硬性约束)

以下事项**任何情况下都不允许做**,违者必须 revert:

1. **禁止使用 emoji 作为菜品图、头像、装饰、店铺图**
   - 不允许 `🌿 🥗 👨‍💼 🏪 🍚 🍗 🥗 🍜 🍲` 等任何 Unicode emoji 出现在 UI 中
   - 占位资源缺失时使用 Flutter `CustomPainter` 矢量绘制或纯色 + 几何形状
   - 真实菜品图必须放在 `assets/images/dishes/` 下,并在 `pubspec.yaml` 注册

2. **禁止修改 P+ Logo**
   - `lib/widgets/app_logo.dart` 中的 `AppLogo` 组件视觉锁定:
     - 绿色圆角方形底 + 中央白色 `p` + 右上橙色 `+` 圆点 + 底部一抹橙色饭碗
   - 任何颜色 / 形状 / 比例调整都要先经过确认
   - 不允许更换 logo 字体、不允许换图

3. **禁止改主色、橙色按钮、米白背景**
   - 主色板见第 5 节,任何 `Color(0x...)` 字面量都必须等于其中之一
   - 主操作按钮永远是橙色 `#FF7A00`,绝不能改成绿色 / 蓝色 / 灰色
   - 全局背景 `AppColors.background = #FAF7EF`,不允许换成纯白或纯灰

4. **禁止把移动端页面改成网页后台风格**
   - 所有页面在 Web 上仍然是手机外壳(`MobileAppFrame`,最大宽度 420px)
   - 不允许出现宽桌面排版、表格式 dashboard、左侧导航树
   - 不允许把 Tab 改成顶栏 nav menu、把"我的订单"改成长长的 data table

5. **禁止调整页面结构比例**
   - 登录页:Hero 装饰 + Logo + 标题 + 输入框 × 2 + 登录按钮 + 双身份卡 + 协议
   - 员工首页:Header + 搜索 + 餐段切换 + 双栏(左 126 商家 + 右白卡菜品)+ 底部悬浮购物车
   - 不允许把双栏改单栏、把搜索框移到 Header 内、把购物车改成贴底固定栏

6. **禁止在没有确认的情况下重构 UI 组件**
   - `AppLogo` / `MerchantBadgeLogo` / `DishImagePlaceholder` / `DishAssetImage` /
     `FloatingCartBar` / `MealTypeTabs` / `MerchantCard` / `LoginHeroBackground` /
     `EmployeeIllustration` / `MerchantIllustration` —— 不允许擅自删除、改名或拆分
   - 如需重构,请在任务说明中列出要改的 widget 与原因,等确认后再动手

---

## 4. 允许改动项(无需特别确认)

下面这些**属于日常优化**,可以直接做,只要不违反第 3 节:

1. **替换更真实的菜品图片**
   - 把 `assets/images/dishes/*.png` 替换成质量更好的写实摄影
   - 文件名保持不变,否则要同步改 `DishAsset._exactMap` / `_keywordMap`

2. **微调像素级间距**
   - 调整 `EdgeInsets` / `SizedBox` 高度 / `borderRadius` ±2~4
   - 调整字号 ±1~2(不允许大幅改变层级关系)

3. **修复溢出、换行、真机适配问题**
   - 处理 `RenderFlex overflowed`
   - 处理小屏(< 375)/ 大屏(> 430)的截断与挤压
   - 为长商家名 / 长菜品名补 `maxLines` + `ellipsis`

4. **补充真实商家图片**
   - 当后端返回真实 `merchant.logoUrl` 时,优先展示网络图
   - 网络图加载失败回到统一的 `AppLogo`

5. **优化加载失败占位**
   - `Image.network` / `Image.asset` 的 `errorBuilder` 用空白瓷盘占位
   - 不允许在 `errorBuilder` 里加 emoji

---

## 5. 品牌色板(硬锁定)

所有色值必须使用 `lib/theme/app_theme.dart` 中的 `AppColors` 常量,不允许就地写 `Color(0x...)`(矢量插画局部色除外):

| 名称           | Hex        | Dart 常量                       | 用途                                   |
| -------------- | ---------- | ------------------------------- | -------------------------------------- |
| 健康绿         | `#16A34A`  | `AppColors.primary`             | 主操作 / 选中态 / 重要标识 / Logo 主体 |
| 深绿           | `#0F7A4B`  | `AppColors.primaryDark`         | 大标题 / Logo 渐变深端                  |
| 浅绿背景       | `#EAF8F1`  | `AppColors.primaryLight`        | 标签胶囊 / 选中态浅底                  |
| 实惠橙         | `#FF7A00`  | `AppColors.accent`              | 价格 / 登录按钮 / 去结算 / 角标         |
| 浅橙背景       | `#FFF1E2`  | `AppColors.accentLight`         | 橙色组件浅底                            |
| 米白背景       | `#FAF7EF`  | `AppColors.background`          | 全局 scaffold 背景                      |
| 卡片白         | `#FFFFFF`  | `AppColors.surface`             | 卡片 / 输入框 / 悬浮栏                  |
| 主文字         | `#1F2937`  | `AppColors.textPrimary`         | 标题 / 菜名 / 重要信息                  |
| 次文字         | `#6B7280`  | `AppColors.textSecondary`       | 副信息 / 描述                            |
| 三级文字       | `#9CA3AF`  | `AppColors.textTertiary`        | placeholder / 占位                       |
| 分割线         | `#E5E7EB`  | `AppColors.divider`             | 卡片内、列表项之间的分隔                |
| 状态蓝         | `#3B82F6`  | `AppColors.statusBlue`          | 状态标签(信息)                         |
| 状态黄         | `#F59E0B`  | `AppColors.statusYellow`        | 评分星星 / 状态标签(待处理)            |

> 矢量插画(`LoginHeroBackground` / `EmployeeIllustration` / `MerchantIllustration`)
> 内允许使用本地常量描述肤色 / 衣服色 / 食材色,但仍要遵循"绿主橙副"的整体调性。

---

## 6. UI 资源目录

| 路径                                     | 内容                                                   |
| ---------------------------------------- | ------------------------------------------------------ |
| `assets/images/dishes/`                  | 本地菜品摄影 PNG;新增/替换时不要改文件名,否则同步更新 `lib/widgets/dish_asset_image.dart` |
| `design_reference/feigong_yuncan_ui/`    | 10 张参考图,**只读**,不允许覆盖或删除                |
| `lib/widgets/login_hero_background.dart` | 登录页顶部矢量装饰(叶子 + 远山 + 瓷碗)              |
| `lib/widgets/role_card_illustration.dart`| 登录页身份卡矢量插画(员工 / 商家)                  |
| `lib/widgets/app_logo.dart`              | `AppLogo` + `AppLogoTitle` + `MerchantBadgeLogo` + `ThemeSlogan` |
| `lib/widgets/dish_asset_image.dart`      | 菜品名 → 本地 PNG 映射 + 多级 fallback                  |
| `lib/widgets/dish_card.dart`             | 员工首页菜品行                                          |
| `lib/widgets/merchant_card.dart`         | 员工首页左侧商家卡                                      |
| `lib/widgets/meal_type_tabs.dart`        | 早餐 / 中餐 / 晚餐 / 加班餐 切换                         |
| `lib/widgets/cart_bar.dart`              | `FloatingCartBar` 悬浮购物车                            |
| `lib/widgets/mobile_app_frame.dart`      | Web / 桌面下的"手机外壳"                              |
| `lib/widgets/qr_placeholder.dart`        | 收款码 / 上传截图 占位 + 网络图                          |
| `lib/theme/app_theme.dart`               | 主题、颜色、圆角、间距常量                              |

---

## 7. 修改 UI 的标准流程

1. 在 `design_reference/feigong_yuncan_ui/` 找到对应参考图
2. 通读本文件第 3、4、5 节
3. 在 issue / 任务说明里贴出:
   - 参考图区域截图
   - 当前实现截图
   - 计划改动点
4. 实施后跑:
   ```powershell
   flutter analyze
   flutter build web --dart-define=API_BASE_URL=http://localhost:3000/api
   ```
5. 在浏览器(移动视口 430×920)实拍登录页 / 受影响页,与参考图同框对比
6. 任何禁止项触发都要 revert,并把违规点写进任务总结

---

## 8. 速查清单(改 UI 前 30 秒过一遍)

- [ ] 我看了对应的参考图吗?
- [ ] 我要改的部分在第 3 节"禁止事项"里吗?
- [ ] 我用的色值都来自 `AppColors` 吗?
- [ ] 我有没有引入 emoji?
- [ ] 我有没有改 `AppLogo` / `FloatingCartBar` / `MealTypeTabs` 等已锁定组件?
- [ ] 我会在改完后跑 `flutter analyze` 和 `flutter build web` 吗?

任何一条答案不是"是 / 否(且符合规则)",停下找人确认。
