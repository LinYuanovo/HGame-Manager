# 动效与加载逐页复审

日期：2026-11-10。目标：`codex/motion-loading`，基线提交 `15e141a` 及该工作树已有的动效改动。

## 已修正的问题

1. **切页重建退出页面**：切换器只给退出内容增加包装，导致原页面先销毁再重新初始化，丢失退出画面中的临时状态并重复加载。当前页和退出页现在使用相同的包装结构和稳定键，切页只改变输入、焦点、语义与 Ticker 开关。回归用例直接验证初始化次数、页面内计数及最终销毁次数。
2. **切换中开启减少动效仍保留旧画面**：设置生效后立即移除退出内容，当前页直接呈现。
3. **标签指示条立即切换但内容仍滑动**：Flutter 的 `TabBarView` 单独读取 `TabController.animationDuration`。共享控制器现在同时提供动态时长；分类、收藏、右键菜单管理和五种刮削行为配置统一生效。
4. **取消入场动画后仍等待定时器**：`AppEntrance` 响应 `animate` 更新，取消延迟并立即开放内容与点击。
5. **游戏加载列数与真实布局不一致**：骨架读取实际布局 Provider，关闭固定列数时显示三列，开启时遵循二至八列边界，并跟随封面比例更新。
6. **图片占位不完整**：补齐详情正文、文章图片、插入图片选择和封面选择入口；共享占位在有高度约束时填满显示区域，正文未获得图片尺寸时使用有限高度，缓存命中直接显示。
7. **云端备份可重复刷新**：加载期间禁用刷新按钮，完成后恢复，防止连续请求交错覆盖结果。
8. **单个导入遮掉已有搜索结果**：骨架只在等待首批结果时显示；导入过程中保留已有结果和选中项，沿用状态文字与按钮上的处理指示。
9. **Markdown 预览缩成窄栏**：原生截图复核发现预览内容居中缩窄。测量测试复现 700px 区域仅剩 89px，切换内容现在填满原显示区域，编辑文本同时从顶部对齐，使编辑与预览起点一致。
10. **减少动效时浅色骨架过淡**：静态骨架采用低透明度动态主色，让等待结构在浅色背景上更容易辨认。

## 检查范围

按 Windows 单用户桌面应用检查。覆盖主窗口和侧栏、刮削、游戏库、分类及其游戏列表、收藏、已玩、通关、工具、设置六分区、详情、单个和批量添加、存档和云备份、攻略搜索、图片管理、Markdown、更新与移动进度、浏览器验证、攻略窗口。

所有本地与网络图片入口均核对等待与失败处理；现有确定进度继续使用业务进度。保留短淡入、首屏交错、悬停和滚动动效，修正状态切换及辅助功能行为。

## 可复验检查

新增正式用例：`test/ui/theme/app_motion_test.dart`、`test/ui/widgets/app_loading_test.dart`。已有 `integration_test/design_tokens_exe_test.dart` 扩展为逐页状态验收，支持通过 `UI_TOKEN_EVIDENCE` 输出截图。

初始五个针对性用例均先失败再修复通过，分别复现退出页重复初始化、减少动效中途生效、取消延迟入场、骨架列数不一致及图片占位尺寸不足。后续用例另外复现了标签页内容继续滑动和云备份重复刷新。

最终完整回归 **258 项通过**，其中包含本轮保留的 13 项动效与加载用例。按顺序执行：

```powershell
flutter test test/core test/ui test/unit test/utils test/services test/repositories test/proxy_client_headers_test.dart test/forum_domain_utils_test.dart test/play_time_tracker_test.dart --reporter expanded
flutter test integration_test/design_tokens_exe_test.dart -d windows --dart-define=UI_TOKEN_EVIDENCE=C:/Users/Administrator/.codex/worktrees/hgame-motion/HGame-Manager/build/motion_review/screenshots --reporter expanded
flutter analyze --no-pub
```

第一轮 Windows 原生验收通过 121 个状态，逐页复核截图后发现并修正 Markdown 预览宽度及静态骨架辨识度问题。最终代码重新构建，**127 个状态通过**，捕获 Flutter 异常为零；对修正区域、工具卡片、收藏分类与攻略图片另作原图复核。

原生状态覆盖七个主页面、分类与收藏第二标签页、游戏列表模式、设置六分区顶部和底部、详情及各配置弹窗、Markdown 编辑和预览、减少动效及攻略窗口页面。游戏、分类、收藏、已玩、通关和工具另覆盖等待、空态、失败；工具和收藏分类使用有内容样本。

最终分析 **0 error、19 warning、434 info**。现有诊断使分析命令退出码为 1；本轮新增共享组件与测试文件无诊断。`git diff --check` 通过。版本仍为 `1.5.5+36`，`lib/core`、`lib/scraper`、依赖及数据库版本没有本轮变更。原生测试未调用正式入口的版本初始化，关于页截图中的 `v0.0.0` 为测试环境显示。

截图、检查页及日志保留在该工作树的 `build/motion_review/`。正式测试源文件保留，样本数据库由原生用例清理，临时运行脚本已移除。交付由 `codex/motion-loading` 分支的本地提交承载。

## 验证边界

原生验收使用构建目录中的独立 SQLite、配置和图片样本；等待、空态和失败状态通过 Provider 注入控制。外部站点、真实账号 WebDAV、视频播放、SMB、正式安装升级和攻略多引擎消息及全局热键链路不属于此次实际运行验证。此次不重新测量 Profile 帧耗时。

原工作区的翻译和迁移修改仍独立保留。后续集成需对照双方最新的 `game_detail_page.dart`，并重新执行整合验证。
