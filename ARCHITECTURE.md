# HGame-Manager 架构文档

## 项目概述

**黄油仓库** - 基于 Flutter 开发的 Windows 本地 HGame 管理器

- **版本**: 1.3.5
- **平台**: Windows 10/11 (64位)
- **Flutter SDK**: >= 3.41.9
- **Dart SDK**: >= 3.11.5

## 技术栈

| 技术 | 用途 |
|------|------|
| Flutter | 跨平台 UI 框架 |
| Riverpod | 状态管理 |
| SQLite (sqflite_common_ffi) | 本地数据存储 |
| window_manager | 窗口管理 |
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
│   │   └── providers.dart       # 所有 Provider 定义
│   ├── repositories/            # 数据访问层
│   │   ├── game_repository.dart # 游戏数据 CRUD 操作
│   │   └── tag_repository.dart  # 标签数据 CRUD 操作
│   ├── services/                # 业务服务层
│   │   ├── app_logger.dart      # 日志服务
│   │   ├── game_count_service.dart # 游戏计数服务
│   │   ├── game_scanner_service.dart # 游戏扫描服务
│   │   └── webdav_service.dart  # WebDAV 同步服务
│   └── utils/                   # 工具类
│       ├── app_paths.dart       # 应用路径管理
│       ├── app_settings.dart    # 配置文件管理
│       ├── performance_monitor.dart # 性能监控
│       └── proxy_client.dart    # HTTP 代理客户端
├── ui/                          # UI 层
│   ├── controllers/             # UI 控制器
│   │   ├── sidebar_controller.dart # 侧边栏控制器
│   │   └── window_controller.dart # 窗口控制器
│   ├── pages/                   # 页面模块
│   │   ├── home_page.dart       # 主页面
│   │   ├── app_router.dart      # 路由管理
│   │   ├── games/               # 游戏页面
│   │   ├── categories/          # 分类页面
│   │   ├── favorites/           # 收藏页面
│   │   ├── played/              # 已玩游戏页面
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
    └── xpath_evaluator.dart     # XPath 评估器
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
  final List<Tag> tags;        // 标签列表
  final List<GameImage> images; // 图片列表
  final int coverIndex;        // 封面图片索引
  final int? rating;           // 评分 (1-10)
  final String? review;        // 评论内容
  final String? savePath;      // 存档路径
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

## 数据库表结构

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
  cover_index INTEGER DEFAULT 0,
  rating REAL DEFAULT 0,
  review TEXT,
  save_path TEXT
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
- `allGamesProvider` - 所有游戏列表
- `playedGamesProvider` - 已玩游戏列表
- `favoriteGamesProvider` - 收藏游戏列表
- `allTagsProvider` - 所有标签
- `allSeriesProvider` - 所有系列
- `gamesByTagProvider` - 按标签筛选游戏
- `searchGamesProvider` - 搜索游戏

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
  settings(6, '设置');   // 设置页面
}
```

## 核心服务

### GameScannerService
- 扫描游戏库目录
- 解析 metadata.json 文件
- 批量写入数据库
- 支持取消扫描
- 增量扫描（跳过未修改游戏）

### AppLogger
- 统一日志管理
- 支持文件日志
- 错误捕获和记录

### SavePathService
- 自动扫描游戏存档位置
- 基于 AppData\LocalLow 和 AppData\Local 目录
- 智能识别游戏名（排除引擎 EXE）
- 置信度评分排序

### WebdavService
- WebDAV 同步支持
- 配置文件同步

### ImageService
- 图片文件管理（复制、删除）
- 本地文件选择
- URL图片下载
- 图片存储目录管理

### VersionCheckService
- 从游戏标题提取搜索关键词
- 在维咔/飞雪/嘤嘤怪三个站点搜索
- 版本号对比取最大值
- 支持自定义域名

## UI 组件

### 玻璃拟态组件
- `GlassContainer` - 毛玻璃容器
- `GlassCard` - 毛玻璃卡片（支持悬停动画）
- `GlassButton` - 毛玻璃按钮
- `GlassChip` - 标签芯片
- `GlassAppBar` - 毛玻璃应用栏
- `GlassSearchBar` - 搜索栏
- `GlassTabBar` - 标签栏
- `GlassDialog` - 对话框

### 多选控制器
- `MultiSelectController<T>` - 通用多选状态管理（支持全选、范围选择）

### 动画组件
- `StaggeredItem` - 交错动画列表项
- `BreathingBorder` - 边框呼吸动画
- `GradientBackground` - 渐变背景

## 主题配置

### 颜色系统
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
- `view_mode` - 视图模式
- `sort_mode` - 排序模式
- `page_size` - 分页大小
- `sorted_path` - 整理目录路径
- `library_path` - 游戏库路径
- `fixed_column_count` - 海报视图是否固定列数 (bool)
- `column_count` - 海报视图每行列数 (int, 2-8, 默认3)
- `game_list_view_mode` - 游戏列表视图模式 ('poster' | 'list')
- `game_list_sort_mode` - 游戏列表排序模式
- `game_list_pagination_mode` - 游戏列表分页模式 ('paginated' | 'infiniteScroll')
- `game_list_items_per_page` - 列表视图每页显示数量 (int, 3-20, 默认5)
- 代理设置、Cookie 设置等

## 网页抓取器

### 支持站点
- ACG嘤嘤怪
- 飞雪ACG
- 微咔ACG
- DLsite

### 抓取流程
1. 解析 HTML 页面
2. 提取元数据（标题、版本、简介等）
3. 下载图片
4. 生成 metadata.json
5. 保存 source_url.txt

## 构建和运行

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run -d windows

# 构建发布版本
flutter build windows --release
```

## 文件路径

```
build/windows/x64/runner/Release/hgame_manager.exe
```

## 注意事项

1. **数据库**: 使用 sqflite_common_ffi 支持桌面平台
2. **窗口管理**: 使用 window_manager 实现自定义标题栏
3. **状态管理**: 使用 Riverpod 2.x + 代码生成
4. **主题**: 玻璃拟态设计风格
5. **平台**: 仅支持 Windows 桌面
