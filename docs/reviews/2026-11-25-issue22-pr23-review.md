# Issue #22 / PR #23 审阅记录

审阅日期：2026-11-25；旧配图确认流程更新：2026-11-26。

- 问题：[issue #22](https://github.com/LinYuanovo/HGame-Manager/issues/22)。
- 修复：[PR #23](https://github.com/LinYuanovo/HGame-Manager/pull/23)。
- 远程基线：`master` 的 `e96033d`；PR 提交：`0b3f19a`。
- 使用场景：Windows 单用户桌面应用，共享图片下载器默认并发 3。

## 结论

PR 正确区分了源站缺图与下载失败：404/410 记录包含 URL 和状态码的警告并跳过，其他 HTTP 错误、空响应和请求异常仍视为失败。严格保存继续依赖共享快照恢复文件与数据库；缺图后的编号沿用原始位置。

发现并修复一处 P2 问题，完成专项回归与 Windows 原生集成验证，具备合并条件。

## 发现与修复

### P2：全部配图缺失时，旧编号图会在扫描后重新入库

触发条件：已有游戏存在旧编号图，例如 `scrape_1.jpg`；重新刮削后的全部图片返回 404/410，且旧图已无正文或攻略引用。

原实现会将数据库图片列表置空，但 `ScrapedImageFileCleaner` 在保留列表为空时直接返回，旧图仍留在磁盘。`GameScannerService` 随后枚举管理器图片目录，把这些旧图重新写回数据库，导致保存结果在扫描后改变。

`downloadAndApplyImages` 在存在可用图片，或全部 URL 均确认为源站缺图时，收集未引用的旧编号图，交由入口显示“保留旧图 / 删除旧图”确认框。保留会同时保存文件和图库记录；明确选择删除后才移除对应文件。关闭、Escape、遮罩关闭或没有确认器时默认保留。正文引用、攻略引用和手动图片继续受到保护；没有可用图片且仍有下载故障时保留旧文件。

回归通过本机 HTTP 404、真实文件、SQLite 与实际扫描链路验证。保留和删除两种选择在保存与再次扫描后保持一致。保留的旧图继续出现在图库中，正文的远程 URL 替换仅使用本次刮削的图片集合。

原有失败回滚用例也补入成功下载、旧图片和旧标签，覆盖 403、503 与 HTTP 200 空响应，确认失败时恢复元数据、图片、标签并保留下载期间新增的游玩时长。

## 调用链核对

| 入口或阶段 | 实际路径与结论 |
| --- | --- |
| 快速刮削、重新刮削 | `game_detail_page.dart` → `applyScrapeResult` → `downloadAndApplyImages`；沿用现有宽松保存策略，共享缺图识别与清理修复。 |
| 刮削中心 | 候选结果 → `ScrapeReviewService.apply` → `applyScrapeResult(requirePersistence: true)`；缺图允许保存，其他下载故障回滚。 |
| 单个 DLsite 添加 | `games_page.dart` 的 `_importDlsite` → 同一严格保存管线。 |
| 批量添加 | `batch_import_dialog.dart` 生成候选 → 审核保存 → 同一严格保存管线。 |
| 下载与引用 | `ConcurrentImageDownloader` 保持原始文件编号；引用修复使用本次刮削的图片集合，保留旧图独立追加到图库。 |
| 文件与数据库回滚 | `ScrapeFileSnapshot` 配合 `restoreScrapeSnapshot` 恢复刮削数据；游玩数据独立保留。 |
| 旧图确认与扫描 | 三个直接保存入口及审核确认链路共用 `confirmScrapedImageCleanup`；`GameScannerService` 再次扫描后保持用户选择的结果。 |

## 验证结果

2026-11-26 验证环境为 Flutter 3.41.9 / Dart 3.11.5。所有 Flutter / Dart 命令串行执行。

| 验证 | 结果 |
| --- | --- |
| `scrape_review_merge_test`、`scrape_apply_service_test`、`scraped_image_file_cleaner_test`、`scraped_image_cleanup_dialog_test`、`scrape_review_tokens_test`、`design_token_usage_test` | 共 56 项通过，包含确认选择、默认保留、引用映射、再次扫描和深浅色大字号布局。 |
| Windows `dlsite_single_import_windows_test` | 7 项通过，包含取得新图和全部缺图后的保留、删除选择。 |
| Windows `dlsite_restricted_windows_test` | 22 项通过。 |
| Windows `scrape_review_windows_test` | 2 项通过，覆盖审核保存中的保留、删除确认，并检查深浅色弹窗截图。 |
| Windows `image_refresh_windows_test` | 4 项通过，包含 429 重试后的原图与省内存封面刷新。 |
| 修改文件格式化、`git diff --check` | 通过。 |
| 修改文件定向静态分析 | 无编译错误；新弹窗和确认流程无诊断，剩余提示位于既有代码。 |
| 远程 PR 格式 CI | `0b3f19a` 的检查成功。 |

HTTP 故障验证使用本机服务器和隔离的临时目录；本次未重新请求 issue 中的线上商品页面与图片。原生集成测试验证实际 Windows 应用中的导入、审核、受限正文保护及图片缓存刷新。
