# 非攻云餐 APK 下载目录

将 release APK 放到此目录：

```
pheako-yuncan.apk
```

公网下载地址：

```
http://118.31.188.176/downloads/pheako-yuncan.apk
```

构建命令（在项目根目录，需 Flutter Android SDK）：

```bash
flutter build apk --release \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=http://118.31.188.176/yuncan-api

cp build/app/outputs/flutter-apk/app-release.apk downloads/pheako-yuncan.apk
```

部署脚本会自动复制到 `/opt/feigong-yuncan/downloads/`。

若暂未构建 APK，Web 上线不受影响；本目录可保留此说明文件。
