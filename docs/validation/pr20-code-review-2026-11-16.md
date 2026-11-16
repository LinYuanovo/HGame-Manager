# PR #20 代码审阅与验证记录

- 日期：2026-11-16（北京时间）
- PR：<https://github.com/LinYuanovo/HGame-Manager/pull/20>
- 主分支基线：`c212e4bf27d37859cb8b945bf0a4e5ec9197f39f`
- 初始 PR 提交：`9991fca5e2ce0d9d8119c77a6cd8d8204290dee0`
- 审阅依据：实际差异、共享服务及调用方、单元测试、Windows 原生测试；PR 描述中的历史结果仅作线索。

## 审阅发现与修复

### 1. 受限重刮丢失已有翻译原文

初始实现从 `GameInfo.toJson()` 重建元数据，只继承旧 `intro`、`intro_html`，覆盖文件后会丢失 `translation.original`，详情页也无法再切换原文。

共享层现在保留正文原文及原文独占图片；新的公开标题、标签使用当前作品数据重建原文快照。自动翻译开启时只翻译新的公开字段，旧正文和原文不再重复送译。

涉及：`lib/core/services/scrape_apply_service.dart`。

### 2. 单个添加未接入图片失败回滚

初始单个 DLsite 添加使用普通下载器，公开图片下载失败后仍可能插入记录并写入 `scraped_at`。数据库未登记但目录已有元数据时，该入口还会覆盖旧简介，与批量添加行为不同。

单个 DLsite 添加现在通过 `ScrapeApplyService.applyScrapeResult`，统一字段合并、图片完整性检查、元数据保存、翻译和目录整理；失败时恢复旧文件及数据库状态。通过现有 providers 注入依赖，真实窗口测试覆盖失败、受限成功和普通作品成功。

涉及：`lib/ui/pages/games/games_page.dart`、`lib/core/services/scrape_apply_service.dart`。

### 3. 专用服务接管后丢失 HTTP 429 重试

刮削中心原先使用 `httpGetWithRetry`，初始 PR 改为专用服务直接 GET，首次 429 就会失败。

作品页和公开 API 现在共用现有重试工具及同一代理客户端，恢复限流后的重试。域名识别同时覆盖合法的尾点主机名，避免其落入通用 HTML 管线。

涉及：`lib/core/services/dlsite_service.dart`。

### 4. 不同作品的旧 HTML 被继承

旧来源与新的受限作品编号不同时，初始实现仍继承旧完整 HTML 和图片。现在在写入前检查数据库、元数据及翻译原文中的可确认 DLsite 作品编号；明确不一致则拒绝套用并保留旧数据。同作品的协议、语言及查询参数变化仍然允许。

涉及：`lib/core/services/scrape_apply_service.dart`。

## 本次验证

| 验证 | 结果 |
| --- | --- |
| 新增失败复现 | 原文备份、作品页 429、API 429、尾点域名共 4 项，修复前失败、修复后通过 |
| 针对性单元与 design token 测试 | 66 项通过 |
| 全量 Flutter 测试 | 386 项通过，串行执行 |
| Windows 共享保存、回滚、原文图片、来源校验及深浅主题 | 20 项通过 |
| Windows 在线验证 | 1 个用例覆盖 3 个真实作品，通过 |
| 真正的单个添加窗口 | 3 项通过，使用临时目录、内存 SQLite 和本地 HTTP 服务 |
| 全仓静态分析 | 0 error；446 条诊断与基线一致：18 warning、428 info，按文件、规则和消息比较零新增 |
| 差异空白检查 | `git diff --check` 通过 |

全量测试首次因 PR 工作树缺少 5 份本地 HTML 样本而失败；从主工作区复制相同样本并校验哈希后，386 项全部通过。样本属于本地既有测试资料，未加入本次提交；干净克隆执行相应用例仍需准备这些资料。

在线验证先直连，DLsite TLS 握手失败；随后通过本机 Clash 代理成功。只修改测试临时设置。实际运行结果：

| 作品编号 | 受限标记 | 图片数 | 标签数 | 简介长度 |
| --- | --- | ---: | ---: | ---: |
| RJ01684124 | `user_only` | 7 | 10 | 0 |
| RJ01622268 | `user_only` | 8 | 8 | 0 |
| RJ01678591 | 普通作品 | 17 | 15 | 2658 |

日文及其他非 ASCII 源文本在本机生成可回填占位符后交给审阅代理。修改回填到原工作树后检查占位符残留为 0。验证日志和原文映射仅留在本地临时审阅目录。

## UI 与验证边界

- 新提示的颜色、字号、间距和图标尺寸使用 `AppTheme`、`GlassConstants`；字体继承项目主题。design token 扫描及深浅主题文字对比度测试通过。
- `ScrapeMode.values` 的循环只证明共享服务在各模式下的行为；真实单个添加另有窗口操作测试。其他入口本次以调用链检查和已有测试为依据，未宣称逐一完成端到端 UI 操作。
- 在线测试通过应用自身 HTTP 客户端获取公开页面与 API；受限简介仍按不可获取处理，没有验证登录后专属正文。
- 文件快照验证覆盖可捕获异常下的恢复；进程突然退出和断电恢复不在本次验证范围。
- 本次没有新增版本或发布包。

## 复现命令

所有 Flutter 命令应在沙箱外依次执行，上一项结束后再启动下一项。

```powershell
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
flutter test --no-pub -d windows integration_test/dlsite_single_import_windows_test.dart
flutter test --no-pub -d windows --dart-define=DLSITE_LIVE_VERIFY=true --dart-define=DLSITE_LIVE_PROXY=127.0.0.1:7897 integration_test/dlsite_restricted_windows_test.dart
```

`DLSITE_LIVE_PROXY` 使用项目约定的 `host:port` 格式；省略该参数时直连。在线验证需显式启用 `DLSITE_LIVE_VERIFY`。
