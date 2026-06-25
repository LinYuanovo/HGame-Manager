# Git 提交规则

## 默认行为
- 所有 `git commit` 操作仅限本地提交
- **禁止**自动执行 `git push` 推送到远程仓库
- **禁止**自行变更版本号
- 只有当用户明确说"提交到 GitHub"或"推送到远程"时，才执行 `git push`

## 示例
- ✅ `git add -A && git commit -m "xxx"` — 允许
- ❌ `git push origin master` — 禁止（除非用户明确要求）
- ❌ `git push` — 禁止（除非用户明确要求）
- ❌ `自行变更版本号` — 禁止（除非用户明确要求）

# 项目了解规则

## 新任务启动
- 开始新任务前，先读取 `ARCHITECTURE.md` 了解项目结构和技术栈
- 快速掌握项目整体架构后再进行具体开发

# 交流规则

## 讨论
- 回答或编写文档和注释时，必须使用中文

# 暗黑模式开发规范

## 禁止硬编码颜色

在 UI 代码中，**禁止**直接使用以下硬编码方式：

```dart
// ❌ 错误示例
Color(0xFFFFFFFF)
Colors.white
Color(0xFF374244)
Colors.grey
```

## 正确做法

使用 `AppTheme` 提供的动态获取方法：

```dart
// ✅ 正确示例
AppTheme.getSurfaceColor(context)      // 表面色（白/深灰）
AppTheme.getTextPrimary(context)       // 主文字色
AppTheme.getTextSecondary(context)     // 次要文字色
AppTheme.getBorderColor(context)       // 边框色
AppTheme.getBackgroundColor(context)   // 背景色
AppTheme.getCardColor(context)         // 卡片色
AppTheme.getPrimaryColor(context)      // 主题色
AppTheme.getFavoriteColor(context)     // 收藏红
AppTheme.getStarColor(context)         // 星级金
```

## 特殊颜色

对于语义颜色（成功、警告、错误），直接使用 AppTheme 常量：

```dart
AppTheme.successColor   // 绿色
AppTheme.warningColor   // 黄色
AppTheme.errorColor     // 红色
AppTheme.warningOrange  // 橙色
```

## 透明色

`Colors.transparent` 不需要主题适配，可以直接使用。

## 白色前景色

按钮、图标等白色前景色（如 `Colors.white`）通常保持不变，因为：
- 浅色模式：白色按钮上的白色文字
- 深色模式：深色按钮上的白色文字

但如果背景色是动态的，需要确保对比度足够。
