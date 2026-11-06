# 路由分块审阅报告

状态：逐路由审阅、21 类缺陷修复与验证已完成。基线 `5cb0e83`，所有“原位置”均以此提交为准，可用 `git show 5cb0e83:<文件> | nl -ba` 查看。审阅范围是用户操作到服务/文件/数据库的执行链，不把未测量的代码观感当成性能结论。没有声称已审完每一行或已完成 Windows 原生验收。

## 路由覆盖

| 路由/入口 | 追踪范围 | 主要发现 |
|---|---|---|
| 游戏 | 扫描、添加、批量导入、分页/封面、右键删除/搬运/启动 | 缓存错误回退、重复插入删除关联、扫描清理越界、原图缓存无限增长 |
| 分类 | 系列/自定义标签、收藏标签、删除、标签游戏列表 | build 时自动删除零关联标签；并发创建标签返回 0 |
| 收藏 | 收藏游戏/标签 → 同一 GameListWidget 和仓库 | 共享封面、缓存、搬运及标签问题同样适用 |
| 已玩 | 游玩记录、存档扫描、启动 → GameLaunchService/PlayTimeTracker | 已有进程绑定和时长单元用例；Windows 真实进程待验收 |
| 通关 | 标记/取消通关、元数据备份、目录移动、缺失目录回退 | 目录移动绕过共享服务、缓存使现存本体被误判为备份 |
| 详情 | 编辑/路径修改、攻略搜索、图片、快速/重新刮削 | 重命名写回旧路径、搬运部分写库、取消攻略搜索损坏旧图 |
| 刮削 | 扫描、并发队列、取消、API/HTML/浏览器回退、共享应用 | 取消不停止队列、卸载后 setState、凭据域名/图片跨站泄露 |
| 工具 | 工具导入、改名/路径、删除、启动 | 未证实新的数据缺陷；进程启动/插件行为未做 Windows 实测 |
| 设置/启动 | WAL 数据库、导出/云备份/导入、升级 ZIP、迁移、浮窗 | 主文件快照漏备份、未校验直接替换、TLS 证书校验关闭；部分原生覆盖欠缺 |

## A：确认的错误、安全与数据风险

1. **P1，代理关闭 TLS 验证**。原 `lib/core/utils/proxy_client.dart:147` 将 `badCertificateCallback` 恒设为 true。启用代理后，中间人证书被接受，影响登录 Cookie 与自动升级下载。真实本地自签名 TLS 服务在修复前返回成功；修复移除此回调。
2. **P1，Cookie 域名包含匹配泄露凭据**。原 `lib/core/utils/proxy_client.dart:282`、`:328` 用 `contains` 选择站点配置。`example.com.attacker.test` 与 `configured.test.attacker.test` 均可命中其他站点 Cookie。改为主机相同或其子域名，默认域名明确列举；变更域名使用现有设置配置。
3. **P1，第三方图片收到来源 Cookie**。原 `lib/core/services/scrape_apply_service.dart:167` 获取来源 Cookie 后交给下载器；原 `lib/core/services/concurrent_image_downloader.dart:99` 对任意图片 URL 直接复用请求头。真实本地 HTTP 服务收到测试 Cookie。现在跨源图片剥离 Cookie/Authorization，429 重试同样处理。
4. **P1，SQLite WAL 记录漏备份**。原 `lib/ui/pages/settings/settings_page.dart:3823`、`:4127` 直接读活动数据库主文件；`lib/core/database/database_helper.dart:38` 启用 WAL。实测数据库已有 1 条提交记录，主文件复制为 0 条。两种导出统一 `VACUUM INTO` 一致性快照，并先 flush 设置。
5. **P1，导入损坏包会先删除当前数据库**。原 `lib/ui/pages/settings/settings_page.dart:3907`、`:3923`、`:4288`、`:4310` 在校验前删除数据库；后续图片失败也不会回滚。新增共享导入服务：暂存、SQLite quick_check、表/版本/设置检查、原文件保留、回调失败回滚；维护期间阻止新数据库读取跨越替换窗口。
6. **P1，搬运“提交”不是数据库事务**。原 `lib/core/services/game_move_service.dart:123` 先改 path，再单独改图片/正文/启动器/存档。图片 UPDATE 触发器注入失败后，源目录虽然回滚，数据库仍指向新目录。现在同一事务更新全部路径字段，metadata 写入失败也触发回滚。
7. **P1，重命名把路径写回旧值**。原 `lib/core/services/folder_rename_service.dart:189` 用旧 `game.copyWith(savePath: ...)` 整行更新，覆盖之前的新 path；`:180` 生成的 relative 又以分隔符开头。实际临时目录重命名后查不到新路径记录。改为共享搬运服务，刮削整理、通关移入/移回也使用该入口。
8. **P1，目录缓存漏查导致本体被误当备份**。原 `lib/core/repositories/game_repository.dart:23` 在 30 秒缓存期内对所有未命中键返回 false。先查 A 再查实际存在的通关 B，B 的 path 被替换为 Backup；启动、删除等下游会使用错误路径。现在未命中查文件系统，搬运后失效缓存。
9. **P1，重复插入隐式删除旧游戏及关系**。原 `lib/core/repositories/game_repository.dart:430` 使用 SQLite REPLACE，路径唯一约束冲突时删除旧行及级联图片/标签，重置评分等状态。改为显式冲突失败，保留原记录；正常更新仍走 updateGame。
10. **P1，扫描清理跨库误删**。原 `lib/core/services/game_scanner_service.dart:648` 用字符串 startsWith 匹配库根，扫描 `library` 会删除失联的 `library-other` 记录。改为目录段边界判断。
11. **P1，存档保护备份失败仍覆盖**。原 `lib/core/services/backup_service.dart:250`、`:452` 忽略 createBackup 的 null，500 MiB 限制/写入失败后继续还原。两个入口均改为失败即停止。
12. **P1，还原“还原前备份”实际还原当前内容**。原 `lib/core/services/backup_service.dart:172` 删除/覆盖同名包，`:259` 才读取输入。测试 old→new→还原得到 new。现在先读入并校验待还原包，再生成保护备份；新包暂存成功才替换。
13. **P1，存档解压可沿目标链接写到目录外**。原 `lib/core/services/backup_service.dart:545` 仅做词法路径判断，`save/link/slot.dat` 的 link 指向目录外仍可覆盖。现在预检归档路径和目标祖先链接，禁止链接项并限制解压总量。
14. **P2，自定义还原重复嵌套目录**。原 `lib/core/services/backup_service.dart:495` 找到 `save/nested/slot.dat` 后以其父目录为目标，再解压 `nested/slot.dat`，写成 `save/nested/nested/slot.dat`。按完整相对后缀计算目标根。
15. **P2，并发创建标签返回无效 ID**。原 `lib/core/repositories/tag_repository.dart:85` 查询与 INSERT OR IGNORE 分离。12 个并发调用实测返回 `{1,0}`，之后外键失败。现在在事务中插入后按唯一键读取真实 ID。
16. **P2，分类页渲染删除用户标签**。原 `lib/ui/pages/categories/categories_page.dart:285` 在 build 微任务中删除所有 gameCount=0 标签，包含新建、收藏标签；刮削暂时清空关系时还可能误删。移除渲染副作用，零关联标签可显示和手动管理。
17. **P2，取消攻略搜索已删除旧配图**。原 `lib/ui/pages/games/game_detail_page.dart:2452` 在显示搜索对话框前删除 guide_*。改为先保留旧图、新下载使用 UUID 文件名，成功写入攻略后清理未引用旧图。
18. **P2，云端目录名解析取错层级、特殊文件名请求截断**。原 `lib/core/services/webdav_service.dart:586` 在去掉空路径段后仍取倒数第二段；原 `:36` 直接拼 URI，使 `#` 变成片段。实测得到父目录而非游戏目录，`slot #1.zip` 请求成 `slot `。改为最后一段与 URI pathSegments 编码，并检查远端文件名。
19. **P2，中断下载污染增量图片缓存**。原 `lib/core/services/webdav_service.dart:296` 直接写最终路径，`:205` 只要文件存在即跳过下载。改为独立暂存目录、流式下载和长度检查，完成后发布最终文件。
20. **P2，同卷移动忽略取消**。原 `lib/core/services/folder_transfer_service.dart:78` rename 快路径未查询 shouldCancel；修复在扫描后/提交前检查取消。
21. **P2，刮削取消仍出队且可并发重启**。原 `lib/ui/pages/scraper/scraper_page.dart:1119` 只修改另一个扫描 Provider，并立即清空 busy；原 `:854` 队列不读取取消。增加本地取消标志，停止新任务、保留 busy 到当前任务收尾；卸载与日志回调加保护，日志上限 1000 条。已进入 apply 的任务完成一致性写入后结束，不承诺中途回滚刮削。

## B：核心测试缺口

- `test/repositories/game_repository_test.dart:5` 的四项测试只断言方法是 Function，不能证明图片删除、排序或事务正确。本次临时 SQLite 用例补充验证，但按用户要求结束时删除临时测试；长期覆盖仍需在后续任务恢复。
- `test/services/game_move_service_test.dart:25` 原测试替身只在第一次 updateGamePath 注入失败，未覆盖“首写成功、后写失败”。本次真实 SQLite 触发器补证。
- `test/services/backup_service_test.dart:26` 仅检查目录位置和旧目录迁移，没有还原、失败保护、恶意 ZIP 或符号链接覆盖。
- `test/core/services/scrape_apply_service_test.dart` 主要验证纯函数和刮削标记，没有五入口取消、页面卸载、跨卷文件整理端到端用例。
- Windows 原生：进程探测、热键、浮窗、目录占用/杀毒软件、更新脚本、文件选择器与真实 GUI 操作，本轮未验收。
- 原始基线用例在 Linux：254 通过/11 失败，8 项缺少未入库的 web 样本，3 项硬编码 Windows 路径；报告不将其算作新增回归。

## C：维护负债

- 本次消除重命名/刮削整理/通关移入的重复目录搬运写库，将路径字段更新合并到仓库事务。
- 本次删除自建 ImagePreloader 及其调用链，交由 Flutter Image/ResizeImage 管理图片生命周期与缓存；移除 FolderRenameService 未使用 SteamService 依赖字段。
- `lib/ui/pages/games/games_page.dart:747` 与 `lib/ui/pages/games/batch_import_dialog.dart:691` 仍分别实现 Steam/DLsite 元数据保存与标签导入。整理入口已统一；后续可抽取导入服务，但不能把搜索匹配规则不加区分地合并。
- `lib/main.dart:546` 的 ErrorBoundary 从不把 `_hasError` 置为 true，不能视为有效错误捕获；`:570` 只是未触发的错误 UI。此处未做扩展性重构。
- `pubspec.yaml:12`、`:14`、`:45`、`:46` 的 `cupertino_icons`、`riverpod_annotation`、`riverpod_generator`、`build_runner` 没有在 lib 中直接引用。尚未完成生成工具/资源/传递依赖的移除构建验证，列为依赖清理候选，不声称可安全删除。

## D：有证据的性能

- 原 `lib/ui/widgets/game_list_widget.dart:387` 无限滚动从第 0 项保留至当前全部已加载项；原 `lib/ui/widgets/image_preloader.dart:39` 无目标尺寸地解码所有图片，缺少容量上限。
- 3 张 4096×4096 PNG，修复前实际 ui.Image 尺寸对应 **201326592 字节（192 MiB）**；修复后 1024×1024 对应 **12582912 字节（12 MiB）**，解码像素内存下降 **93.75%**。
- 本轮计时：旧并行预加载 519 ms，新顺序解析 853 ms。运行方式不同，不用于声称响应提速。该指标不是整个应用 RSS，也不包含 GPU/压缩字节和 Flutter 其他缓存。
- 无限滚动现在仅由 ListView/GridView 构建可见及缓存范围内 Image；Flutter 图片缓存有既有容量限制。详情原图保持独立。
- 对 SavePathService 的重复 AppData 扫描、通关 Provider 的目录遍历、SQLite 大库查询尚无真实用户负载测量，不给出“灾难/提速倍数”判断。

## 修复入口速查（当前代码）

| 修复范围 | 当前入口 |
|---|---|
| TLS/凭据域名 | `lib/core/utils/proxy_client.dart:119`、`:264` |
| 图片跨源请求头 | `lib/core/services/concurrent_image_downloader.dart:91` |
| 数据库快照/导入 | `lib/core/services/database_backup_service.dart:9`、`:20` |
| 事务搬运 | `lib/core/repositories/game_repository.dart:484`、`lib/core/services/game_move_service.dart:120` |
| 重命名/整理共用 | `lib/core/services/folder_rename_service.dart:149`、`lib/core/services/scrape_apply_service.dart:263` |
| 路径缓存/并发标签 | `lib/core/repositories/game_repository.dart:24`、`lib/core/repositories/tag_repository.dart:89` |
| 存档校验/解压 | `lib/core/services/backup_service.dart:253`、`:558`、`:578` |
| 下载完整性/URI | `lib/core/services/webdav_service.dart:32`、`:302` |
| 分类保留空标签 | `lib/ui/pages/categories/categories_page.dart:272` |
| 攻略搜索保护 | `lib/ui/pages/games/game_detail_page.dart:2447`、`lib/ui/pages/games/guide_search_dialog.dart:170` |
| 刮削取消 | `lib/ui/pages/scraper/scraper_page.dart:1134` |
| 封面内存 | `lib/ui/widgets/game_list_widget.dart:1770` |

## 验证及限制

使用 Linux Flutter 3.41.9/Dart 3.11.5、实际 SQLite FFI、隔离临时目录、本地 HTTP/TLS 服务。未触碰真实游戏库、登录态或外部云盘；没有 Windows 原生软件验收。所有 Flutter/Dart 命令串行。

- 原始基线：254 项通过、11 项失败。
- 最终全量：278 项通过、11 项失败；两次失败名称逐项比对完全一致。
- 本次 24 项临时验证全部通过：缓存、标签并发、重命名、后续写库失败回滚、同卷取消、路径替换反证、两种还原保护失败、还原保护备份本身、链接逃逸、云端目录名、特殊文件名、真实图片解码、WAL 快照、重复插入保留、跨库扫描、非法数据库拒绝、图片阶段失败恢复库/设置、网络中断及重试、嵌套存档、Cookie 主机边界、TLS 校验、图片跨源凭据、分类页 Widget。
- TLS 测试用 OpenSSL 生成一次性自签名证书，HTTP/TLS 只监听回环地址。显式撤销测试绑定的 HTTP 拦截后重测，确保没有把模拟 400 响应当成安全验证成功。
- 现有测试执行方式：`rg -l 'package:flutter_test/flutter_test.dart' test -g '*_test.dart'` 收集真正的 Flutter 测试，再以 `flutter test --no-pub --concurrency=1 --reporter=expanded` 串行运行；仓库内若干名为 `_test.dart` 的联网调试脚本不属于此集合。
- 原始分析 513 项诊断（0 error、20 warning、493 info）；最终清理后 509 项（0 error、18 warning、491 info），产品改动未新增诊断。
- 原始失败清单：刮削编号映射 2 项 Windows 路径；DLsite 3 项缺少 `web/dlsite1.html`/`dlsite2.html`；富文本 5 项缺少 `web/acgyyg`/`web/feixueacg`/`web/vikacg` 样本；更新 ZIP 1 项 Windows 路径断言。

临时回归代码和生成文件已按用户要求移除，结果保留于本文。现有搬运测试只调整仓库替身以适配新事务接口，没有删除原项目测试。长期自动回归覆盖仍有 B 节所述缺口。

快照 API 的依据：[SQLite VACUUM INTO 文档](https://www.sqlite.org/lang_vacuum.html)（通过 Context7 查询），其输出是活动数据库的一致性快照。此结论另外由实际 WAL 用例验证。

修复不能提供跨 SQLite/文件系统的断电原子性。文件搬运遇到进程中止或外部并发修改仍需恢复日志机制；现有目录传输按大小/数量校验，不等同内容哈希验证。存档还原中磁盘写入失败可能留下部分新文件，但保护备份已成功保留；后续可扩展逐文件暂存和回滚。

兼容性变化：代理仍要求可信 TLS 证书；新论坛域名需显式配置后才携带 Cookie；跨源图片不携带来源凭据；重复游戏路径导入报错而不覆盖；含链接或超过解压大小限制的存档会拒绝还原。依赖没有升级，版本号没有修改。

产品修复本地提交：`dfc1da3`。本轮未推送、未合并主分支、未生成新发布包。临时源码/夹具/日志/缓存已清理，工作树保留供评审。
