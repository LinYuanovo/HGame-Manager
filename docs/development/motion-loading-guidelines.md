# 动效与加载规范

适用于 Windows 主窗口、详情页、攻略浮窗、设置及业务弹窗。视觉沿用玻璃表面、圆角和 `AppTheme` 浅深色令牌。

## 时间与移动

- 按压 100ms；松开轻微回弹 310ms；退出、图片淡入和确定进度追随 200ms；内容切换与入场 310ms；图片展开与滚动 420ms。透明度、颜色与进度使用单调曲线，回弹只作用于位置、缩放。
- 自绘连续值通过窗口 `View.display.refreshRate` 采样原始 vsync 时间戳；换屏后读取新值，未知频率跟随引擎。窗口隐藏暂停装饰，失焦但可见时保持反馈。框架滚动、原生窗口移动与输入跟随平台；不要用固定毫秒定时器模拟刷新率。
- 页面位移最多 8 个逻辑像素，列表首次进入最多 6 个；避免按页面宽度放大位移。设置分区固定从顶部进入，避免不同内容高度改变起点。
- 列表仅首批可见项短暂交错，滚动加载立即显示。图片缓存命中直接呈现。
- 路由过渡期间退出页面隔离鼠标、键盘焦点和语义树，停用内部 Ticker。
- 不用动画延后请求、写库、取消或完成状态；业务进度由实际状态驱动。

## 等待状态

- 游戏列表按用户已保存的列表/海报模式、列数和封面比例显示骨架。
- 分类为标签格，工具为图标卡，搜索/备份/规则为行骨架；图片使用同尺寸静态结构与流光占位。
- 一个加载区域由一个画笔和一个控制器绘制，流光周期 1400ms；通过 `CustomPainter(repaint:)` 更新绘制并用 `RepaintBoundary` 隔离，避免每帧重建页面。
- 确定进度保留数量、百分比和进度条；按钮短操作使用小型忙碌指示。数据返回后立即显示原有空态、错误或内容。
- 已有内容在保存、下载时保持可见，使用持续忙碌提示并禁用冲突操作；空区域才使用骨架。读取失败时结束等待并提供错误反馈和重试入口。
- 系统减少动效或辅助导航时停用位移、交错与流光，不确定进度使用静态等待标识。隐藏页面、后台生命周期和卸载后停止骨架动画。

## 使用规则

### 按钮与字体

- 普通确认、次要操作和取消分别使用主题中的 `ElevatedButton` / `FilledButton`、`OutlinedButton` 和 `TextButton`。标签使用 `Text` 继承按钮字型。四类按钮和 `IconButton` 共用 `AppMotion.buttonFace`。
- 删除、警告、成功等操作通过 `AppButtonStyles.solid`、`tinted`、`outline` 选择强调程度。紧凑表格操作使用 `AppMiniIconButton`，系统窗口按钮使用 `WindowCaptionButton`。回调为 `null` 时交由控件处理禁用、焦点和读屏状态。
- 界面默认字体由主窗口和攻略浮窗各自的 `AppTheme` 注入。按钮、菜单、标题和下拉选项继承主题。尚未保存的字体、正文字号和详情字号只在设置页的字体预览中生效。
- 共用对话框标题使用 `AppTypography.dialogTitle`。字号取 `GlassConstants.font*`，字重和正文行高取 `AppTypography`。详情、Markdown 和浮窗的阅读字号继续使用用户设置。
- 表单和列表可以决定布局宽度、容器位置及可见操作。绘制颜色、按钮状态、字号和字重分别在主题入口维护。`test/ui/theme/design_token_usage_test.dart` 检查页面新增的本地样式，`theme_test.dart` 验证渲染后的字体、动效和对比度。

### 动效组件

- `AppMotion` 管理时间、曲线、系统偏好及滚动；`AppTabController` 让标签页的框架内部点击也遵循偏好。
- `AppContentSwitcher` 用于有明确显示区域的互斥内容，当前页和退出页保留相同的包装结构；`AppEntrance` 用于一次性进入，取消时立即显示。
- `AppSkeleton` 只承担展示；游戏页用 `GameListSkeleton` 读取实际布局 Provider，固定列数开关与封面比例须和列表一致。
- `AppProgressIndicator` 和 `AppLinearProgress` 保留真实任务进度及主题颜色。
- 新等待入口复用共享组件。既有数据、缓存、错误处理和持久化仍由原业务层管理。

## 参考

- [Flutter 官方流光骨架示例](https://docs.flutter.dev/cookbook/effects/shimmer-loading)：占位形状对应最终内容，同一区域的流光保持一致。
- [Flutter 性能建议](https://docs.flutter.dev/perf/best-practices)：限制重建、离屏层与动画影响范围。
- [Flutter 动画概览](https://docs.flutter.dev/ui/animations)：使用框架现有动画能力。

使用 Flutter 自带绘制与动画组件。流光画笔使用完全不透明的基础色，再由渐变控制透明度；减少动效时采用低透明度动态主色绘制静态结构。
