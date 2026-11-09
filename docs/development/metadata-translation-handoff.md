# 刮削元信息自动翻译交接

更新日期：2026-11-10

## 工作位置

- 基线：`18d954d`（`master`）
- 分支：`codex/metadata-translation`
- 工作树：`C:\Users\Administrator\.codex\worktrees\metadata-translation\HGame-Manager`
- 计划：`docs/development/metadata-translation-plan.md`

## 当前进度

功能实现完成，扩展回归 159 项通过，Windows 原生集成 4 组通过。主工作区保持干净，任务代码保留在独立分支与工作树，尚未提交。

Google 实际外网请求已执行：直连超时，本机代理出口触发 Google 验证码，正确提示失败并保留原文；没有取得外网成功翻译的验收证据。OpenAI 兼容协议采用本地真实 HTTP 服务验证，没有使用外部 LLM 凭据进行推理验证。

## 已确认调用路径

- URL 三入口：`game_detail_page.dart` 的 `_quickScrape` / `_rescrapeGame`，`scraper_page.dart` 的 `_scrapeSingleGame` → `ScrapeApplyService.applyScrapeResult`。
- 单个导入：`games_page.dart` 的 `_importSteam` / `_importDlsite` → `_saveImagesAndMetadata` → `_postImportProcess` → `translateGameMetadata` → `organizeFolder`。
- 批量导入：`batch_import_dialog.dart` 对应导入方法 → `_saveImagesAndMetadata` → `_postImportProcess` → `translateGameMetadata` → `organizeFolder`。
- 元数据路径由 `GameDataPaths` 管理，详情页从元数据加载富文本；可在该层保存原文快照。
- 当前会话没有提供可调用的 Hy Memory 查询工具；已按实际源码继续核对。

## 验证结果

| 验证 | 结果与范围 |
| --- | --- |
| 首轮定向测试 | 46 项通过，包含翻译成功、格式错误、401/429、截断、超时、完整兜底、双失败、长文本及原文完整性。 |
| 扩展回归 | `flutter test --no-pub --concurrency=1 --timeout=60s test/core test/ui test/unit test/utils test/proxy_client_headers_test.dart`，159 项全部通过，含俄语/阿拉伯语 Unicode 文字识别。 |
| 受影响文件静态检查 | 0 error、7 warning、119 info；与未修改主工作区逐项归一化对比，126 条诊断完全相同，没有新增。分析器因既有诊断返回非零，不能表述为全项目零告警。 |
| Windows 原生共享流程 | 真实本地 HTTP、SQLite、图片下载、元数据写入；五种模式的共享处理均验证译文和原文。单个/批量导入验证的是实际共用处理方法，未通过真实 Steam/DLsite 导入对话框逐个完成远程抓取。 |
| 目录与重载 | 真实移动游戏目录后，原文中的本地图片路径同步重写；重扫游戏库后译文和原文仍可加载。 |
| Windows 原生 UI | 浅/深色主题下切换原文、译文，检查标题/正文/标签；切换不增加请求次数且数据库保持译文。验证设置菜单入口、两种服务选择、测试连接、保存和完整多行提示。 |
| 视觉检查 | 8 张原生渲染截图已目视检查：浅/深色各包含详情原文、详情译文、LLM 设置、Google 设置。 |
| 真实外网 | 成功取得 Steam 620 的公开英文元数据；Google 直连超时，代理出口返回验证码跳转。程序保留 125 字符的原始简介并显示失败提示。成功翻译路径由响应样本验证，外网成功路径待可用网络复验。 |
| LLM 兼容协议 | 原生进程向本地真实 HTTP 服务发送标准 Chat Completions 请求，验证模型、鉴权、JSON 返回、503 降级及全部失败；本地响应是受控测试响应，不代表外部模型翻译质量。 |

原生测试命令为 `flutter test integration_test/metadata_translation_exe_test.dart -d windows --no-pub --timeout=5m --dart-define=TRANSLATION_EVIDENCE=<任务临时目录>`。按用户清理要求，新增测试入口与其产物在验收后移除；上述命令记录本次执行范围。

构建过程的本机约定：

- Flutter/Dart 始终在沙箱外串行执行。系统 `dart` 命令指向未配置版本的管理器，格式化使用 `C:\flutter\bin\cache\dart-sdk\bin\dart.exe`。
- 媒体依赖下载失败后复用本机缓存，先校验插件要求的 MD5：mpv 为 `a832ef24b3a6ff97cd2560b5b9d04cd8`，ANGLE 为 `e866f13e8d552348058afaafe869b1ed`。
- CMake 首次配置失败后重试前必须显式设置 `CMAKE_INSTALL_PREFIX`，确保指向当前工作树的构建输出目录。

## 实现决策

- `MetadataTranslationService` 对完整元数据进行翻译，只在所有文字成功后生成结果；失败时返回原对象，避免半份译文覆盖原文。
- `ScrapeApplyService.translateGameMetadata` 在图片本地化后、目录整理前保存译文和原文。原文位于 `translation.original`，复用现有元数据文件及路径重写，不增加数据库字段。
- LLM 通过标准 Chat Completions 消息协议请求；Google 通过免密钥网络接口逐块处理。两者使用独立请求客户端和超时，Google 请求不携带 LLM 密钥。
- 详情切换只影响显示；编辑时回到保存的译文。长失败提示允许完整换行显示。
- 新 UI 使用已有主题色、文字样式、间距和圆角令牌。

## 清理情况

已清除本次新增测试源文件、`.tmp_translation`、8 张截图、测试日志、隔离数据库、`build`、`.dart_tool`、`windows/flutter/ephemeral` 和未跟踪的 Flutter 生成配置；已还原两份受跟踪的插件注册生成文件。原生测试创建的 `hgm_translation_native_*` 样本目录已由测试清理，未发现残留。主工作区仍干净，任务工作树仅保留功能源码和计划、交接、使用说明；分支和工作树保留供审阅。

系统目录误写不包含在上述清理中，其恢复需要下节所述确认。

## 系统目录误写与修复待确认

首次 CMake 配置在媒体依赖下载失败时中断，默认前缀 `C:/Program Files/hgame_manager` 留在缓存中；随后重试构建把 Debug 测试运行文件装入了该目录。该目录创建于 2026-06-20，属于已有目录，因此不能递归删除。已修正本任务缓存，后续安装清单均指向工作树 `build/windows/x64/runner/Debug`。

已核对该系统目录的 20 个顶层运行文件，它们均与本次 Debug 构建对应文件哈希相同；其中一部分媒体库原本已存在且内容相同。`data/flutter_assets` 被重新写入测试资源，目录内没有 `app.so`。没有事前文件快照，无法证明或精确还原原来的程序版本，不能声称已恢复。当前不应启动该目录中的程序。

已准备的候选修复来源是主工作区现有的完整 v1.5.5+36 Release 构建：

- 来源：`E:\Programs\Trae Projects\HGame-Manager\build\windows\x64\runner\Release`
- 程序 SHA-256：`C0C732EDEBFFEF4FFA012A6480B3A671EA613382015ACA359A68B75760886066`
- `data/app.so` SHA-256：`C753131FDFE6D2399FB4D53100ED2058AC138A4D3E416075D5DFEF02EE20544D`
- 每个受影响顶层文件都有对应的 Release 文件。

建议获得用户确认后：先备份系统目录现状，再用该 Release 的运行文件和资源修复；保留目录内其他文件与用户数据，校验复制后哈希。这属于修复已有程序目录的操作，需要用户确认具体版本；本次没有自行执行。
