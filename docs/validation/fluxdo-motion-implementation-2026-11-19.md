# FluxDO 动效适配实施与验证

实施分支：`codex/fluxdo-motion-plan`。基线：`f02df84`。页面设计和 38 项入口映射见[逐页计划](../development/fluxdo-motion-page-plan.md)。

## 用户可见的主要变化

- 侧栏、设置分区和五种刮削配置用同一个选中面移动到目标；连续点选可以改向。
- 游戏列表和海报保留正在操作的游戏，可见封面随布局变化移动。详情、正文图片和攻略浮窗使用同源图片开合，翻图后返回当前图片。
- 导入完成可按 ID 回到库中，批量结果保留每项路径和状态，可筛出失败项。刮削中心可以循环定位失败任务，并暂停或恢复日志跟随。
- 收藏写入完成后才退出，邻卡补位；失败保留原项。已玩与通关刷新后保留多选，扫描结果持续显示。
- 图片管理支持真正拖排，封面跟随图片身份。取消删除编辑保留原文件；保存图片顺序和封面使用同一数据库事务。
- 评分区支持悬停预览与键盘半星调整；Markdown 往返保留编辑实例、选区与焦点。攻略搜索允许改选其他候选，迟到正文不会覆盖新选择。
- 存档和云备份在目标行显示操作状态，失败原因保留；下载、备份与还原完成后能找到对应记录。设置子窗返回时突出原行，设置关闭重开恢复分区与阅读位置。

## 代码检查中修复的交互问题

- 视图切换原先总回到第一页；现在按目标 ID 计算新页，网格容量变化时再次校准。
- 同一滚动控制器曾在翻页重建期间挂载两处；滚动通知处理改为从实际滚动位置读取，定位只在单一挂载时执行。
- 图片飞行期间清理缓存会释放渲染图像；飞行层独立持有克隆引用，并在退出后释放。
- 详情中的大图与详情本身使用可配对的页面路由，退出结束后再交接状态。连续 Esc 每次只退出一层。
- 分类长标题受到实际工具栏宽度约束；键盘返回后可以再次激活原卡。
- 图片拖排用稳定路径识别封面，编辑中的删除在确认保存后才处理受管理的文件。
- 本地存档及云端备份操作互斥；云端还原明确展示目标和确认动作。旧列表在刷新期间保持可见。

## 自动化范围

离线回归共 **283 项通过**（`build/fluxdo-closure-offline.log`）。Windows 图片/设置/本地导入完整交互链通过（`build/fluxdo-complete-native-flow-r2.log`）；刮削失败队列专项通过（`build/fluxdo-closure-scraper.log`）。最终主路由、六个设置分区及共享弹窗浅深主题回归通过两项、覆盖 **166 个界面状态**（`build/fluxdo-closure-native.log`）。本轮修改文件静态分析 **0 个错误**（`build/fluxdo-final-analysis.log`），`git diff --check` 通过；静态分析仍含基线的警告和提示。

`test/ui/widgets/motion_flow_test.dart` 覆盖图片翻页配对、来源离屏、途中关闭、运行中减少动效、布局飞行中断与卸载、列表补位期间文本编辑状态、离屏长列表定位、Markdown 中文选区和评分输入。

`test/ui/widgets/library_motion_test.dart` 覆盖导入 ID 先于新数据到达、分页视图往返、收藏写入失败与成功按 ID 移除、同名分类、长标题，以及刷新后的多选身份。

`test/ui/widgets/sidebar_motion_test.dart` 直接核对绘制中的选中矩形，覆盖中途改向、自定义排序、折叠、隐藏项及减少动效接管。攻略搜索另有改选候选与迟到正文回归。

`integration_test/fluxdo_motion_flow_test.dart` 在 Windows 原生窗口生成本地样例，完成以下操作：

1. 定位到库中后续页的游戏，切海报后打开详情。
2. 由图片 A 打开查看器，切到 B，以滚轮放大，按 Esc 退回详情，再按 Esc 返回原游戏。
3. 拖排图片，核对封面仍属于原图；确认保存后从数据库重新读取顺序与封面。
4. 打开指定设置项，再普通打开设置、切换分区并滚动，关闭重开核对位置。
5. 从隔离文件夹真实执行“不刮削”批量导入，在结果行点击“在游戏库中查看”，核对返回 ID 对应已写入目录。

`integration_test/scraper_result_motion_test.dart` 使用 12 个隔离目录，在本地处理阶段模拟失败，验证连续失败定位、可见目标、日志阅读位置保留和恢复跟随到底。

`integration_test/design_tokens_exe_test.dart` 在空的构建数据目录串行运行浅深主题、主路由、设置六分区、管理子窗、等待与错误状态等 166 个界面状态。

## 原生证据与边界

原生专项输出到测试程序的 `hgame_manager_data/motion-evidence/`，包括详情展开途中、放大图、返回游戏、图片重排和设置定位截图，以及 `debug-frame-times.json`。最终证据保存在 `build/validation/fluxdo-motion-final-evidence/motion-evidence/`；先前样例与截图保存在 `build/validation/fluxdo-motion-evidence-20261119-190738/`。两次归档都用于给全页回归留出空的构建样例库。

帧时间记录来自 Debug 构建，覆盖建立页面和交互阶段，因此保留冷启动与重建峰值。它用于检查具体卡顿来源，不代表 Release 的显示 FPS、VRR 或多屏呈现表现。查看器开合、图片拖排、数据库保存与本地导入已执行原生链路；线上 Steam/DLsite、WebDAV 账户、第三方程序启动以及跨显示器和系统热键冲突仍需相应真实环境验证。

完整交互链记录了 578 帧。UI build 的中位数为 0.305 ms、P95 为 11.079 ms、最大值为 287.618 ms；raster 的中位数为 0.845 ms、P95 为 3.868 ms、最大值为 79.231 ms。由于这组记录包含 Debug 冷启动、页面建立、截图读取和导入操作，不能据此断言全程达到某个刷新率。

## 复跑

Flutter/Dart 依仓库规则在沙箱外串行运行。全页原生测试需要空的构建样例目录；保留已有截图后再运行。

```powershell
flutter test --no-pub --concurrency=1 test/ui test/core test/services test/utils test/unit test/repositories test/forum_domain_utils_test.dart test/proxy_client_headers_test.dart
flutter test --no-pub integration_test/design_tokens_exe_test.dart -d windows --reporter expanded
flutter test --no-pub integration_test/fluxdo_motion_flow_test.dart -d windows --reporter expanded
flutter test --no-pub integration_test/scraper_result_motion_test.dart -d windows --reporter expanded
```
