# Android 正式版打包说明

## 应用信息

| 项 | 值 |
|----|-----|
| 包名 | `com.feigong.yuncan` |
| 应用名称 | 非攻云餐 |
| 图标 | P+ Logo（`assets/images/ui/app_logo_large.png`） |

## 1. 生成 Release Keystore

在 **android/** 目录下执行（仅需一次）：

```bash
keytool -genkeypair -v \
  -keystore app/feigong-yuncan-release.jks \
  -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias feigong-yuncan
```

按提示设置 store 密码与 key 密码，并填写组织信息。

> `*.jks` 与 `key.properties` 已在 `.gitignore` 中，**切勿提交到 Git**。

## 2. 配置 key.properties

```bash
cd android
cp key.properties.example key.properties
```

编辑 `key.properties`（密码仅保存在本地，不要写入 README）：

```properties
storePassword=你的store密码
keyPassword=你的key密码
keyAlias=feigong-yuncan
storeFile=feigong-yuncan-release.jks
```

`storeFile` 路径相对于 `android/app/` 目录。

## 3. 生成启动图标（首次或 Logo 变更后）

```bash
flutter pub get
dart run flutter_launcher_icons
```

## 4. 打包 Release APK

```bash
# 生产 API 地址按实际域名修改
flutter build apk --release \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=https://your-domain.com/api
```

若未配置 `key.properties`，Release 会临时使用 debug 签名（仅本地测试，不可上架）。

## 5. APK 输出路径

```
build/app/outputs/flutter-apk/app-release.apk
```

## 6. 验证

```bash
flutter analyze
flutter build apk --release --dart-define=ENV=prod
```

## 7. 真机安装

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 8. Android 模拟器 API 地址

模拟器访问本机后端请使用：

```
--dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```
