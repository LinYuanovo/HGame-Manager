请将当前 Flutter 应用的 UI 从 Material 3 默认风格全面改造为以下设计语言，并确保所有页面和组件统一应用，不要修改业务逻辑，只要修改UI代码就行：

## 全局风格要求
- **玻璃拟态（Glassmorphism）**：背景使用模糊和半透明效果，模拟磨砂玻璃质感
- **呼吸感**：界面有恰当的留白、轻量动效，元素看起来“轻盈通透”
- **圆润平滑自然**：所有卡片、按钮、容器使用较大圆角（如 16~24px），过渡动画缓动自然
- **视觉元素**：大量使用圆角、半透明背景（rgba 或 withOpacity）、柔和阴影（多层阴影营造悬浮感）、微妙渐变、流畅的微交互动画

## 图标

- 形状：圆角方形（圆角半径约图标边长的 22%），类似 iOS 现代图标风格
- 背景：纯白色（#FFFFFF），可带有极其微弱的灰白渐变或完全纯白
- 主体内容：
  - 字母 "JM" 居中显示
  - 字体：MapleMonoNL-NF-CN-Bold
  - 颜色：蓝色（建议使用明快、科技感的蓝色，如 #2563EB 或 #3B82F6，与白色背景形成鲜明对比）
  - 比例：字母主体占图标内面积的 55%-65%，视觉饱满但不拥挤
- 风格参考：小米 logo 的现代简约感 —— 字母坚实有力，轮廓清晰，无多余装饰，重心平稳，可微调字距让 “J” 与 “M” 结合更紧密整体
- 整体图标不加任何边框、高光或浮雕效果，保持极致扁平与干净
- 输出格式：提供 1024x1024 的 PNG 透明背景（白色底作为图标内容），并同时导出 app_icon.png 可用于 Flutter 项目
- 另可提供一个简化版单色剪影（蓝色 "JM" 在透明背景上），用于通知栏等小尺寸场景

请确保最终图标在不同尺寸下都清晰可辨，圆角与字母比例协调，符合玻璃拟态应用的精致调

## 具体实现指引

### 1. 主题配置（ThemeData）
- 修改 `ThemeData` 的 `colorScheme`，使用浅色/深色半透明色板
- 设置 `scaffoldBackgroundColor` 为带有模糊感的背景色，或使用堆叠的背景层
- 全局 `cardTheme`：默认背景半透明白色，圆角 20，阴影轻微弥散
- 全局 `appBarTheme`：背景使用 `BackdropFilter` 模糊，或半透明带模糊效果
- 文字主题颜色需适配半透明背景，保证可读性

### 2. 玻璃拟态核心实现
- 在需要玻璃效果的容器上包裹 `ClipRRect` + `BackdropFilter`（filter: ImageFilter.blur），并设置半透明背景色
- 例如（只是参考，不是一定要这样）：
  ```dart
  ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ... // 内容
      ),
    ),
  )

## 圆角与阴影
所有交互元素（按钮、卡片、输入框、列表项）使用 BorderRadius.circular(16) 或以上

阴影采用柔和的多层阴影，营造悬浮感（颜色使用半透明黑色或主色调）

## 渐变与色彩
渐变背景：页面背景可考虑低饱和度的对角线渐变或径向渐变

强调色使用柔和渐变（如蓝色→紫色），应用于选中状态、按钮、标签

## 动画与呼吸感
页面切换使用淡入淡出或平滑滑动，时长 300-400ms，曲线用 Curves.easeInOut

列表项加载添加交错动画（staggered animation），项目逐个淡入上浮

按钮和卡片添加微弱的 hover 和 press 动效（缩放、阴影加深），可使用 AnimatedContainer 或 InkWell 自定义

利用 TweenAnimationBuilder 实现属性平滑过渡（如数值变化时）

## 全局组件改造
侧边栏：应用毛玻璃背景，菜单项悬停高亮为半透明浅色

影片网格/列表：每个影片卡片使用玻璃卡片样式，图片带圆角

演员头像：圆形头像，外圈带柔光阴影

按钮：半透明背景，边框 1px 半透明白色，点击时轻微放大并加深背景

滚动条：自定义为半透明细条，圆角

# 性能注意事项
过多的 BackdropFilter 可能影响性能，仅在必要的顶层容器使用，或条件性启用

对于列表项，避免在每一项上都应用实时模糊，可考虑预渲染或使用缓存

# 执行方式
先改造全局主题和公共基础组件（如 GlassCard, GlassButton, GlassContainer），然后在各个页面中替换现有组件

保留现有业务逻辑不变，仅修改 UI 层的样式和布局

所有颜色、圆角大小、动画时长等参数集中定义在 app_theme.dart 或常量文件中，方便统一调优

请根据以上要求，完整修改当前项目的 UI 代码，并确保最终效果具有高度统一的玻璃拟态呼吸感。
