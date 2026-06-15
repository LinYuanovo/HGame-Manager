<h1 align="center">黄油仓库</h1>

<p align="center">
  <b>HGame-Manager</b>
</p>

<p align="center">
  <nobr>
    <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=flat-square&logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=flat-square&logo=windows" alt="Windows">
    <img src="https://img.shields.io/badge/Version-1.3.0-blue?style=flat-square" alt="Version">
  </nobr>
</p>

<p align="center">
  <b>一款基于 Flutter 开发的 Windows 本地 HGame 管理器</b><br>
  <i>玻璃拟态设计 · 智能刮削 · 标签管理 · 收藏追踪</i>
</p>

***

## 功能特性

### 游戏管理
- **多种视图模式**：列表 / 海报墙
- **灵活排序**：标题、添加时间、最近游玩
- **分页 / 瀑布流**：两种浏览模式
- **收藏功能**：收藏游戏优先排列
- **游玩追踪**：记录游玩次数和时间

### 智能刮削
- **多站点支持**：ACG嘤嘤怪 / 飞雪ACG / 微咔ACG
- **Cookie 认证**：支持登录后刮削付费内容
- **自动整理**：刮削后按系列分类移动到整理目录
- **智能标签**：自动关联重叠标签（如"互动SLG"→"SLG"）
- **系列归一**：仅保留 RPG/ADV/ACT/SLG/AVG/FPS/TPS 七大系列

### 分类系统
- **标签 / 系列管理**：右键修改删除
- **智能重叠**：标签自动关联
- **收藏分类**：支持收藏标签和系列

### 游戏详情
- **图片轮播**：支持键盘导航
- **大图查看**：80%窗口大小的图片查看器
- **下载链接**：网盘按钮双击复制
- **解压码**：独立显示，双击复制
- **编辑模式**：可编辑版本号、标签、下载地址、解压码等

### 设置
- **代理支持**：HTTP 代理配置和测试
- **Cookie 管理**：每个站点独立 Cookie
- **忽略文件夹**：扫描和刮削分别设置
- **系列类型管理**：自定义添加系列类型
- **字体大小**：全局字体大小调整

## 快速开始

### 环境要求

- **操作系统**: Windows 10/11 (64位)
- **Flutter SDK**: >= 3.41.9
- **Dart SDK**: >= 3.11.5

### 构建运行

```bash
# 克隆仓库
git clone <repo-url>
cd HGame-Manager

# 安装依赖
flutter pub get

# 运行应用
flutter run -d windows

# 构建发布版本
flutter build windows --release
```

可执行文件位于：
```
build/windows/x64/runner/Release/hgame_manager.exe
```

## 目录结构

```
游戏库根目录/
├── SLG/                        # 按系列分类
│   └── GameName/
│       ├── source_url.txt      # 来源URL（必需）
│       ├── metadata.json       # 元数据（刮削生成）
│       └── images/             # 游戏图片（刮削下载）
└── ...
```

刮削整理后：
```
整理目录/
├── SLG/                        # 按系列分类
│   └── GameName/
│       ├── source_url.txt
│       ├── metadata.json
│       └── images/
└── 未分类/                     # 无系列标签的游戏
    └── ...
```

## 技术栈

| 技术 | 用途 |
| --- | --- |
| [Flutter](https://flutter.dev) | 跨平台 UI 框架 |
| [Riverpod](https://riverpod.dev) | 状态管理 |
| [SQLite](https://www.sqlite.org) (sqflite_common_ffi) | 本地数据存储 |
| [window_manager](https://pub.dev/packages/window_manager) | 窗口管理 |
| [html](https://pub.dev/packages/html) | HTML 解析 |
| [http](https://pub.dev/packages/http) | HTTP 客户端（代理支持） |
| [file_picker](https://pub.dev/packages/file_picker) | 文件夹选择器 |

## 项目结构

```
HGame-Manager/
├── lib/
│   ├── main.dart               # 应用入口
│   ├── core/
│   │   ├── database/           # 数据库层
│   │   ├── models/             # 数据模型
│   │   ├── providers/          # Riverpod 状态管理
│   │   ├── repositories/       # 数据访问层
│   │   ├── services/           # 业务服务
│   │   └── utils/              # 工具类
│   └── ui/
│       ├── theme/              # 主题配置（玻璃拟态）
│       ├── widgets/            # 共享组件
│       └── pages/              # 页面模块
├── windows/                    # Windows 平台代码
└── pubspec.yaml                # 项目配置
```

## 许可证

MIT License
