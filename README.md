<h1 align="center">黄油仓库</h1>

<p align="center">
  <b>HGame-Manager</b>
</p>

<p align="center">
  <nobr>
    <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=flat-square&logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows" alt="Windows">
    <img src="https://img.shields.io/badge/License-AGPL--3.0-green?style=flat-square" alt="License">
    <img src="https://img.shields.io/github/v/release/LinYuanovo/HGame-Manager?style=flat-square&label=Version&color=blue" alt="Version">
  </nobr>
</p>

<p align="center">
  <b>一款基于 Flutter 开发的 Windows 本地 HGame 管理器</b><br>
  <i>玻璃拟态设计 · 智能刮削 · 存档管理 · 转区启动 · 分类存放</i>
</p>

***

## 快速开始

### 环境要求

<details>
<summary>点击展开查看环境要求</summary>

#### 用户使用（直接下载）
- **操作系统**: Windows 10/11 (64位)
- **内存**: 建议 4GB+
- **磁盘空间**: 200MB+（解压后）

#### 开发构建
- **Flutter SDK**: >= 3.41.9
- **Dart SDK**: >= 3.11.5
- **操作系统**: Windows 10/11 (64位)
- **构建工具**: Visual Studio 2022 / Build Tools（安装「使用 C++ 的桌面开发」及 Windows SDK），并将 NuGet CLI 加入 PATH
- **内存**: 建议 8GB+
- **磁盘空间**: 2GB+（含构建缓存）

</details>

### 安装步骤

#### 直接使用

Windows 系统在 [releases](https://github.com/LinYuanovo/HGame-Manager/releases) 页面直接下载 zip 压缩包后**解压**即可使用([网盘](https://docs.qq.com/sheet/DVXZ6U2xmbFZuVGtQ?tab=BB08J2))

#### 使用教程

- [在线文档站](https://linyuanovo.github.io/HGame-Manager/)

- [图文教程](https://github.com/LinYuanovo/HGame-Manager/blob/master/%E4%BD%BF%E7%94%A8%E6%95%99%E7%A8%8B.md)

- [视频教程在网盘内](https://docs.qq.com/sheet/DVXZ6U2xmbFZuVGtQ?tab=BB08J2)

#### 自行构建

<details>
<summary>点击展开查看自行构建方式</summary>

```bash
# 克隆仓库
git clone https://github.com/LinYuanovo/HGame-Manager.git
cd HGame-Manager

# 安装依赖
flutter pub get

# 运行应用（开发模式）
flutter run -d windows

# 构建发布版本
flutter build windows --release
```

可执行文件位于：
```
build/windows/x64/runner/Release/hgame_manager.exe
```

</details>

## 游戏库目录结构

每个游戏使用独立文件夹，可放在分类子目录中。直接添加本地游戏不需要来源链接；通过刮削中心抓取帖子信息时，需要准备 `source_url.txt`：

```
游戏库根目录/
├── SLG/                        # 按系列分类
│   └── GameName/
│       ├── Game.exe            # 游戏启动程序（示例）
│       └── HGMDatas/           # 管理器数据目录
│           ├── source_url.txt  # 来源链接（按需）
│           ├── metadata.json   # 游戏信息
│           ├── images/         # 管理器配图
│           └── backup/         # 存档备份
├── RPG/
│   └── ...
└── 未分类/
    └── ...
```

### 关键文件说明

| 文件 | 说明 | 是否必需 |
| --- | --- | --- |
| `HGMDatas/source_url.txt` | 来源页面链接；刮削中心按此文件发现待刮削游戏 | 本地添加不需要，帖子刮削时需要 |
| `HGMDatas/metadata.json` | 游戏信息；刮削成功后含 `scraped_at` 已刮削标识，游戏库刷新按此文件扫描 | 导入或刮削时生成 |
| `HGMDatas/images/` | 管理器保存的封面、截图和攻略图片 | 按需生成 |
| `HGMDatas/backup/` | 游戏存档的 ZIP 备份 | 备份或导入存档时生成 |

兼容游戏根目录的旧版 `source_url.txt`、`metadata.json` 和有明确管理器引用的配图。手动准备来源文件时，可与游戏启动程序放在同一目录。游戏自带的 `image/`、`images/` 资源不应手动移入 `HGMDatas`。

应用数据库、设置等保存在 EXE 同级的 `hgame_manager_data/`，与各游戏的 `HGMDatas/` 分开存放。

### 刮削整理后的目录

配置整理目录并在「设置 → 管理 → 刮削行为管理」中为相应入口启用移动后，游戏会按系列分类移入整理目录：

```
整理目录/
├── SLG/
│   └── GameName/
│       └── HGMDatas/
│         ├── source_url.txt
│         ├── metadata.json
│         └── images/
├── RPG/
│   └── ...
└── Unclassified/                     # 无系列标签的游戏
    └── ...
```

## 功能特性

### 🔍 刮削中心

- **多站点支持**：[ACG嘤嘤怪](https://acgyyg.ru/) / [飞雪ACG](https://feixueacg.org/)/ [维咔ACG](https://www.vikacg.com/)
- **自定义解析器**：通过xpath实现自定义站点宽泛解析
- **云端导入**: 支持从 DLsite（RJ号/名称搜索）或 Steam（App ID/名称搜索）导入游戏信息和封面图
- **自动整理**：按各入口的刮削行为配置重命名、移动游戏到整理目录
- **跳过已刮削**：扫描默认跳过已刮削游戏（按 metadata.json 的 `scraped_at` 标识判断），勾选「包含已刮削的游戏」可重新刮削
- **智能标签**：自动关联重叠标签（如"互动SLG" → "SLG"）
- **简介排版优化**：尽可能保留原始 HTML 布局
- **批量导入**：同时导入多个游戏
- **取消任务**：取消后停止启动新任务，已进入保存阶段的游戏完成当前写入后结束

![刮削页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/scraper_page.png)

![多渠道刮削页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_scraper.jpg)

### 🎮 游戏管理

- **多种视图模式**：列表 / 海报墙
- **灵活排序**：标题、添加时间、最近游玩
- **分页 / 瀑布流**：两种浏览模式
- **收藏功能**：收藏游戏优先排列
- **游玩追踪**：记录游玩次数、时间和时长
- **富文本编辑**：Markdown 编辑器，支持图片预览和插入
- **添加方式**：单个添加、批量添加或拖入文件夹 / EXE，可选择 Steam、DLsite 或不刮削
- **目录搬运**：显示移动进度，支持取消；同步更新相关路径，写库失败时回滚
- **通关记录**：可保留游戏信息和备份，在移走或删除本体后继续查看

![游戏页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/games_page.png)

### 📁 分类系统

- **标签 / 系列管理**：右键修改删除
- **收藏分类**：支持收藏标签和系列
- **自定义整理**：支持连续添加、拖拽排序，空标签保留到手动删除

![分类页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/categories_page.png)

![分类详情页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/category_detail_page.png)

### 🖼️ 游戏详情

- **大图查看**：支持键盘导航，80% 窗口大小的图片查看器，支持鼠标滚轮缩放（20%-500%）和拖拽
- **图片管理**：自定义添加、删除、排序图片
- **信息存储**：网盘链接、解压码按钮双击复制
- **编辑模式**：可编辑版本号、标签、下载地址、解压码等
- **检查更新**：根据已有版本号检查更新
- **攻略浮窗**：独立窗口查看攻略，支持置顶、调整字号和全局快捷键

![游戏详情页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_detail_page.png)

![游戏更新弹窗](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_update_window.png)

![已玩游戏评论弹窗](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/played_comment_window.png)

![游戏攻略页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_guide_page.png)

### 💾 存档管理

- **下载存档**：从 2DFan 搜索并下载存档
- **导入自定义存档**：导入自定义备份，如：全CG存档等
- **备份当前存档**：将当前的存档文件夹进行备份
- **上传至云端**：通过webdav将存档上传，并能够进行下载、恢复等操作
- **还原保护**：覆盖已有存档前先备份；保护备份失败或压缩包校验不通过时停止还原

![存档管理页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_save_manager_page.png)

![查看云端备份](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_save_cloud.png)

### 📦 游戏库备份

- 在「设置 → 备份」中导出或导入数据库和设置，可选择包含图片
- WebDAV 支持增量图片备份，避免重复上传未变化的配图
- 备份包含最新已保存记录；导入失败时回滚数据库和设置，回滚未完成时提示恢复文件位置

### 🔧 工具导入

- **导入工具**：导入常用软件可双击快速启动
- **转区启动**：导入'[LEProc.exe](https://github.com/xupefei/Locale-Emulator/releases)'后可以联动转区启动游戏

![导入工具](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/import_tools.png)

![转区启动](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/LE_launch.png)

## 技术栈

| 技术 | 版本 | 用途 |
| --- | --- | --- |
| [Flutter](https://flutter.dev) | 3.41.9 | 跨平台 UI 框架 |
| [Dart](https://dart.dev) | 3.11.5 | 编程语言 |
| [Riverpod](https://riverpod.dev) | ^2.4.9 | 状态管理 |
| [SQLite](https://www.sqlite.org) | via sqflite_common_ffi ^2.3.1 | 本地数据存储 |

## 项目结构

<details>
<summary>点击展开查看主要目录结构</summary>

```
HGame-Manager/
├── lib/                          # 应用源代码
│   ├── main.dart                 # 应用入口
│   ├── core/                     # 核心业务逻辑
│   │   ├── database/             # 数据库层
│   │   ├── models/               # 数据模型
│   │   ├── providers/            # Riverpod 状态管理
│   │   ├── repositories/         # 数据访问层
│   │   ├── services/             # 业务服务
│   │   └── utils/                # 工具类
│   ├── ui/                       # 用户界面
│   │   ├── controllers/          # UI 控制器
│   │   ├── windows/              # 攻略浮窗
│   │   ├── theme/                # 主题配置（玻璃拟态）
│   │   ├── widgets/              # 共享组件
│   │   └── pages/                # 页面模块
│   └── scraper/                  # 网页抓取器
│       ├── html_parser.dart      # HTML 解析器
│       ├── dlsite_parser.dart    # DLsite 解析器
│       ├── site_parsers.dart     # 站点解析器注册
│       ├── xpath_evaluator.dart  # XPath 评估器
│       ├── rich_text_extractor.dart # 富文本提取
│       ├── steam_html_converter.dart # Steam HTML 转纯文本
│       ├── parse_utils.dart      # 解析工具函数
│       └── scraper_init.dart     # 抓取器初始化
├── docs/                         # VitePress 文档站（自动部署至 GitHub Pages）
├── test/                         # 单元和组件测试
├── integration_test/             # Windows 原生集成测试
├── windows/                      # Windows 平台代码
└── pubspec.yaml                  # 项目配置
```

</details>

架构与数据流见 [ARCHITECTURE.md](ARCHITECTURE.md)，构建及 Windows Debug EXE 验证方式见[开发指南](docs/development/build.md)。README 顶部版本徽章显示最新 GitHub Release；本地源码版本以 `pubspec.yaml` 为准。

## 赞助

如果你喜欢这个项目，可以赞助支持

![赞助](https://raw.githubusercontent.com/LinYuanovo/HGame-Manager/refs/heads/master/docs/guide/images/image53.png)
