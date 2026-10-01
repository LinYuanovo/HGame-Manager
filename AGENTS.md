# Git 提交规则

## 默认行为
- 所有 `git commit` 操作仅限本地提交
- **禁止**自动执行 `git push` 推送到远程仓库
- **禁止**自行变更版本号
- 只有当用户明确说"提交到 GitHub"或"推送到远程"时，才执行 `git push`

## 示例
- ✅ `git add -A && git commit -m "xxx"` — 允许
- ❌ `git push origin master` — 禁止（除非用户明确要求）
- ❌ `git push` — 禁止（除非用户明确要求）
- ❌ `自行变更版本号` — 禁止（除非用户明确要求）

# 项目了解规则

## 新任务启动
- 开始新任务前，先读取 `ARCHITECTURE.md` 了解项目结构和技术栈
- 快速掌握项目整体架构后再进行具体开发

# GitHub CLI

- 本机已安装 `gh`（GitHub CLI）
- 查询 CI 状态、失败日志、管理 Release 时优先使用 `gh run list` / `gh run view --log-failed` / `gh release`，不要裸调匿名 GitHub API（有速率限制）
- `gh` 命令涉及网络访问，需在沙箱外（提权）运行

# 交流规则

## 讨论
- 回答或编写文档和注释时，必须使用中文

# 暗黑模式开发规范

## 禁止硬编码颜色

在 UI 代码中，**禁止**直接使用以下硬编码方式：

```dart
// ❌ 错误示例
Color(0xFFFFFFFF)
Colors.white
Color(0xFF374244)
Colors.grey
```

## 正确做法

使用 `AppTheme` 提供的动态获取方法：

```dart
// ✅ 正确示例
AppTheme.getSurfaceColor(context)      // 表面色（白/深灰）
AppTheme.getTextPrimary(context)       // 主文字色
AppTheme.getTextSecondary(context)     // 次要文字色
AppTheme.getBorderColor(context)       // 边框色
AppTheme.getBackgroundColor(context)   // 背景色
AppTheme.getCardColor(context)         // 卡片色
AppTheme.getPrimaryColor(context)      // 主题色
AppTheme.getFavoriteColor(context)     // 收藏红
AppTheme.getStarColor(context)         // 星级金
```

## 特殊颜色

对于语义颜色（成功、警告、错误），直接使用 AppTheme 常量：

```dart
AppTheme.successColor   // 绿色
AppTheme.warningColor   // 黄色
AppTheme.errorColor     // 红色
AppTheme.warningOrange  // 橙色
```

## 透明色

`Colors.transparent` 不需要主题适配，可以直接使用。

## 白色前景色

按钮、图标等白色前景色（如 `Colors.white`）通常保持不变，因为：
- 浅色模式：白色按钮上的白色文字
- 深色模式：深色按钮上的白色文字

但如果背景色是动态的，需要确保对比度足够。

## Flutter 测试执行规则

- Flutter 测试必须串行执行，禁止并行启动多个 `flutter test`、`flutter analyze` 或 Dart 测试进程，避免工具链互相等待导致卡住超时。
- 多组测试需要按顺序逐条执行；上一条命令结束后再执行下一条。
- 所有 `flutter` / `dart` 命令必须在沙箱外（提权）运行：Flutter 工具启动时需读写 `C:\flutter\bin\cache\lockfile`，沙箱内无写权限，`flutter.bat` 会静默无限重试导致命令永久挂起且无任何输出。若命令超过 1 分钟无输出，不要等待，直接提权重跑。

# 刮削入口一致性规范

## 五种刮削方式
- **快速刮削**：`game_detail_page.dart` `_quickScrape`（详情页顶部输入 URL/ID 回车）
- **重新刮削**：`game_detail_page.dart` `_rescrapeGame`（详情页刷新按钮，用已有来源重抓）
- **刮削中心**：`scraper_page.dart` `_scrapeSingleGame`（刮削页批量刮削）
- **单个添加**：`games_page.dart` `_CloudImportDialog`（Steam/DLsite 搜索导入）
- **批量添加**：`games_page.dart` `_BatchImportDialog`（Steam/DLsite 搜索导入）

## URL 刮削三入口（快速/重新/刮削中心）共享处理管线
- 获取 html/GameInfo 由各入口自行负责（维咔 API 优先 → `httpGetWithRetry` → Cloudflare 挑战回退内置浏览器 → XpathParser 客户端渲染二次渲染）
- 拿到 GameInfo 后**必须**单次调用 `ScrapeApplyService.applyScrapeResult(...)` 完成：字段合并（含标题去版本）→ 写 metadata.json 与 source_url.txt → `syncTags` → `downloadAndApplyImages`（下载/重写/修复/清理）→ `organizeFolder`（按 `ScrapeModeConfigs` 重命名/移动）
- **禁止**在入口内私写字段合并、标签循环、图片下载重写、目录移动代码；单个/批量添加的整理也必须走 `organizeFolder`
- 新增刮削处理时：先扩展 `ScrapeApplyService`（或 `lib/scraper/`），再在同一次改动中让所有适用入口经由共享层生效
- 提交前对照本清单自检五种入口行为一致性

## 开发规则
- 新增或修改任何刮削处理（字段映射、标签、图片、兜底、重试等）时，先落到共享层（`ScrapeApplyService` 或 `lib/scraper/`），再在同一次改动中对齐所有适用入口；**禁止**只改单个入口造成"有的地方有、有的地方没有"
- 单个/批量添加目前仅 Steam/DLsite 通道；若未来支持站点 URL 刮削，必须复用上述共享管线
- 提交前对照本清单自检五种入口行为一致性
