# 从源码构建

## 环境要求

- **Flutter SDK**：>= 3.41.9
- **Dart SDK**：>= 3.11.5
- **操作系统**：Windows 10 / 11（64 位）
- **内存**：建议 8GB+
- **磁盘空间**：2GB+（含构建缓存）

## 构建步骤

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

构建产物位于：

```
build/windows/x64/runner/Release/hgame_manager.exe
```

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

更详细的架构说明请查阅仓库根目录的 [ARCHITECTURE.md](https://github.com/LinYuanovo/HGame-Manager/blob/master/ARCHITECTURE.md)。

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
├── windows/                      # Windows 平台代码
└── pubspec.yaml                  # 项目配置
```
