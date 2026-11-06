# HGame-Manager 架构文档

## 项目概述

**黄油仓库** - 基于 Flutter 开发的 Windows 本地 HGame 管理器

- **源码版本**: 以 `pubspec.yaml` 的 `version` 字段为唯一来源；应用包和文档站读取该值，README 徽章显示最新 GitHub Release，未发布时可能不同
- **平台**: Windows 10/11 (64位)
- **Flutter SDK**: >= 3.41.9
- **Dart SDK**: >= 3.11.5

## 技术栈

| 技术 | 用途 |
|------|------|
| Flutter | 跨平台 UI 框架 |
| Riverpod | 手写 Provider / StateNotifier 状态管理（当前未使用代码生成） |
| SQLite (sqflite_common_ffi) | 本地数据存储 |
| window_manager | 窗口管理 |
| desktop_multi_window | 攻略浮窗（独立系统子窗口） |
| hotkey_manager | 攻略浮窗全局快捷键 |
| html | HTML 解析 |
| http | HTTP 客户端（代理支持） |

## 目录结构

```
lib/
├── main.dart                    # 应用入口
├── core/                        # 核心业务层
│   ├── database/                # 数据库层
│   │   └── database_helper.dart # SQLite 数据库初始化和管理
│   ├── models/                  # 数据模型
│   │   └── models.dart          # Game, Tag, GameImage 模型定义
│   ├── providers/               # Riverpod 状态管理
│   │   ├── providers.dart       # 数据与业务 Provider
│   │   └── theme_provider.dart  # 主题状态
│   ├── repositories/            # 数据访问层
│   │   ├── game_repository.dart # 游戏数据 CRUD 操作
│   │   ├── tag_repository.dart  # 标签数据 CRUD 操作
│   │   └── tool_repository.dart # 工具数据 CRUD 操作
│   ├── services/                # 业务服务层
│   │   ├── app_logger.dart      # 日志服务
│   │   ├── game_count_service.dart # 游戏计数服务
│   │   ├── game_scanner_service.dart # 游戏扫描服务
│   │   ├── game_move_service.dart # 目录搬运与数据库路径同步
│   │   ├── scrape_apply_service.dart # 共享刮削处理
│   │   ├── database_backup_service.dart # 数据库快照与还原
│   │   ├── backup_service.dart  # 游戏存档备份与还原
│   │   ├── app_data_migration_service.dart # 应用数据迁移
│   │   ├── webdav_service.dart  # WebDAV 同步服务
│   │   ├── steam_service.dart    # Steam API 服务
│   │   └── fan2d_service.dart   # 2DFan 搜索和下载服务
│   └── utils/                   # 工具类
│       ├── app_paths.dart       # 应用路径管理
│       ├── app_settings.dart    # 配置文件管理
│       ├── guide_window_state.dart # 攻略浮窗状态存储（独立 JSON 文件）
│       ├── performance_monitor.dart # 性能监控
│       └── proxy_client.dart    # HTTP 代理客户端
├── ui/                          # UI 层
│   ├── controllers/             # UI 控制器
│   │   ├── sidebar_controller.dart # 侧边栏控制器
│   │   └── window_controller.dart # 窗口控制器
│   ├── windows/                 # 独立子窗口
│   │   └── guide_window.dart    # 攻略浮窗子窗口（desktop_multi_window 新引擎入口）
│   ├── pages/                   # 页面模块
│   │   ├── home_page.dart       # 主页面
│   │   ├── app_router.dart      # 路由管理
│   │   ├── games/               # 游戏页面
│   │   ├── categories/          # 分类页面
│   │   ├── favorites/           # 收藏页面
│   │   ├── played/              # 已玩游戏页面
│   │   ├── tools/               # 工具页面
│   │   ├── scraper/             # 刮削页面
│   │   └── settings/            # 设置页面
│   ├── theme/                   # 主题配置
│   │   └── app_theme.dart       # 玻璃拟态主题和组件
│   └── widgets/                 # 共享组件
│       ├── game_list_widget.dart # 游戏列表组件
│       ├── sidebar_widget.dart  # 侧边栏组件
│       └── title_bar_widget.dart # 标题栏组件
└── scraper/                     # 网页抓取器
    ├── html_parser.dart         # HTML 解析器
    ├── parse_utils.dart         # 解析工具函数
    ├── scraper_init.dart        # 抓取器初始化
    ├── site_parsers.dart        # 站点解析器注册
    ├── xpath_evaluator.dart     # XPath 评估器
    └── steam_html_converter.dart # Steam HTML转纯文本
```

## 架构模式

### 分层架构

```
┌─────────────────────────────────────┐
│           UI Layer (ui/)            │
│  Pages → Widgets → Controllers      │
├─────────────────────────────────────┤
│     State Management (providers/)   │
│         Riverpod Providers          │
├─────────────────────────────────────┤
│    Business Logic (services/)       │
│  Scanner, Logger, WebDAV, Count     │
├─────────────────────────────────────┤
│    Data Access (repositories/)      │
│    GameRepository, TagRepository    │
├─────────────────────────────────────┤
│      Data Layer (database/)         │
│      SQLite DatabaseHelper          │
├─────────────────────────────────────┤
│       Models (models/)              │
│      Game, Tag, GameImage           │
└─────────────────────────────────────┘
```

### 数据流

```
UI (Pages/Widgets)
    ↓ ↑
Riverpod Providers (providers.dart)
    ↓ ↑
Services (services/)
    ↓ ↑
Repositories (repositories/)
    ↓ ↑
Database (database/)
    ↓ ↑
Models (models/)
```

## 核心模型

完整字段与序列化以 `lib/core/models/models.dart`、`backup_entry.dart` 和 `tool.dart` 为准。

### Game 模型
```dart
class Game {
  final int? id;
  final String path;           // 游戏路径
  final String? title;         // 标题
  final String? version;       // 版本号
  final String? intro;         // 简介
  final String? features;      // 特点
  final String? changelog;     // 更新日志
  final String? downloadUrl;   // 下载链接
  final String? sourceUrl;     // 来源URL
  final int playCount;         // 游玩次数
  final DateTime? lastPlayedTime; // 最后游玩时间
  final DateTime? addedTime;   // 添加时间
  final bool isFavorite;       // 是否收藏
  final bool isPlayed;         // 是否已玩
  final bool isCleared;        // 是否通关
  final String? clearedBackupPath; // 通关备份路径
  final List<Tag> tags;        // 标签列表
  final List<GameImage> images; // 图片列表
  final int coverIndex;        // 封面图片索引
  final double rating;         // 评分 (0-5，支持半星)
  final String? review;        // 评论内容
  final String? savePath;      // 存档路径
  final String? guide;         // 攻略内容（Markdown格式）
  final int playDuration;      // 总游玩秒数
  final String? maker;         // 厂商
  final String? makerUrl;      // 厂商链接
  final String? gameLauncher;  // 启动程序
  final bool launcherLocked;   // 是否固定启动程序
  final bool useLocaleEmulator; // 是否转区启动
  final double introScrollPosition; // 简介滚动位置
  final double guideScrollPosition; // 攻略滚动位置
}
```

### Tag 模型
```dart
class Tag {
  final int? id;
  final String name;           // 标签名
  final String type;           // 类型: 'custom' | 'series'
  final String? displayName;   // 显示名称
  final bool isFavorite;       // 是否收藏
  final DateTime? createdAt;   // 创建时间
  final int gameCount;         // 关联游戏数量
}
```

### GameImage 模型
```dart
class GameImage {
  final int? id;
  final int gameId;            // 关联游戏ID
  final String imagePath;      // 图片路径
  final int sortOrder;         // 排序顺序
}
```

### BackupEntry 模型
```dart
class BackupEntry {
  final String name;          // 显示名称
  final String fileName;      // 文件名（含 .zip）
  final int sizeBytes;        // 文件大小
  final DateTime? date;       // 备份日期
  final BackupSource source;  // 来源：manual/preRestore/imported
  final String filePath;      // 完整路径
}
```

## 数据库表结构

当前 schema 版本为 **13**，建表与升级逻辑在 `lib/core/database/database_helper.dart`。数据库位于 `<exe_dir>/hgame_manager_data/hgame_manager.db`，启用外键和 WAL。除下列游戏与标签表外，还有 `tools`（工具记录）和 `settings`（保留表）；应用设置实际由 `AppSettings` 写入 JSON 文件。

### games 表
```sql
CREATE TABLE games (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT UNIQUE NOT NULL,
  title TEXT,
  version TEXT,
  intro TEXT,
  features TEXT,
  changelog TEXT,
  download_url TEXT,
  source_url TEXT,
  play_count INTEGER DEFAULT 0,
  last_played_time DATETIME,
  added_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  is_favorite INTEGER DEFAULT 0,
  is_played INTEGER DEFAULT 0,
  is_cleared INTEGER NOT NULL DEFAULT 0,
  cleared_backup_path TEXT,
  cover_index INTEGER DEFAULT 0,
  rating REAL DEFAULT 0,
  review TEXT,
  save_path TEXT,
  game_launcher TEXT,
  launcher_locked INTEGER NOT NULL DEFAULT 0,
  use_locale_emulator INTEGER NOT NULL DEFAULT 0,
  maker TEXT,
  maker_url TEXT,
  play_duration INTEGER DEFAULT 0,
  guide TEXT,
  intro_scroll_position REAL DEFAULT 0,
  guide_scroll_position REAL DEFAULT 0
);
```

### tags 表
```sql
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  type TEXT NOT NULL,  -- 'custom' | 'series'
  display_name TEXT,
  is_favorite INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(type, name)
);
```

### game_images 表
```sql
CREATE TABLE game_images (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  image_path TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
);
```

### game_tag_relation 表
```sql
CREATE TABLE game_tag_relation (
  game_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (game_id, tag_id),
  FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
);
```

## 核心 Provider

### 数据 Provider
- `sharedPreferencesProvider` - AppSettings 配置文件
- `gameRepositoryProvider` - 游戏数据仓库
- `tagRepositoryProvider` - 标签数据仓库
- `allGamesProvider` - 游戏库页面列表，排除通关记录；是否保留已玩游戏由设置控制
- `playedGamesProvider` - 已玩游戏列表
- `clearedGamesProvider` - 通关列表，支持本体缺失时保留记录和备份引用
- `favoriteGamesProvider` - 收藏游戏列表
- `allTagsProvider` - 所有标签
- `allSeriesProvider` - 所有系列
- `gamesByTagProvider` - 按标签筛选游戏
- `searchGamesProvider` - 搜索游戏
- `allToolsProvider` - 工具列表

### 状态 Provider
- `selectedNavIndexProvider` - 当前导航索引
- `viewModeProvider` - 视图模式（列表/海报）
- `sortModeProvider` - 排序模式
- `fontSizeProvider` - 字体大小
- `isScanningProvider` - 扫描状态
- `scanProcessedProvider` - 扫描进度
- `pageSizeProvider` - 分页大小
- `savePathServiceProvider` - 存档路径扫描服务
- `saveScanProgressProvider` - 存档扫描进度
- `isSaveScanningProvider` - 存档扫描状态

## 页面路由

```dart
enum NavRoute {
  scraper(0, '刮削'),    // 刮削页面
  games(1, '游戏'),      // 游戏列表页面
  categories(2, '分类'), // 分类管理页面
  favorites(3, '收藏'),  // 收藏游戏页面
  played(4, '已玩'),     // 已玩游戏页面
  cleared(5, '通关'),    // 通关游戏页面
  tools(6, '工具'),     // 工具页面
  settings(7, '设置');   // 设置页面
}
```

路由枚举还包含图标。七个内容页由 `AppRouter` 切换；「设置」通过侧边栏打开弹窗，游戏详情也是弹窗。

## 核心服务

### GameScannerService
- 扫描游戏库目录
- 解析 metadata.json 文件
- 批量写入数据库
- 支持取消扫描
- 增量扫描（跳过未修改游戏）
- 按目录段判断所属游戏库，避免清理相邻目录的记录；游戏库刷新扫描元数据，刮削中心另行扫描来源链接

### AppDataMigrationService / GameDataMigrationService
- 前者在启动时查找旧安装数据，保留迁移备份；无权限的候选目录会跳过，迁移检查异常记录日志后继续启动
- 后者迁移游戏目录中的管理器元数据和有明确引用的配图到 `HGMDatas`，保留游戏自带资源

### AppLogger
- 统一日志管理
- 支持文件日志
- 错误捕获和记录

### SavePathService
- 自动扫描游戏存档位置
- 基于 AppData\LocalLow 和 AppData\Local 目录
- 智能识别游戏名（排除引擎 EXE）
- 置信度评分排序

### BackupService
- 本地存档备份/还原（zip 压缩）
- 路径占位符编码（%USERPROFILE%、%GameDir%）实现跨设备迁移
- 自定义备份导入（zip/文件夹，智能文件匹配还原）
- 自动检测并导入"存档"文件夹
- 备份重命名和批量删除
- 还原前先读取并校验 ZIP，再创建「还原前备份」；保护备份失败时停止覆盖
- 检查解压路径、链接、CRC 与 500 MiB 大小限制，防止越界写入；写盘失败不保证逐文件回滚，可使用保护备份恢复

### FolderRenameService / ClearedMetadataBackupService
- 前者按可配置规则组合游戏 ID、厂商、系列、标题和版本，过滤非法目录名，并调用共享搬运服务
- 后者保存通关游戏元数据，支持本体删除后的记录保留；详情页标题变更也会同步调整通关备份目录名

### Fan2dService
- 2DFan 论坛存档搜索和下载
- 域名自动检测（访问 /domain 页面获取可用域名列表）
- RAR 解压（调用系统 WinRAR）并重打包为 ZIP
- 临时文件自动清理
- 2DFan 攻略搜索和抓取，支持多个 walkthrough 页面及 XPath / CSS 选择器回退

### FolderTransferService
- 游戏目录搬运（同卷 rename 快路径 / 跨卷 1MB 分块复制）
- 进度回调（扫描 → 复制 → 校验 → 清理）、每文件失败重试（3 次退避）
- 完整性校验（文件数量 + 每文件大小 + 目录结构），失败或取消时清理目标、保留源
- 目标目录已存在、与源互相包含、含符号链接时直接拒绝
- 两阶段提交：校验通过后先调 `commit`（写库），再删除源；`commit` 失败时跨卷删除目标副本、同卷尝试 rename 回原名，回滚失败会报告文件实际位置

### GameMoveService
- 移动游戏文件夹共享入口（列表移动、详情修改路径、自动重命名、刮削整理、通关移入/移回共用）
- 委托 FolderTransferService 完成搬运，写库作为 `commit` 在两阶段提交中执行：`GameRepository.relocateGame` 在同一 SQLite 事务中更新数据库路径、图片引用、启动器、存档路径与正文引用；metadata 写入失败时回滚事务并还原原文件
- 写库失败时尝试回滚，瞬时锁冲突自动重试 2 次；回滚未完成时报告文件实际位置和清理提示
- 搬运失败/取消时数据库保持不变

### DatabaseBackupService
- 本地导出和 WebDAV 备份共用 `VACUUM INTO` 一致性数据库快照，包含 WAL 中已经提交的记录
- 导入前检查 SQLite 完整性、核心表、版本与设置格式，保留原文件直到数据库和图片处理全部成功
- 导入失败回滚数据库与设置；回滚失败保留恢复目录并报出位置
- `DatabaseHelper.runMaintenance` 阻止新的数据库访问跨越替换阶段；文件系统与 SQLite 之间仍不具备断电原子性

### 列表封面
- ListView/GridView 按需构建 `Image`，使用 Flutter 图片缓存管理生命周期
- 保留原始分辨率解码，不对封面做固定 1024×1024 降采样；多个图片加载可并发，详情媒体独立处理
- 下载器写入及共享刮削发布同路径图片后失效文件缓存；列表以图片路径与图片记录 ID 更新组件，避免继续显示旧封面

### ScrapeApplyService
- 快速刮削、重新刮削、刮削中心调用 `applyScrapeResult` 完成字段合并、元数据写入、标签、配图和目录整理
- Steam/DLsite 单个与批量添加仍各自处理搜索结果、元数据和标签；共用 `markScraped` 标记、`ConcurrentImageDownloader` 下载及 `organizeFolder` 整理，并非五入口全部调用总编排
- 纯函数：stripVersionFromTitle、resolveCategoryName、mergeGameInfo、buildMetadataJson、buildNumberedUrlMapping
- 流程：syncTags 标签同步、downloadAndApplyImages 图片下载与引用重写、fixImageUrlsInMetadata 元数据修复、moveGameToSorted/organizeFolder 目录整理、applyScrapeResult 总编排
- 图片默认并发 3；刮削中心线程数可选 1–8；取消后停止出队，已进入应用结果阶段的任务先完成写入

### ForumDomainUtils
- 论坛自定义域名对旧 source_url 的自动重写（`resolveWithCustomDomain`）
- 宽松但有限制的同站匹配：仅比较主域名（host 最后两段）首标签是否含站点品牌词
- 访问来源/快速刮削/重新刮削/刮削中心入口统一调用

### WebdavService
- 游戏级 WebDAV 备份文件夹管理
- 模糊匹配云端游戏文件夹（双向近似匹配+置信度）
- 单独游戏存档的上传/下载/删除
- 游戏库数据库、设置和可选图片备份，支持增量图片上传
- 文件名按 URI 路径段编码；下载写入暂存文件，验证传输长度后再替换目标，gzip 响应按流解压

### ImageService
- 图片文件管理（复制、删除）
- 本地文件选择
- URL图片下载
- 图片存储目录管理
- `invalidateFileCache` 供共享下载和刮削层失效 `FileImage` 缓存

### SteamService
- Steam API 游戏搜索和详情获取
- 智能名称构建回退搜索
- steam_appid.txt 自动识别
- Steam HTML 描述转纯文本
- 图片批量下载

### VersionCheckService
- 从游戏标题提取搜索关键词
- 在维咔/飞雪/嘤嘤怪三个站点搜索
- 版本号对比取最大值
- 支持自定义域名

### PilipiliService
- pilipili专栏文章搜索（WBI签名）
- 文章内容刮削（HTML/JSON转Markdown）
- 关键词智能提取（过滤版本号、官中等）

### GuideWindowService
- 攻略浮窗主窗口侧管理（详情页右侧悬浮按钮栏「浮窗显示攻略」触发）
- 基于 desktop_multi_window 创建独立系统子窗口（同进程新引擎，入口参数 `multi_window <id> <json>`）
- **子窗口引擎只注册 window_manager 插件**（`flutter_window.cpp` 的 `DesktopMultiWindowSetWindowCreatedCallback`）：media_kit / flutter_inappwebview 等重型插件在子窗口注册会导致主窗口输入被冻结；跨窗口通信通道由插件内部自行注册，不受影响
- 浮窗状态记忆（位置/大小/置顶/透明度/字号/各游戏滚动位置）存于独立文件 `guide_window_state.json`，避免与 settings.json 并发写
- 关闭浮窗必须走 `setPreventClose(false)` + `close()` 系统 WM_CLOSE 流程；**禁止** `windowManager.destroy()`（其 Windows 实现是 PostQuitMessage，会退出整个进程）
- 全局快捷键（hotkey_manager，可在 设置→管理→攻略浮窗快捷键 自定义）：
  - 开启/关闭：默认 CTRL+1（重开显示最后一次的内容）
  - 置顶：默认 CTRL+2
  - 上滑/下滑：默认 CTRL+↑/↓（步长 300px）
- 主窗口通过 `WindowController.invokeMethod` 转发 updateContent/scroll/togglePin/closeWindow/focus；子窗口关闭时回调 `guideWindowClosed`

## UI 组件

### 玻璃拟态组件
- `GlassContainer` - 毛玻璃容器
- `GlassCard` - 毛玻璃卡片（支持悬停动画）
- `GlassButton` - 毛玻璃按钮
- `GlassChip` - 标签芯片
- `GlassAppBar` - 毛玻璃应用栏
- `GlassSearchBar` - 搜索栏
- `GlassTabBar` - 标签栏
- `showGlassDialog` - 对话框函数

### 多选控制器
- `MultiSelectController<T>` - 通用多选状态管理（支持全选、范围选择）

### 动画组件
- `StaggeredItem` - 交错动画列表项
- `BreathingBorder` - 边框呼吸动画
- `GradientBackground` - 渐变背景

## 主题配置

### 颜色系统
- 支持浅色和暗色模式，UI 通过 `AppTheme.get…(context)` 读取动态颜色；以下为浅色主题示例，常量定义以 `app_theme.dart` 为准
- **主色调**: 蓝紫渐变 (#2563EB → #7C3AED)
- **背景色**: 浅灰渐变 (#F0F4F8)
- **表面色**: 半透明白 (#FFFFFF 80%)
- **文字色**: 深灰 (#374244)

### 玻璃拟态常量
```dart
class GlassConstants {
  // 圆角
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 24.0;

  // 模糊
  static const double blurSmall = 10.0;
  static const double blurMedium = 18.0;
  static const double blurLarge = 30.0;

  // 动画
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 400);
}
```

## 配置管理

### AppSettings
- 基于 JSON 文件的配置存储
- 存储位置: `<exe_dir>/hgame_manager_data/settings.json`
- 替代 SharedPreferences，保持数据本地化

### 配置项
- `font_family` - 字体
- `font_size` - 字体大小
- `view_mode` / `sort_mode` - 通用 Provider 的视图/排序配置；主游戏列表使用下述 `game_list_*` 配置
- `page_size` - 分页大小
- `sorted_path` - 旧版单整理目录配置，兼容回退使用
- `library_path` - 游戏库路径（JSON 数组格式，支持多目录）
- `sorted_paths` - 各游戏库对应的整理目录（JSON 对象格式，键为库路径，值为整理路径）
- `cleared_paths` - 各游戏库对应的通关目录（JSON 对象格式）
- `domain_2dfan` - 2DFan 自定义域名
- `fixed_column_count` - 海报视图是否固定列数 (bool)
- `column_count` - 海报视图每行列数 (int, 2-8, 默认3)
- `game_list_view_mode` - 游戏列表视图模式 ('poster' | 'list')
- `game_list_sort_mode` - 游戏列表排序模式
- `game_list_sort_mode_games` / `game_list_sort_mode_played` / `game_list_sort_mode_cleared` - 游戏、已玩、通关页面各自的排序模式
- `game_list_pagination_mode` - 游戏列表分页模式 ('paginated' | 'infiniteScroll')
- `game_list_items_per_page` - 列表视图每页显示数量 (int, 3-20, 默认5)
- `guide_window_hotkey_toggle` / `guide_window_hotkey_pin` / `guide_window_hotkey_scroll_up` / `guide_window_hotkey_scroll_down` - 攻略浮窗全局快捷键（HotKey JSON 格式）
- 代理设置、Cookie 设置等

## 网页抓取器

### 支持站点
- ACG嘤嘤怪
- 飞雪ACG
- 维咔ACG
- DLsite
- Steam

### 抓取流程
1. 根据入口调用站点 API 或 HTTP 获取页面，必要时经内置浏览器完成验证或渲染
2. 解析为游戏信息；URL 刮削三入口交给 `applyScrapeResult`，Steam/DLsite 添加入口按其导入流程处理
3. 保存游戏信息、元数据、来源和已刮削标记，更新标签与配图
4. 按入口对应的 `ScrapeModeConfigs` 决定是否重命名和移动目录

管理器元数据位于 `<game>/HGMDatas/`，存档备份位于其 `backup/` 子目录。兼容旧版游戏根目录的元数据；游戏自带 `image/`、`images/` 不作为可整体搬走的管理器资源。

## 构建和运行

Windows 构建需要 Visual Studio 2022 / Build Tools 的 C++ 桌面工作负载、Windows SDK 和 PATH 中可用的 NuGet CLI。完整说明与串行测试命令见 `docs/development/build.md`。

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run -d windows

# 构建发布版本
flutter build windows --release
```

## 文档站（VitePress + GitHub Pages）

项目文档站基于 [VitePress](https://vitepress.dev) 构建，源码位于 `docs/`，通过 GitHub Actions 自动部署到 GitHub Pages。

```
docs/
├── .vitepress/
│   ├── config.mts           # 站点配置（base 为 /HGame-Manager/，与仓库名一致）
│   ├── theme/               # 专属主题（蓝紫渐变 + 玻璃拟态）
│   │   ├── index.ts
│   │   └── custom.css
│   └── dist/                # 构建产物（已 gitignore）
├── public/logo.png          # 站点 Logo
├── index.md                 # 首页（Hero + 特性卡片）
├── guide/                   # 使用指南（含 images/ 教程截图）
├── faq.md                   # 常见问题
└── development/build.md     # 从源码构建
```

```bash
# 本地预览文档站（需 Node.js）
npm install
npm run docs:dev       # 开发模式，默认 http://localhost:5173

# 构建静态产物
npm run docs:build     # 输出到 docs/.vitepress/dist
```

- 部署工作流：`.github/workflows/deploy-docs.yml`（push 到 master 且文档、`pubspec.yaml`、Node 依赖或工作流变更时自动构建部署，也支持手动触发）
- 线上地址：`https://linyuanovo.github.io/HGame-Manager/`
- 首次部署需在仓库 **Settings → Pages → Source** 选择 **GitHub Actions**

## 文件路径

```
build/windows/x64/runner/Release/hgame_manager.exe
```

## 注意事项

1. **数据库**: 使用 sqflite_common_ffi 支持桌面平台
2. **窗口管理**: 使用 window_manager 实现自定义标题栏
3. **状态管理**: 使用 Riverpod 2.x 手写 Provider / StateNotifier
4. **主题**: 玻璃拟态设计风格
5. **平台**: 仅支持 Windows 桌面
