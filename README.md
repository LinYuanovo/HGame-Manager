<h1 align="center">黄油仓库</h1>

<p align="center">
  <b>HGame-Manager</b>
</p>

<p align="center">
  <nobr>
    <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=flat-square&logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows" alt="Windows">
    <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
    <img src="https://img.shields.io/badge/Version-1.3.7-blue?style=flat-square" alt="Version">
  </nobr>
</p>

<p align="center">
  <b>一款基于 Flutter 开发的 Windows 本地 HGame 管理器</b><br>
  <i>玻璃拟态设计 · 智能刮削 · 标签管理 · 收藏追踪</i>
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
- **内存**: 建议 8GB+
- **磁盘空间**: 2GB+（含构建缓存）

</details>

### 安装步骤

#### 直接使用

Windows 系统在 [releases](https://github.com/LinYuanovo/HGame-Manager/releases) 页面直接下载 zip 压缩包后**解压**即可使用([网盘](https://docs.qq.com/sheet/DVXZ6U2xmbFZuVGtQ?tab=BB08J2))

#### 使用教程

- [图文教程](https://github.com/LinYuanovo/HGame-Manager/blob/master/%E4%BD%BF%E7%94%A8%E6%95%99%E7%A8%8B.docx)

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

应用期望以下目录结构来正确识别和管理游戏：

```
游戏库根目录/
├── SLG/                        # 按系列分类
│   └── GameName/
│       └── source_url.txt      # 来源URL（DLsite/Steam，必需）
├── RPG/
│   └── ...
└── 未分类/
    └── ...
```

### 关键文件说明

| 文件 | 说明 | 是否必需 |
| --- | --- | --- |
| `source_url.txt` | 游戏来源页面 URL（DLsite/Steam），用于刮削和导入 | 是 |
| `metadata.json` | 游戏元数据（标题、版本、简介等） | 否（刮削后自动生成） |
| `images/` | 游戏截图和封面图 | 否（刮削后自动下载） |

### 刮削整理后的目录

刮削功能会自动将游戏按系列分类移动到整理目录：

```
整理目录/
├── SLG/
│   └── GameName/
│       ├── source_url.txt
│       ├── metadata.json
│       └── images/
├── RPG/
│   └── ...
└── 未分类/                     # 无系列标签的游戏
    └── ...
```

## 功能特性

### 刮削中心

- **多站点支持**：[ACG嘤嘤怪](https://acgyyg.ru/) / [飞雪ACG](https://feixueacg.org/)/ [维咔ACG](https://www.vikacg.com/)
- **云端导入**: 支持从 DLsite（RJ号/名称搜索）或 Steam（App ID/名称搜索）导入游戏信息和封面图
- **自动整理**：刮削后按系列分类移动到整理目录
- **智能标签**：自动关联重叠标签（如"互动SLG" → "SLG"）

![刮削页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/scraper_page.png)

![多渠道刮削页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_scraper.jpg)

### 游戏管理

- **多种视图模式**：列表 / 海报墙
- **灵活排序**：标题、添加时间、最近游玩
- **分页 / 瀑布流**：两种浏览模式
- **收藏功能**：收藏游戏优先排列
- **游玩追踪**：记录游玩次数和时间
- **存档查找**：智能查找已玩游戏的存档位置

![游戏页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/games_page.png)

![存档弹窗](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_saved_window.png)

### 分类系统

- **标签 / 系列管理**：右键修改删除
- **收藏分类**：支持收藏标签和系列

![分类页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/categories_page.png)

![分类详情页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/category_detail_page.png)

### 游戏详情

- **图片轮播**：支持键盘导航
- **大图查看**：80% 窗口大小的图片查看器
- **图片管理**：自定义添加、删除、排序图片
- **下载链接**：网盘按钮双击复制
- **解压码**：独立显示，双击复制
- **编辑模式**：可编辑版本号、标签、下载地址、解压码等
- **检查更新**：根据已有版本号检查更新

![游戏详情页面](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_detail_page.png)

![游戏更新弹窗](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/game_update_window.png)

![已玩游戏评论弹窗](https://raw.githubusercontent.com/LinYuanovo/pic_bed/refs/heads/main/HGame-Manager/played_comment_window.png)

### 设置

- **忽略文件夹**：扫描和刮削分别设置
- **系列类型管理**：自定义添加系列类型
- **字体大小**：全局字体大小调整

### v1.3.7 新功能

- **存档路径模糊匹配**: 自动识别如 `AppData\Roaming\RenPy\游戏名-数字` 格式的存档路径
- **游戏文件夹移动**: 右键菜单"移动文件夹"，支持跨盘移动，自动更新数据库路径
- **详情页路径编辑**: 编辑模式下可修改游戏文件夹路径，自动移动文件夹
- **自定义解析器增强**: XPath 下标自动回退，F12 复制的路径不精确时自动尝试相邻下标
- **游戏文件夹重命名**: 设置中开启后可一键将文件夹名改为 `[ID] [类型] 标题 版本` 格式
- **快速刮削**: 游戏详情页输入链接/ID/关键词回车即可快速刮削，支持自动识别 Steam/DLsite

## 技术栈

| 技术 | 版本 | 用途 |
| --- | --- | --- |
| [Flutter](https://flutter.dev) | 3.41.9 | 跨平台 UI 框架 |
| [Dart](https://dart.dev) | 3.11.5 | 编程语言 |
| [Riverpod](https://riverpod.dev) | ^2.4.9 | 状态管理 |
| [SQLite](https://www.sqlite.org) | via sqflite_common_ffi | 本地数据存储 |
| [window_manager](https://pub.dev/packages/window_manager) | ^0.3.7 | 窗口管理 |
| [http](https://pub.dev/packages/http) | ^1.1.0 | HTTP 客户端（代理支持） |

## 项目结构

<details>
<summary>点击展开查看完整目录结构</summary>

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
│   │   ├── theme/                # 主题配置（玻璃拟态）
│   │   ├── widgets/              # 共享组件
│   │   └── pages/                # 页面模块
│   └── scraper/                  # 网页抓取器
│       ├── html_parser.dart      # HTML 解析器
│       ├── site_parsers.dart     # 站点解析器注册
│       └── xpath_evaluator.dart  # XPath 评估器
├── windows/                      # Windows 平台代码
└── pubspec.yaml                  # 项目配置
```

</details>

