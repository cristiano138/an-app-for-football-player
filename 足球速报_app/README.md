# 足球速报 App（Android）

深色卡片式足球每日速报应用，由现有 PWA 网页版改造而来的 Flutter 原生 App。
数据由 WorkBuddy 定时任务（每天 07:10）自动生成并发布，App 启动自动拉取最新一期，**日常零维护**。

- 包名：`com.zqsb.football`
- 版本：1.0.1（versionCode 2）
- 技术栈：Flutter 3.47（Dart 3.13），纯原生渲染（非 WebView 套壳）

## 安装方式

1. 把 apk 传到安卓手机（微信/QQ/数据线均可）。
2. 在手机上点击 APK 安装。系统若提示「未知来源应用」，允许即可。
3. 要求 Android 7.0（API 24）及以上。

## 数据更新方式（自动）

- 数据链路：每天 07:10 定时任务自动抓取赛事素材 → 生成 md → 合并进 `report-data.js` → 发布到线上。
- App 每次启动都会异步拉取远端最新数据；成功则刷新并写入本地缓存。
- 三层降级：**远端数据 → 本地缓存 → 内置数据**，任何情况下打开都有内容，绝不空白。
- 断网时顶部会有黄色「离线模式」轻提示，浏览的是上次更新内容。
- 唯一限制：07:10 那一刻电脑需开着且 WorkBuddy 在运行（既有机制）。

## 功能

- 速报列表（按日期倒序）+ 当日详情页；最新一期带「最新」徽标、按下水波纹反馈
- 详情页顶部板块标签（⚽速报/📋比分/🔔动态/📅前瞻/🔗来源）点击平滑跳转到对应板块（1.0.1 修复了点击无反应的问题）
- 阅读进度条、一键复制速报要点（详情页右上角）、首页回顶部按钮
- 字体大小调节（设置 → 显示：小/标准/大，全局生效）
- 历史速报切换（列表直达，详情页底部 ‹ › 翻前一天/后一天）
- 板块与网页版一致；空板块自动隐藏
- 每日本地推送通知（默认 08:00，可在设置中修改时间或关闭）
- **App 内检查更新**（设置 → 关于 → 检查 App 更新）：从站点拉取 `update.json`，发现新版（versionCode 更大）后弹窗确认 → 显示下载进度 → 调起系统安装；未授权「安装未知应用」时会先引导授权
- 设置页支持：立即同步数据（拉取最新速报数据）、手动导入 data.js、推送开关/时间

## 发布新版本（流程概要）

> 详细步骤见交付说明。核心三件事：
> 1. `pubspec.yaml` 的 `version` 升一级（如 `1.0.2+3`，**+号后必须递增**）
> 2. `flutter build apk --release` 编译，产物改名 `football-v<版本>.apk` 放入站点目录 `..\足球速报\`
> 3. 修改站点目录 `update.json`（version/versionCode/apkUrl/notes 与新版一致）并发布站点

> 签名密钥：`C:\Users\ThinkPad\.android\debug.keystore`。**请务必备份此文件**（网盘/U 盘）。
> 丢失后打出的包与已分发版本签名不一致，所有用户将无法覆盖安装。

## 重新编译

本工具链（`..\_toolchain\`）在 1.0.1 交付后已按要求清理。下次需要重新编译时需重新安装
Flutter SDK + JDK 17 + Android SDK（过程约 20-40 分钟，可再次交给 AI 自动完成）。
编译命令（工具链就绪后）：

```powershell
. "<工具链目录>\env.ps1"
cd "E:\workbuddy\定时球报\足球速报_app"
flutter build apk --release    # 产物在 build\app\outputs\flutter-apk\app-release.apk
```

> 注意：引擎依赖仓库 `download.flutter.io` 在国内多数镜像缺失。若构建报
> `io.flutter:flutter_embedding_release` 找不到，需把 4 个引擎 jar
> （flutter_embedding_release / arm64_v8a_release / armeabi_v7a_release / x86_64_release，
> 版本号 `1.0.0-<engine.stamp>`）下载到 `X:\maven-local\` 本地 maven 仓库
> （`subst X: <工具链目录>` 后按 `io\flutter\<构件>\...` 目录摆放）。
> `android\build.gradle.kts` 的 allprojects 已配置优先使用该本地仓库。

## 换图标方法

1. 用新的正方形 PNG（建议 1024×1024）覆盖 `assets\icon\icon-512.png`。
2. 在项目目录执行（需工具链就绪）：

```powershell
dart run flutter_launcher_icons
flutter build apk --release
```

## 目录结构

```
足球速报_app\
├─ lib\
│  ├─ main.dart                       入口（全局字号应用）
│  ├─ models\report.dart              数据模型（与网页版 schema 一致）
│  ├─ data\                           内置数据/远端拉取/缓存/JS 剥壳解析/仓库（勿改）
│  ├─ services\
│  │  ├─ app_update_service.dart      App 更新：检查/比较/下载（含可单测纯函数）
│  │  ├─ notify_service.dart          每日推送
│  │  └─ settings_store.dart          设置存储（推送/字号）
│  ├─ theme\app_theme.dart            配色（#0D100F 深色主题，与网页版对应）
│  └─ ui\
│     ├─ pages\                       列表页/详情页/设置页
│     └─ widgets\                     按板块拆分的组件 + 通用组件
├─ android\app\src\main\
│  ├─ AndroidManifest.xml             权限 + FileProvider（update.provider）
│  ├─ res\xml\file_paths.xml          FileProvider 路径授权
│  └─ kotlin\com\zqsb\football\
│     ├─ MainActivity.kt              注册更新通道
│     └─ UpdateInstaller.kt           版本号读取/安装授权/调起安装（MethodChannel）
├─ test\app_update_test.dart          版本比较与 update.json 解析单测
├─ assets\data\report-data.js         内置兜底数据
├─ assets\icon\icon-512.png           App 图标源图
└─ dist\                              安装包输出
```
