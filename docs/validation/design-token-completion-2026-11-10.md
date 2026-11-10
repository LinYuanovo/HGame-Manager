# 设计令牌统一与验收

日期：2026-11-10。基线：`d3971b3`。分支：`codex/integration-ui-translation`。

## 范围

本次检查 `lib/ui` 下全部 Dart 文件，并补充 `lib/main.dart` 中的错误页面。设计定义集中在 `AppTheme` 和 `GlassConstants`，使用处按界面用途引用。既有布局的尺寸保持原值；用户字号、媒体比例、窗口尺寸、滚动距离、动画计算及其他业务参数按原逻辑保留。

## 完成内容

- 设置页共享 `_buildSection` 改用动态主色、`iconControl` 和 `spacingInline`，所有设置分区同时生效。
- 完成导航、分类、游戏列表/详情、刮削、存档、工具、设置、图片管理、通用弹窗及攻略浮窗中的图标、字号、圆角和常用间距引用。
- 页面和共享组件中的固定主色、次色和浅主色改为按当前主题获取。设置、刮削标题渐变也使用主题接口。
- `GlassChip`、`GlassCard`、`BreathingBorder` 等共享组件使用动态颜色。呼吸边框的可选颜色未传入时由当前主题决定。
- 主色按钮及加载指示器使用对应的前景色；图片遮罩、固定语义色按钮和 ShaderMask 的白色前景集中引用 `lightForegroundColor`。普通阴影、输入填充和弹窗遮罩使用对应主题接口。
- 新增 `design_token_usage_test.dart`，扫描颜色字面量、固定主题色、字号/图标默认值、圆角、EdgeInsets 和短 SizedBox 间隔；主题定义文件作为 token 来源排除。
- 新增共享标签、呼吸边框及主色前景的浅深色组件回归。原生测试入口保留为 `integration_test/design_tokens_exe_test.dart`。

## 扫描结果

口径为 41 个 `lib/ui` 使用文件及 `lib/main.dart`，排除 `app_theme.dart` 定义文件。数值计数反映明确规则匹配，不代表所有数字都应替换。

| 项目 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 固定主题主色/次色/表面色引用 | 189 | 0 |
| 字号字面量 | 18 | 0 |
| 图标尺寸字面量 | 264 | 0 |
| 圆角字面量 | 2 | 0 |
| 原始颜色引用（透明色除外） | 18 | 0 |
| 40px 及以内单维 SizedBox 间隔 | 64 | 0 |
| EdgeInsets 中非零数值 | 97 | 0 |

## 验证

- 245 项业务回归通过，包括新增的 token 使用检查和浅深色组件测试。
- 静态分析零错误、19 warning、434 info；诊断由基线 500 条降到 453 条。按文件和消息去除行号对比，没有新增诊断；历史警告仍存在，分析器退出码为 1。
- 原生入口使用独立空数据库、四个样本游戏和真实 PNG，检查浅深色各 33 个状态：七个主页面，设置六分区首尾，十二个弹窗/子页面，以及单个/批量导入真实按钮入口。
- 设置与批量添加通过正式软件入口打开；其他共享弹窗直接实例化其真实组件。实际远程刮削、WebDAV 认证、文件选择器、视频播放和全局热键冲突不在本次端到端覆盖范围。
- 原有 `ui_translation_merge_test.dart` 复验翻译/目录持久化、原文切换、封面画质开关、同路径替换图片和诊断 ZIP，确保主题修改没有破坏这些连接处。

最终 66 个原生状态全部通过，66 张截图已通过分组核对图逐项目视检查，未发现布局溢出；翻译与封面整合原生用例也通过。截图中的游戏、图片和数据均为测试样本；关于页版本显示来自测试入口的默认值，不代表修改了应用版本。

攻略浮窗本轮完成源码与 token 检查，未重新启动独立子引擎；`main.dart` 错误页完成源码与编译检查，未注入运行时故障触发。不能将 66 个界面状态表述为所有可能运行状态的全覆盖。

## 清理与交付

- 构建安装清单核对为本工作区 Debug 输出目录。隔离原生构建已删除，原 `build` 已恢复，原 Release 主程序和 `data/app.so` 的 SHA-256 保持一致。
- 66 张截图、22 张核对图、替换工具和临时测试启动脚本已清理。正式 token 使用检查、组件测试与原生测试入口保留用于回归。
- 本聊天证据目录 `C:\Users\Administrator\.codex\visualizations\2026\11\09\01a1c0fd-df6b-7430-a0dd-a05761a18417` 保留 `token-native.log`、`token-integration.log`、`token-regression.log`、`token-final-analyze.log`、结果 JSON、源码哈希与截图哈希清单。
- 应用和数据库版本保持原值，成果仅提交到本地整合分支。

## 复验方法

1. `flutter test --no-pub --concurrency=1 test/ui/theme` 检查 token 与共享组件。
2. 在空 Windows Debug 构建数据目录运行 `flutter test integration_test/design_tokens_exe_test.dart -d windows --no-pub --timeout=5m`。指定 `UI_TOKEN_EVIDENCE` 可输出检查用截图；测试开始会验证数据目录为空。
3. Flutter/Dart 始终串行运行。构建前保留已有 `build`，避免覆盖已有运行文件和用户数据；CMake 安装前缀必须指向当前构建目标目录。
