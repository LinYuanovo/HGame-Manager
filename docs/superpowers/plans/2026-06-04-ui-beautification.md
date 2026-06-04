# UI美化设计实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按照DESIGN.md规范进行UI美化，添加呼吸感动画、统一Glass组件使用、优化交互体验，但不修改业务逻辑。

**Architecture:** 在现有Glass组件体系基础上，补充缺失的呼吸感动画（光晕脉动、边框脉动），将未Glass化的组件（详情弹窗、右键菜单、SnackBar）改为Glass风格，优化侧边栏折叠动画。

**Tech Stack:** Flutter, Dart, 现有Glass组件库

---

## 文件结构

### 需要修改的文件

| 文件 | 职责 | 修改内容 |
|------|------|----------|
| `lib/ui/theme/app_theme.dart` | 主题和组件库 | 添加呼吸感动画组件、优化GradientBackground |
| `lib/ui/pages/games/game_detail_page.dart` | 游戏详情弹窗 | 改为使用showGlassDialog()，统一Glass风格 |
| `lib/ui/widgets/game_list_widget.dart` | 游戏列表 | 右键菜单改为showGlassMenu() |
| `lib/ui/pages/categories/categories_page.dart` | 分类页 | 右键菜单改为showGlassMenu() |
| `lib/ui/widgets/sidebar_widget.dart` | 侧边栏 | 优化折叠动画，添加文字淡出效果 |
| `lib/ui/controllers/sidebar_controller.dart` | 侧边栏控制器 | 添加平滑动画支持 |
| `lib/ui/pages/settings/settings_page.dart` | 设置页 | 统一使用GlassContainer |
| `lib/ui/pages/scraper/scraper_page.dart` | 刮削页 | 统一使用GlassContainer |

---

## Task 1: 添加光晕呼吸动画到GradientBackground

**Files:**
- Modify: `lib/ui/theme/app_theme.dart:550-613`

- [ ] **Step 1: 将GradientBackground改为StatefulWidget**

```dart
class GradientBackground extends StatefulWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.03, end: 0.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE0E8F0),
            Color(0xFFE8E4F2),
            Color(0xFFF0ECFA),
            Color(0xFFE8EFF8),
            Color(0xFFF2F0FF),
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF2563EB).withValues(alpha: _glowAnimation.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Positioned(
                bottom: -150,
                left: -100,
                child: Container(
                  width: 600,
                  height: 600,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF7C3AED).withValues(alpha: _glowAnimation.value * 0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证动画效果**

运行应用，确认背景光晕有缓慢脉动效果（4-6秒周期，opacity在0.03-0.06之间变化）。

---

## Task 2: 添加边框呼吸动画组件

**Files:**
- Modify: `lib/ui/theme/app_theme.dart` (在GlassCard后添加新组件)

- [ ] **Step 1: 创建BreathingBorder组件**

```dart
class BreathingBorder extends StatefulWidget {
  final Widget child;
  final bool isBreathing;
  final Color color;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const BreathingBorder({
    super.key,
    required this.child,
    this.isBreathing = false,
    this.color = AppTheme.primaryColor,
    this.duration = const Duration(seconds: 3),
    this.minOpacity = 0.15,
    this.maxOpacity = 0.35,
    this.borderRadius = GlassConstants.radiusLarge,
    this.padding,
  });

  @override
  State<BreathingBorder> createState() => _BreathingBorderState();
}

class _BreathingBorderState extends State<BreathingBorder>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(BreathingBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isBreathing != widget.isBreathing) {
      _setupAnimation();
    }
  }

  void _setupAnimation() {
    if (widget.isBreathing) {
      _controller?.dispose();
      _controller = AnimationController(
        duration: widget.duration,
        vsync: this,
      )..repeat(reverse: true);
      _animation = Tween<double>(
        begin: widget.minOpacity,
        end: widget.maxOpacity,
      ).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeInOut),
      );
    } else {
      _controller?.stop();
      _animation = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller ?? const AlwaysStoppedAnimation(0),
      builder: (context, child) {
        final opacity = _animation?.value ?? widget.minOpacity;
        return Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.color.withValues(alpha: opacity),
              width: 1,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 2: 验证组件**

创建一个简单的测试页面，确认BreathingBorder在isBreathing=true时边框透明度有脉动效果。

---

## Task 3: 优化GlassCard支持边框呼吸

**Files:**
- Modify: `lib/ui/theme/app_theme.dart:377-476`

- [ ] **Step 1: 为GlassCard添加边框呼吸支持**

在GlassCard中添加`enableBorderBreathing`参数，并在选中态时启用边框呼吸：

```dart
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final bool enableHoverEffect;
  final bool enableBorderBreathing;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = GlassConstants.radiusLarge,
    this.color,
    this.enableHoverEffect = true,
    this.enableBorderBreathing = false,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  AnimationController? _borderController;
  Animation<double>? _borderAnimation;

  @override
  void initState() {
    super.initState();
    _setupBorderAnimation();
  }

  @override
  void didUpdateWidget(GlassCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableBorderBreathing != widget.enableBorderBreathing) {
      _setupBorderAnimation();
    }
  }

  void _setupBorderAnimation() {
    if (widget.enableBorderBreathing) {
      _borderController?.dispose();
      _borderController = AnimationController(
        duration: const Duration(seconds: 3),
        vsync: this,
      )..repeat(reverse: true);
      _borderAnimation = Tween<double>(begin: 0.15, end: 0.35).animate(
        CurvedAnimation(parent: _borderController!, curve: Curves.easeInOut),
      );
    } else {
      _borderController?.stop();
      _borderAnimation = null;
    }
  }

  @override
  void dispose() {
    _borderController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enableHoverEffect ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enableHoverEffect ? (_) => setState(() { _isHovered = false; _isPressed = false; }) : null,
      child: GestureDetector(
        onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: widget.onTap != null ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed
              ? GlassConstants.pressScale
              : (_isHovered ? GlassConstants.hoverScale : 1.0),
          duration: GlassConstants.animFast,
          curve: GlassConstants.animCurve,
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            curve: GlassConstants.animCurve,
            margin: widget.margin,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlassConstants.blurMedium,
                  sigmaY: GlassConstants.blurMedium,
                ),
                child: AnimatedBuilder(
                  animation: _borderController ?? const AlwaysStoppedAnimation(0),
                  builder: (context, child) {
                    final borderOpacity = _borderAnimation?.value ?? 0.35;
                    return AnimatedContainer(
                      duration: GlassConstants.animFast,
                      curve: GlassConstants.animCurve,
                      padding: widget.padding,
                      decoration: BoxDecoration(
                        color: widget.color ??
                            (_isHovered
                                ? Colors.white.withValues(alpha: 0.88)
                                : Colors.white.withValues(alpha: 0.65)),
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        border: Border.all(
                          color: _isHovered
                              ? AppTheme.primaryColor.withValues(alpha: 0.25)
                              : widget.enableBorderBreathing
                                  ? AppTheme.primaryColor.withValues(alpha: borderOpacity)
                                  : Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isHovered
                                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.05),
                            blurRadius: _isHovered ? 28 : 16,
                            spreadRadius: _isHovered ? 2 : 1,
                            offset: Offset(0, _isHovered ? 6 : 4),
                          ),
                          BoxShadow(
                            color: (_isHovered
                                ? AppTheme.secondaryColor
                                : AppTheme.primaryColor).withValues(alpha: _isHovered ? 0.06 : 0.03),
                            blurRadius: _isHovered ? 50 : 40,
                            spreadRadius: 0,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证效果**

在游戏列表中选中卡片时，确认边框有呼吸脉动效果。

---

## Task 4: 将GameDetailDialog改为Glass风格

**Files:**
- Modify: `lib/ui/pages/games/game_detail_page.dart:57-95`

- [ ] **Step 1: 修改build方法使用showGlassDialog**

将原有的Dialog实现改为使用showGlassDialog：

```dart
@override
Widget build(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  final dialogWidth = screenSize.width * 0.9;
  final dialogHeight = screenSize.height * 0.9;

  return PopScope(
    canPop: !_isImageViewerOpen,
    child: Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: GlassConstants.blurLarge,
            sigmaY: GlassConstants.blurLarge,
          ),
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
                  blurRadius: 50,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                Expanded(child: _buildBody()),
                if (_isEditing)
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                if (_isEditing) _buildEditBar(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: 移除原生Divider**

将所有`Divider`替换为玻璃风格的分隔线：

```dart
Container(
  height: 1,
  color: Colors.white.withValues(alpha: 0.3),
)
```

- [ ] **Step 3: 验证详情弹窗**

打开游戏详情弹窗，确认使用Glass风格（毛玻璃背景、带色调阴影、白色高光边框）。

---

## Task 5: 统一右键菜单为Glass风格

**Files:**
- Modify: `lib/ui/widgets/game_list_widget.dart` (查找_showContextMenu方法)
- Modify: `lib/ui/pages/categories/categories_page.dart` (查找_showTagContextMenu方法)

- [ ] **Step 1: 修改game_list_widget.dart中的右键菜单**

将原生`showMenu()`改为`AppTheme.showGlassMenu()`：

```dart
// 在_showContextMenu方法中
final result = await AppTheme.showGlassMenu<String>(
  context: context,
  position: position,
  items: [
    // ... 菜单项
  ],
);
```

- [ ] **Step 2: 修改categories_page.dart中的右键菜单**

同样将原生`showMenu()`改为`AppTheme.showGlassMenu()`。

- [ ] **Step 3: 验证右键菜单**

在游戏列表和分类页右键点击，确认菜单使用Glass风格（毛玻璃背景、圆角、带色调阴影）。

---

## Task 6: 优化侧边栏折叠动画

**Files:**
- Modify: `lib/ui/controllers/sidebar_controller.dart`
- Modify: `lib/ui/widgets/sidebar_widget.dart`

- [ ] **Step 1: 为SidebarController添加动画支持**

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 侧边栏状态控制器，管理侧边栏的宽度、展开/折叠状态
class SidebarController extends ChangeNotifier {
  double _width;
  final double _minWidth;
  final double _maxWidth;
  double _targetWidth;

  SidebarController({
    double width = LayoutConstants.sidebarWidth,
    double minWidth = LayoutConstants.minSidebarWidth,
    double maxWidth = LayoutConstants.maxSidebarWidth,
  })  : _width = width,
        _targetWidth = width,
        _minWidth = minWidth,
        _maxWidth = maxWidth;

  double get width => _width;
  bool get isExpanded => _width > 100;

  /// 根据拖拽增量更新侧边栏宽度
  void updateWidth(double delta) {
    final newWidth = (_width - delta).clamp(_minWidth, _maxWidth);
    if (newWidth != _width) {
      _width = newWidth;
      _targetWidth = newWidth;
      notifyListeners();
    }
  }

  /// 平滑过渡到目标宽度
  void animateToWidth(double targetWidth) {
    _targetWidth = targetWidth.clamp(_minWidth, _maxWidth);
    notifyListeners();
  }

  /// 更新当前宽度（由动画驱动）
  void updateAnimatedWidth(double width) {
    _width = width;
    notifyListeners();
  }
}
```

- [ ] **Step 2: 修改SidebarWidget使用AnimatedContainer**

在sidebar_widget.dart中，将Container改为AnimatedContainer，并添加文字淡出效果：

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final fontSize = ref.watch(fontSizeProvider);
  final gamesAsync = ref.watch(allGamesProvider);
  final playedAsync = ref.watch(playedGamesProvider);

  return MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      onHorizontalDragUpdate: (details) {
        controller.updateWidth(details.delta.dx);
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: GlassConstants.blurMedium,
                sigmaY: GlassConstants.blurMedium,
              ),
              child: AnimatedContainer(
                duration: GlassConstants.animMedium,
                curve: GlassConstants.animCurve,
                width: controller.width,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    ...NavRoute.values.where((r) => r != NavRoute.settings).map((route) {
                      int? count;
                      if (route == NavRoute.games) {
                        count = gamesAsync.valueOrNull?.length;
                      } else if (route == NavRoute.played) {
                        count = playedAsync.valueOrNull?.length;
                      }
                      return _buildNavItem(
                        route: route,
                        selectedIndex: selectedIndex,
                        count: count,
                        fontSize: fontSize,
                        ref: ref,
                      );
                    }),
                    const Spacer(),
                    _buildNavItem(
                      route: NavRoute.settings,
                      selectedIndex: selectedIndex,
                      count: null,
                      fontSize: fontSize,
                      ref: ref,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
```

- [ ] **Step 3: 为文字添加淡出效果**

在_buildNavItem方法中，使用AnimatedOpacity实现文字淡出：

```dart
Widget _buildNavItem({
  required NavRoute route,
  required int selectedIndex,
  int? count,
  double fontSize = 14.0,
  required WidgetRef ref,
}) {
  final isSelected = route.index == selectedIndex;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        onTap: () {
          ref.read(selectedNavIndexProvider.notifier).state = route.navIndex;
        },
        child: AnimatedContainer(
          duration: GlassConstants.animFast,
          curve: GlassConstants.animCurve,
          padding: EdgeInsets.symmetric(
            horizontal: controller.isExpanded ? 16 : 0,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.15),
                      AppTheme.secondaryColor.withValues(alpha: 0.15),
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: controller.isExpanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? route.selectedIcon : route.icon,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondary,
                size: 22,
              ),
              AnimatedOpacity(
                opacity: controller.isExpanded ? 1.0 : 0.0,
                duration: GlassConstants.animMedium,
                curve: GlassConstants.animCurve,
                child: controller.isExpanded
                    ? Row(
                        children: [
                          const SizedBox(width: 12),
                          Text(
                            route.label,
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : AppTheme.textSecondary,
                              fontSize: fontSize,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          if (count != null && count > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? LinearGradient(
                                        colors: [
                                          AppTheme.primaryColor.withValues(alpha: 0.8),
                                          AppTheme.secondaryColor.withValues(alpha: 0.8),
                                        ],
                                      )
                                    : null,
                                color: isSelected
                                    ? null
                                    : AppTheme.textSecondary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 18),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                  fontSize: (fontSize * 0.78).clamp(9, 14),
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: 验证侧边栏动画**

拖拽侧边栏分隔条，确认：
1. 宽度平滑过渡（300ms easeInOut）
2. 文字淡出/淡入效果
3. 图标保持居中

---

## Task 7: 统一设置页使用GlassContainer

**Files:**
- Modify: `lib/ui/pages/settings/settings_page.dart`

- [ ] **Step 1: 查找并替换原生Container**

搜索settings_page.dart中使用原生Container的地方，替换为GlassContainer：

```dart
// 原来的
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.6),
    borderRadius: BorderRadius.circular(16),
  ),
  child: ...
)

// 改为
GlassContainer(
  padding: EdgeInsets.all(16),
  child: ...
)
```

- [ ] **Step 2: 验证设置页**

打开设置页，确认所有卡片区域使用Glass风格。

---

## Task 8: 统一刮削页使用GlassContainer

**Files:**
- Modify: `lib/ui/pages/scraper/scraper_page.dart`

- [ ] **Step 1: 查找并替换原生Container**

搜索scraper_page.dart中使用原生Container的地方，替换为GlassContainer。

- [ ] **Step 2: 验证刮削页**

打开刮削页，确认所有面板使用Glass风格。

---

## Task 9: 优化SnackBar为Glass风格

**Files:**
- Modify: 搜索所有使用`ScaffoldMessenger.showSnackBar()`的地方

- [ ] **Step 1: 创建GlassSnackBar工具方法**

在app_theme.dart中添加：

```dart
static void showGlassSnackBar(BuildContext context, String message, {Color? color}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(
            color: (color ?? AppTheme.primaryColor).withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: (color ?? AppTheme.primaryColor).withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 30,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              color == AppTheme.errorColor
                  ? Icons.error_outline
                  : color == AppTheme.successColor
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
              color: color ?? AppTheme.primaryColor,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: color ?? AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height * 0.1,
        left: MediaQuery.of(context).size.width * 0.3,
        right: MediaQuery.of(context).size.width * 0.3,
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}
```

- [ ] **Step 2: 替换所有原生SnackBar调用**

搜索代码库中所有使用`ScaffoldMessenger.showSnackBar()`的地方，替换为`AppTheme.showGlassSnackBar()`。

- [ ] **Step 3: 验证SnackBar**

触发SnackBar（如复制操作），确认使用Glass风格。

---

## Task 10: 最终验证

- [ ] **Step 1: 运行应用全面测试**

运行应用，逐一检查：
1. 背景光晕呼吸效果
2. 选中卡片边框呼吸效果
3. 游戏详情弹窗Glass风格
4. 右键菜单Glass风格
5. 侧边栏折叠动画
6. 设置页和刮削页Glass风格
7. SnackBar Glass风格

- [ ] **Step 2: 检查动画性能**

确认所有动画流畅，无卡顿感。呼吸感动画周期≥4秒，opacity变化幅度≤0.03。

- [ ] **Step 3: 检查业务逻辑**

确认所有业务逻辑未被修改，功能正常运行。

---

## 设计规范检查清单

根据DESIGN.md规范，逐项检查：

- [ ] 所有容器用`GlassContainer`/`GlassCard`，不用原生`Container`
- [ ] 圆角值在12~24之间
- [ ] 没有纯白/纯黑大面积实色
- [ ] 阴影带主色调环境光
- [ ] hover效果：阴影+scale，200ms，easeInOut
- [ ] 列表项用`StaggeredItem`入场
- [ ] 弹窗用`showGlassDialog()`，菜单用`showGlassMenu()`
- [ ] 同时播放≤3个动画
- [ ] 不用原生`AppBar`、`TabBar`、`showDialog`
- [ ] 文字只用`textPrimary`或`textSecondary`
- [ ] 间距用`GlassConstants.spacingXxx`
- [ ] 玻璃透明度在60%~88%之间
- [ ] 光晕呼吸周期4~6秒
- [ ] 边框呼吸周期3~4秒
- [ ] 动画时长不超过500ms
- [ ] 不使用`Curves.linear`、`Curves.bounceIn`

---

## 注意事项

1. **不修改业务逻辑**：所有修改仅限于UI层，不涉及数据处理、状态管理逻辑
2. **保持向后兼容**：新组件参数都有默认值，不影响现有调用
3. **渐进式改进**：可以分批实施，每个Task独立可验证
4. **性能考虑**：呼吸感动画使用`AnimationController`循环驱动，避免使用`Timer`