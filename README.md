<p align="center">
  <img src="assets/images/tubiao.png" width="120" alt="播放一烨图标">
</p>

<h1 align="center">播放一烨</h1>

<p align="center">一个用 Flutter 写的安卓影视搜索播放器，基于苹果 CMS（MacCMS）采集接口，多源聚合搜索、在线播放、DLNA 投屏。</p>

---

## 功能

- **多源聚合搜索**：内置的 24 个数据源全部启用、同时搜索，先返回的先显示；同名影片自动合并，一部剧只显示一条。搜索框右侧 ❌ 一键清空剧名和结果
- **多源切换**：详情页可在不同数据源之间切换，某个源失效时换一个继续看
- **线路 / 选集**：支持多线路切换，自动优先显示可直接播放的 m3u8 线路
- **播放器**
  - 单击显示 / 隐藏控制栏，**双击暂停 / 播放**，**左右滑动快进快退**（滑满一屏 90 秒，滑动时显示目标时间）
  - 底栏：投屏、倍速、**清晰度**、全屏；全屏时左上角有 **「<」返回键**
  - 上一集 / 下一集、选集网格、播完自动播放下一集
- **清晰度切换**：自动解析 m3u8 主播放列表里的各档清晰度（1080P / 720P …），可手动切换，从当前进度接着播。多数源只提供一档，此时按钮显示当前清晰度
- **观看记录**：自动保存看到第几集、几分几秒；再次进入详情页自动选中上次的源和线路，一键「继续播放」，看完了则「看下一集」
- **历史页**：底部导航「首页 / 历史」，历史页点一下直接接着看，右侧按钮进详情页，左滑删除，可一键清空
- **DLNA 投屏**：搜索同一 WiFi 下的电视 / 盒子，从手机当前进度开始投；投屏期间可暂停 / 继续、换集、退出投屏
  - 默认通过**手机中转**：电视向手机请求视频，手机带上 App 的证书和 UA 去源站拉取后转给电视，解决电视直连源站报错（如 `-1004`）的问题；也可以在遥控面板切换成电视直连
- **证书兼容**：内置 Let's Encrypt 新根证书 ISRG Root YE，避免旧手机出现 `CERTIFICATE_VERIFY_FAILED`

## 使用说明

1. 安装 APK 后打开，输入剧名点搜索
2. 搜索结果点进去，选择播放源 → 线路 → 集数即可播放
3. 投屏：播放页右上角或控制栏里的投屏图标 → 选择设备。手机和电视需要连同一个 WiFi，电视需开启投屏（DLNA）功能。投屏期间视频经过手机中转，App 不要被关掉
4. 看过的影视在底部 **「历史」** 里，点一下就能接着看

## 更新记录

### v1.2.0

- 标题改为「播放一烨」，首页提示精简为「输入剧名点搜索」
- 去掉首页右上角的数据源入口，内置源全部启用；搜索框加 ❌ 清空按钮
- 播放器控制层重写：滑动快进快退、双击暂停播放、去掉中间的 ±10 秒按钮
- 新增清晰度切换按钮（全屏按钮左侧）
- 新增全屏左上角返回键
- 新增 DLNA 投屏（含手机中转模式）
- 新增观看记录与续播
- 新增底部导航和历史页

## 项目结构

```
lib/
├── main.dart              # 入口，全局网络证书配置
├── net.dart               # User-Agent、内置根证书、HttpOverrides
├── models.dart            # 数据模型（数据源、影片、线路、剧集）及播放列表解析
├── maccms_api.dart        # 苹果 CMS 接口请求：搜索、详情、测试
├── source_store.dart      # 内置数据源列表 kDefaultSources
├── hls.dart               # 解析 m3u8 主播放列表里的清晰度
├── history_store.dart     # 观看记录本地存储、续播位置计算
├── dlna.dart              # DLNA：SSDP 搜索设备、AVTransport 控制命令
├── cast_proxy.dart        # 投屏中转：本机 HTTP 服务，改写 m3u8 并转发视频
└── pages/
    ├── home_shell.dart      # 底部导航（首页 / 历史）
    ├── search_page.dart     # 搜索页（多源并发、结果合并）
    ├── history_page.dart    # 观看历史页
    ├── detail_page.dart     # 详情页（源 / 线路 / 选集 / 继续播放）
    ├── player_page.dart     # 播放页（清晰度切换、投屏、保存进度）
    ├── player_controls.dart # 播放控制层（手势、底栏按钮、全屏返回键）
    ├── cast_sheet.dart      # 投屏设备选择面板
    ├── sources_page.dart    # 数据源管理页（目前界面上没有入口）
    └── widgets.dart         # 公共组件（海报、选集网格、线路切换）
android/app/src/main/kotlin/.../MainActivity.kt  # 搜索投屏设备时申请 WiFi 组播锁
test/                      # 单元测试（播放列表、清晰度、续播逻辑）
assets/images/             # 图片资源（App 图标等）
```

## 开发与构建

### 环境

- Flutter 3.41+（Dart SDK ^3.11.5）
- Android Studio（含 Android SDK）

### 运行

```bash
flutter pub get
flutter run            # 连接模拟器或开启 USB 调试的手机
flutter test           # 运行单元测试
```

开发时修改 Dart 代码保存即可热重载；修改 `AndroidManifest.xml`、`MainActivity.kt`、新增依赖、更换图标后需要停止并重新运行。

### 打包 APK

```bash
flutter build apk --release
```

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

> 如果打包时报 `Gradle build daemon disappeared unexpectedly`，并在 `android/` 下生成 `hs_err_pid*.log` 提示内存不足，说明电脑空闲内存不够 `android/gradle.properties` 里配置的 8G 堆，把 `-Xmx8G` 调小（如 `-Xmx2G`）即可。

### 更换 App 图标

替换 `assets/images/tubiao.png`（建议 1024×1024 以上的 PNG），然后执行：

```bash
dart run flutter_launcher_icons
```

### 修改数据源

编辑 `lib/source_store.dart` 中的 `kDefaultSources`，重新打包即可。搜索直接使用这个列表，不再读取手机上保存的数据源设置。

## 依赖

| 包 | 用途 |
|---|---|
| [http](https://pub.dev/packages/http) | 网络请求 |
| [html](https://pub.dev/packages/html) | 清理简介中的 HTML 标签 |
| [video_player](https://pub.dev/packages/video_player) | 视频播放 |
| [chewie](https://pub.dev/packages/chewie) | 播放器（控制层为自己实现） |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 本地保存观看记录 |
| [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) | 生成 App 图标（开发依赖） |

DLNA 投屏和投屏中转没有使用第三方包，基于 `dart:io` 自行实现。

## 常见问题

**能搜到但播放失败**
资源站的线路经常失效，在详情页换一个播放源或线路再试。标注「不是直链」的线路需要网页解析，本播放器无法直接播放。部分源默认测试时就不支持搜索或返回 403，会显示在「X 个源失败」里，不影响其他源。

**清晰度只有一个选项**
大部分源只提供一档清晰度，想要别的清晰度可以在详情页换个源。

**搜不到投屏设备**
确认手机和电视在同一个 WiFi、电视已打开投屏 / DLNA 功能；可以试试关掉手机的移动数据。搜不到时面板上会显示搜索记录（本机网卡、收到的回应数），便于排查。

**电视上提示播放失败**
默认的手机中转模式下，投屏期间 App 不要被关掉；也可以在遥控面板切换「直连 / 中转」再试，或换一个源。投屏时从手机进度开始播依赖电视支持跳转，少数电视会从头播。

**数据源全部失效**
资源站地址变动频繁，可自行搜索「苹果 CMS 采集接口」获取新的地址，修改 `kDefaultSources` 后重新打包。

## 免责声明

- 本项目仅供个人学习 Flutter 开发与交流使用，**不得用于任何商业用途**。
- 本项目本身**不存储、不提供、不上传任何影视资源**，所有内容均来自第三方接口，与本项目无关。
- 请遵守所在地区的法律法规，支持正版影视内容。如有侵权，请联系删除。
