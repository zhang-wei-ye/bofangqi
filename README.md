<p align="center">
  <img src="assets/images/tubiao.png" width="120" alt="播放一烨图标">
</p>

<h1 align="center">播放一烨</h1>

<p align="center">一个用 Flutter 写的安卓影视搜索播放器，基于苹果 CMS（MacCMS）采集接口，多源聚合搜索、在线播放。</p>

---

## 功能

- **多源聚合搜索**：所有开启的数据源同时搜索，先返回的先显示；同名影片自动合并，一部剧只显示一条
- **多源切换**：详情页可在不同数据源之间切换，某个源失效时换一个继续看
- **线路 / 选集**：支持多线路切换，自动优先显示可直接播放的 m3u8 线路
- **播放器**：上一集 / 下一集、选集网格、播完自动播放下一集、全屏播放
- **数据源管理**：在 App 内添加、编辑、删除、开关、拖动排序、批量导入、一键测试可用性，数据保存在本机
- **内置默认源**：首次安装自动加载一批可用的数据源，可随时「恢复默认」
- **证书兼容**：内置 Let's Encrypt 新根证书 ISRG Root YE，避免旧手机出现 `CERTIFICATE_VERIFY_FAILED`

## 使用说明

1. 安装 APK 后打开即可搜索（首次启动已自动加载默认数据源）
2. 点首页右上角 **「数据源」** 进入数据源管理：
   - 右下角 **+**：添加单个接口
   - **批量导入**：每行一个，格式为 `名称,接口地址`，或只写接口地址
   - **全部测试**：检查每个源是否可用、片库数量
   - **恢复默认**：补回被删除的默认源，不影响自己添加的源
3. 搜索结果点进去，选择播放源 → 线路 → 集数即可播放

### 接口地址格式

需要苹果 CMS 的 **JSON** 采集接口，一般形如：

```
https://example.com/api.php/provide/vod/
https://example.com/api.php/provide/vod/from/xxxm3u8
```

只填域名时会自动补全为 `/api.php/provide/vod/`。返回 XML 的接口（地址中带 `/at/xml`）不支持。

## 项目结构

```
lib/
├── main.dart            # 入口，全局网络证书配置
├── net.dart             # User-Agent、内置根证书、HttpOverrides
├── models.dart          # 数据模型（数据源、影片、线路、剧集）及播放列表解析
├── maccms_api.dart      # 苹果 CMS 接口请求：搜索、详情、测试
├── source_store.dart    # 数据源本地存储 + 默认源列表
└── pages/
    ├── search_page.dart   # 搜索页（多源并发、结果合并）
    ├── detail_page.dart   # 详情页（源 / 线路 / 选集）
    ├── player_page.dart   # 播放页
    ├── sources_page.dart  # 数据源管理页
    └── widgets.dart       # 公共组件（海报、选集网格、线路切换）
assets/images/           # 图片资源（App 图标等）
```

## 开发与构建

### 环境

- Flutter 3.41+（Dart SDK ^3.11.5）
- Android Studio（含 Android SDK）

### 运行

```bash
flutter pub get
flutter run            # 连接模拟器或开启 USB 调试的手机
```

开发时修改 Dart 代码保存即可热重载；修改 `AndroidManifest.xml`、新增依赖、更换图标后需要停止并重新运行。

### 打包 APK

```bash
flutter build apk --release
```

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

### 更换 App 图标

替换 `assets/images/tubiao.png`（建议 1024×1024 以上的 PNG），然后执行：

```bash
dart run flutter_launcher_icons
```

### 修改默认数据源

编辑 `lib/source_store.dart` 中的 `kDefaultSources`。默认源只在首次安装时写入，已安装的用户可在数据源管理页点「恢复默认」获取新增的默认源。

## 依赖

| 包 | 用途 |
|---|---|
| [http](https://pub.dev/packages/http) | 网络请求 |
| [html](https://pub.dev/packages/html) | 清理简介中的 HTML 标签 |
| [video_player](https://pub.dev/packages/video_player) | 视频播放 |
| [chewie](https://pub.dev/packages/chewie) | 播放器控制界面 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 本地保存数据源 |
| [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) | 生成 App 图标（开发依赖） |

## 常见问题

**某个源显示「暂不支持搜索」或 403**
该接口关闭了搜索功能，或限制了访问地区，在数据源管理中关掉即可。

**能搜到但播放失败**
资源站的线路经常失效，在详情页换一个播放源或线路再试。标注「不是直链」的线路需要网页解析，本播放器无法直接播放。

**数据源全部失效**
资源站地址变动频繁，可自行搜索「苹果 CMS 采集接口」获取新的地址，在 App 内批量导入即可，无需重新打包。

## 免责声明

- 本项目仅供个人学习 Flutter 开发与交流使用，**不得用于任何商业用途**。
- 本项目本身**不存储、不提供、不上传任何影视资源**，所有内容均来自用户自行配置的第三方接口，与本项目无关。
- 请遵守所在地区的法律法规，支持正版影视内容。如有侵权，请联系删除。
