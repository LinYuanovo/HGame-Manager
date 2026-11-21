# 从源码构建

## 环境要求

- **Flutter SDK**：>= 3.41.9
- **Dart SDK**：>= 3.11.5
- **操作系统**：Windows 10 / 11（64 位）
- **Visual Studio 2022 / Build Tools**：安装「使用 C++ 的桌面开发」、MSVC 和 Windows SDK
- **NuGet CLI**：加入 PATH，供 Windows WebView 插件构建使用
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

运行或分发时保留整个 `Release/` 目录中的 DLL 和 `data/`，不能只复制 EXE。内置浏览器依赖 WebView2 Runtime。

## 版本与更新日志

应用版本以 `pubspec.yaml` 的 `version` 为准，格式为 `主版本.次版本.修订号+构建号`。沿用项目惯例，小版本修复同时递增修订号和构建号，并在 `CHANGELOG.md` 顶部添加对应的 `## v版本 (日期)`。

应用包与文档站读取源码版本；README 徽章显示 GitHub 已发布版本。`package.json` 的版本仅属于文档站工具包，不与应用版本同步递增。

## Windows Debug EXE 验证

以下命令会构建并运行真实 Windows Debug 应用，不依赖桌面操作工具。必须串行执行，上一条完成后再运行下一条：

```powershell
flutter test integration_test/image_refresh_windows_test.dart -d windows --no-pub --reporter expanded
flutter test integration_test/webdav_download_windows_test.dart -d windows --no-pub --reporter expanded
```

- 封面测试检查共享刮削和下载重试覆盖同路径图片后，列表实际渲染是否更新。
- WebDAV 测试检查普通 / gzip 完整下载和中断保护。
- 两组用例使用临时目录与本地 HTTP 服务。已有 `move_folder_exe_test.dart` 另需 SMB 目标配置，并启动完整应用；运行它前应使用隔离构建目录和应用数据，避免加载已有游戏库。
- 普通单元 / 组件测试也应串行运行；`test/` 中混有联网调试脚本，不能把所有同名文件都当成 Flutter 测试。部分旧解析器测试依赖未入库的 `web/` 样本。
- `flutter analyze --no-pub` 目前存在既有 warning/info；应核对新增诊断，不能把非零退出码直接视为编译失败。

## 文档站验证

使用 Node.js 22（与文档部署工作流一致）：

```bash
npm ci
npm run docs:build
```

构建输出在 `docs/.vitepress/dist/`；`npm run docs:dev` 可启动本地预览。合并或提交本身不会发布应用，发布工作流由版本标签或手动操作触发。

文档站在相关改动推送到 `master` 后才由 GitHub Actions 部署，本地构建不会更新线上页面。源码中的版本号变更也会触发部署。`docs/reviews/`、`docs/work/` 和 `docs/superpowers/` 属于历史审阅或工作记录，留在仓库中，不发布为使用指南，也不进入站点搜索。

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
│   │   ├── controllers/          # UI 控制器
│   │   ├── windows/              # 攻略浮窗
│   │   ├── theme/                # 主题配置（玻璃拟态）
│   │   ├── widgets/              # 共享组件
│   │   └── pages/                # 页面模块
│   └── scraper/                  # 网页抓取器
├── docs/                         # 文档站与历史审阅记录
├── test/                         # 单元和组件测试
├── integration_test/             # Windows 原生集成测试
├── windows/                      # Windows 平台代码
└── pubspec.yaml                  # 项目配置
```
