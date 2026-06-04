# HGame-Manager 设计规范

> 玻璃拟态 · 呼吸感 · 清新自然
>
> 像清晨薄雾里的花园——光线柔和地穿过玻璃，一切都在轻轻地呼吸。

---

## 一、设计灵魂

### Q: 这个应用要给用户什么感觉？

**A: 清晨薄雾中的玻璃温室。**

阳光透过磨砂玻璃洒进来，光线被柔化、散开，形成温润的光晕。空气中有微微的流动感——不是静止的展板，而是一个有生命的空间。

- **玻璃拟态**：所有容器都是磨砂玻璃，背景内容若隐若现，营造纵深
- **呼吸感**：界面不是死的——光晕在脉动、边框在微动、hover 时元素在膨胀
- **清新自然**：冷调蓝紫为骨，暖白为肤，圆润如鹅卵石，没有尖锐的棱角

### Q: 和常见的 Glassmorphism 有什么不同？

**A: 三个关键词区分。**

| 关键词 | 常见做法 | 我们的做法 |
|--------|----------|------------|
| 呼吸 | 静态 | 关键元素有微妙的持续脉动 |
| 透明度 | 统一白底 | 分层透明度，越高层越不透明 |
| 光感 | 平面 | 边框有折射高光，hover 时有彩色光晕 |

---

## 二、色彩系统

### 主色板

| 角色 | 色值 | 用途 |
|------|------|------|
| 主色 | `#2563EB` | 选中态、主按钮、链接 |
| 主色·浅 | `#3B82F6` | hover 态、渐变过渡 |
| 辅色 | `#7C3AED` | 渐变终点、次要强调 |
| 点缀 | `#FF6B6B` | 关闭按钮、删除、错误 |

### 背景层（由底到表）

| 层 | 色值 | 说明 |
|----|------|------|
| 最底层 | 5 色线性渐变 `#E0E8F0 → #E8E4F2 → #F0ECFA → #E8EFF8 → #F2F0FF` | 左上到右下 |
| 光晕 1 | 径向渐变 `#2563EB @ 4% → transparent` | 右上角 500px 圆 |
| 光晕 2 | 径向渐变 `#7C3AED @ 3% → transparent` | 左下角 600px 圆 |

### 玻璃层透明度规范

**原则：越高层的元素，越不透明（越"实"）。**

| 元素 | 透明度 | 说明 |
|------|--------|------|
| 侧边栏 | `@0.50` | 最轻薄，让背景透过来 |
| 卡片（默认） | `@0.65` | 标准玻璃体 |
| 卡片（hover） | `@0.88` | 接近实色，表示"聚焦" |
| 弹窗/Dialog | `@0.88` | 最实，压住底层 |
| 菜单/PopupMenu | `@0.95` | 几乎实色，保证可读性 |

### 文字色

| 层级 | 色值 | 用途 |
|------|------|------|
| 主文字 | `#1A1A2E` | 标题、正文 |
| 次文字 | `#6B7280` | 描述、提示 |

### 状态色

| 状态 | 色值 |
|------|------|
| 成功 | `#10B981` |
| 警告 | `#F59E0B` |
| 错误 | `#EF4444` |

---

## 三、玻璃质感规范

### Q: 玻璃的"层次感"怎么体现？

**A: 三层区分——背景层、内容层、浮层，透明度递减。**

```
背景层 (最透明)
  └─ GradientBackground      无模糊，纯渐变 + 光晕
  └─ 侧边栏                   blur=18, opacity=0.50

内容层 (中等)
  └─ 卡片/列表项               blur=18, opacity=0.65
  └─ TabBar                   blur=10, opacity=0.35

浮层 (最不透明)
  └─ 弹窗 Dialog              blur=30, opacity=0.88
  └─ 右键菜单                  blur=10, opacity=0.95
  └─ Toast                    blur=10, opacity=0.92
```

### Q: 边框高光怎么做？

**A: 双层边框——外层白光 + 内层彩色折射。**

```dart
// 标准玻璃边框
border: Border.all(
  color: Colors.white.withOpacity(0.35),  // 白色高光边
  width: 1,
)

// hover 时：白色边变亮 + 蓝色折射光
border: Border.all(
  color: _isHovered
      ? AppTheme.primaryColor.withOpacity(0.25)  // 蓝色折射
      : Colors.white.withOpacity(0.35),           // 默认白边
  width: 1,
)
```

### Q: 阴影怎么打？

**A: 双层阴影——近阴影定义距离 + 远阴影是彩色环境光。**

```dart
// 默认态
boxShadow: [
  BoxShadow(
    color: Colors.black.withOpacity(0.06),
    blurRadius: 20, spreadRadius: 2,
    offset: Offset(0, 4),
  ),
  BoxShadow(
    color: AppTheme.primaryColor.withOpacity(0.03),
    blurRadius: 40,
    offset: Offset(0, 8),
  ),
]

// hover 态：近阴影变蓝变大，远阴影切换为辅色
boxShadow: [
  BoxShadow(
    color: AppTheme.primaryColor.withOpacity(0.12),
    blurRadius: 28, spreadRadius: 2,
    offset: Offset(0, 6),
  ),
  BoxShadow(
    color: AppTheme.secondaryColor.withOpacity(0.06),
    blurRadius: 50,
    offset: Offset(0, 10),
  ),
]
```

---

## 四、圆角规范

| 级别 | 值 | 场景 |
|------|-----|------|
| Small | 12px | 芯片、小按钮、Tab 指示器 |
| Medium | 16px | 按钮、输入框、Toast |
| Large | 20px | 卡片、弹窗、PopupMenu |
| XLarge | 24px | 搜索栏（胶囊形）、大面板 |

**原则：** 容器越大圆角越大。搜索栏 24px 胶囊形是最圆的元素。

---

## 五、间距系统

基底为 8px 的四级递进：

| Token | 值 | 场景 |
|-------|-----|------|
| spacingSmall | 8px | 图标与文字、Chip 内 padding |
| spacingMedium | 16px | 卡片内 padding、列表项间距 |
| spacingLarge | 24px | 区块间距、卡片间、页面内边距 |
| spacingXLarge | 32px | 大区块分隔、弹窗内边距 |

---

## 六、呼吸感体系

### Q: "丰富型"呼吸感具体包含哪些？

**A: 六种呼吸模式，由背景到前景递进。**

### 6.1 光晕呼吸（背景层）

背景的径向渐变光晕缓慢脉动，模拟自然光线波动。

- **周期**：4~6 秒
- **幅度**：opacity 在 `0.03 ↔ 0.06` 之间
- **曲线**：`Curves.easeInOut`
- **实现**：`AnimationController` 循环驱动

### 6.2 边框呼吸（选中态）

选中的卡片/标签，边框透明度在 `0.15 ↔ 0.35` 之间缓慢变化。

- **周期**：3~4 秒
- **触发**：仅对 `isSelected=true` 的元素生效
- **实现**：`sin(breatheValue * pi)` 映射到 opacity 范围

### 6.3 交互呼吸（hover/press）

hover 不是瞬间跳变，而是有弹性的过渡：

```
默认 → hover:  scale 1.0 → 1.02, 时长 200ms, easeOut
hover → press: scale 1.02 → 0.97, 时长 100ms, easeIn
press → 释放:  scale 0.97 → 1.0,  时长 150ms, easeOut
```

同时伴随：阴影变大、阴影变蓝、边框变蓝。

### 6.4 Tab 切换过渡

Tab 内容切换时使用 `AnimatedSwitcher` 或自定义过渡：

- **效果**：旧内容淡出 + 新内容淡入 + 轻微上移
- **时长**：300ms
- **曲线**：`Curves.easeInOut`

### 6.5 页面转场

路由切换时：

- **效果**：新页面从右侧滑入 + 淡入
- **时长**：350ms
- **曲线**：`Curves.easeOutCubic`

### 6.6 列表项涟漪入场

列表/网格加载时，项目依次浮现：

- **效果**：fade 0→1 + slide 上移 5%
- **时长**：每项 150ms
- **顺序**：同时开始（不延迟，避免卡顿感）

### ⚠️ 呼吸感的度

- 同时只有 1~2 个元素在"呼吸"
- 光晕呼吸周期 ≥ 4 秒
- opacity 变化幅度 ≤ 0.03
- 每次交互最多触发 2 层反馈
- 动画时长不超过 500ms

---

## 七、动画规范

### 时长

| 时长 | 值 | 场景 |
|------|-----|------|
| Fast | 200ms | hover、scale、颜色过渡 |
| Medium | 300ms | 弹窗开关、Tab 切换 |
| Slow | 400ms | 页面转场、大面积位移 |

### 曲线

| 曲线 | 用途 |
|------|------|
| `Curves.easeInOut` | 通用（呼吸、过渡） |
| `Curves.easeOut` | 入场动画（快入慢出） |
| `Curves.easeOutCubic` | 页面转场（更流畅的减速） |

### 缩放值

| 状态 | scale | 说明 |
|------|-------|------|
| 默认 | 1.0 | — |
| hover | 1.02 | 轻微放大 |
| press | 0.97 | 轻微缩小 |

### ⚠️ 动画禁忌

- ❌ `Curves.linear` — 太机械
- ❌ `Curves.bounceIn` — 破坏玻璃的沉稳感
- ❌ 同时 > 3 个独立动画
- ❌ 动画时长 > 500ms
- ❌ 入场动画有延迟（会感觉卡顿）

---

## 八、侧边栏规范

### Q: 侧边栏怎么改？

**A: 保持 70px 折叠宽度，优化折叠/展开动画。**

### 折叠状态

| 状态 | 宽度 | 内容 |
|------|------|------|
| 展开 | 220px（默认） | 图标 + 文字 |
| 折叠 | 70px | 仅图标 |

### 折叠动画

- **时长**：300ms
- **曲线**：`Curves.easeInOut`
- **效果**：宽度平滑过渡 + 文字淡出/淡入 + 图标居中
- **实现**：`AnimatedContainer` 驱动宽度，`AnimatedOpacity` 驱动文字

### 折叠触发

- 手动拖拽分隔条
- 双击分隔条切换
- 窗口过窄时自动折叠（< 900px）

---

## 九、页面结构规范

### Q: 不同页面如何避免"套路化"？

**A: 每种页面类型有自己的布局语言。**

### 游戏页面（主库）

- **布局**：搜索栏 + 排序/视图切换 + 网格/列表
- **卡片**：`GlassCard`，封面图 + 标题 + 标签
- **入场**：`StaggeredItem` 涟漪

### 分类页面

- **布局**：标签云 + 渐变色块背景
- **标签云**：每个标签是一个 `GlassChip`，大小/颜色可按热度变化
- **背景**：标签区域有柔和的渐变色块，不同分类区域用不同色调区分

### 详情页面（弹窗形式）

- **布局**：图片轮播 + 信息面板
- **图片**：大图展示，支持左右切换
- **信息**：标题、版本、标签、描述、下载链接等

### 刮削页面

- **布局**：左侧控制面板 + 右侧结果列表
- **控制面板**：`GlassContainer` 包裹操作按钮和统计
- **结果**：列表项带进度条和状态指示

### 设置页面

- **布局**：分区表单，每个区域一个 `GlassCard`
- **内容**：标签 + 输入控件，紧凑排列

---

## 十、字体规范

| 用途 | 字体 | 说明 |
|------|------|------|
| 全局正文 | `Microsoft YaHei` | Windows 原生，中文友好 |
| 代码/路径 | `MapleMonoNL-NF-CN` | 项目内置等宽字体 |

### 字号层级

| 层级 | 字号 | 字重 | 场景 |
|------|------|------|------|
| headlineLarge | 34px | Bold | 页面大标题 |
| headlineMedium | 26px | w600 | 区块标题 |
| headlineSmall | 22px | w600 | 卡片标题 |
| titleLarge | 20px | w500 | 列表项标题 |
| titleMedium | 18px | w500 | 小标题 |
| titleSmall | 16px | w400 | 描述性标题 |
| bodyLarge | 18px | Normal | 大段正文 |
| bodyMedium | 15px | Normal | 默认正文 |
| bodySmall | 13px | Normal | 辅助文字 |

---

## 十一、组件速查表

所有组件定义在 `lib/ui/theme/app_theme.dart`。

| 组件 | 场景 | 关键参数 |
|------|------|----------|
| `GlassContainer` | 通用玻璃容器 | blur, borderRadius, color |
| `GlassCard` | 可交互卡片 | enableHoverEffect, onTap |
| `GlassButton` | 玻璃按钮 | gradient, isEnabled |
| `GlassSearchBar` | 搜索框 | hintText, onChanged |
| `GlassChip` | 标签芯片 | isSelected, color |
| `GlassAppBar` | 毛玻璃顶部栏 | title, actions |
| `GlassTabBar` | 毛玻璃标签栏 | controller, tabs |
| `StaggeredItem` | 列表项入场动画 | index, baseDelay |
| `EmptyStateWidget` | 空状态 | icon, message |
| `showGlassDialog()` | 毛玻璃弹窗 | child, barrierDismissible |
| `showGlassMenu()` | 毛玻璃菜单 | position, items |
| `showCopyToast()` | 复制提示 | text |

### 常量

| 类 | 用途 |
|----|------|
| `GlassConstants` | 圆角、模糊、动画时长、间距、缩放 |
| `LayoutConstants` | 卡片尺寸、窗口尺寸、侧边栏宽度 |

---

## 十二、设计禁忌

| 禁忌 | 原因 |
|------|------|
| 原生 Material 默认样式 | 破坏玻璃拟态一致性 |
| 纯白 `#FFFFFF` 大面积背景 | 失去透明层次 |
| 纯黑阴影 | 太硬，要用带色调的柔阴影 |
| 圆角 < 8px | 太尖锐 |
| 圆角 > 28px | 太卡通 |
| 同时 > 3 个动画 | 视觉噪音 |
| 动画 > 500ms | 感觉卡顿 |
| `Curves.linear` | 无呼吸感 |
| 边框 > 1.5px | 玻璃应该是轻盈的 |
| 透明度 < 50% | 太透明，难阅读 |
| 透明度 > 92% | 太实，失去玻璃感 |
| 有 `GradientBackground` 再套背景 | 渐变叠加变脏 |

---

## 十三、新页面自检清单

开发新页面或改造 UI 时，逐项检查：

- [ ] 所有容器用 `GlassContainer` / `GlassCard`，不用原生 `Container`
- [ ] 圆角值在 12~24 之间
- [ ] 没有纯白/纯黑大面积实色
- [ ] 阴影带主色调环境光
- [ ] hover 效果：阴影 + scale，200ms，easeInOut
- [ ] 列表项用 `StaggeredItem` 入场
- [ ] 弹窗用 `showGlassDialog()`，菜单用 `showGlassMenu()`
- [ ] 同时播放 ≤ 3 个动画
- [ ] 不用原生 `AppBar`、`TabBar`、`showDialog`
- [ ] 文字只用 `textPrimary` 或 `textSecondary`
- [ ] 间距用 `GlassConstants.spacingXxx`
- [ ] 玻璃透明度在 60%~88% 之间
