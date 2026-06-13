# Git 提交规则

## 默认行为
- 所有 `git commit` 操作仅限本地提交
- **禁止**自动执行 `git push` 推送到远程仓库
- 只有当用户明确说"提交到 GitHub"或"推送到远程"时，才执行 `git push`

## 示例
- ✅ `git add -A && git commit -m "xxx"` — 允许
- ❌ `git push origin master` — 禁止（除非用户明确要求）
- ❌ `git push` — 禁止（除非用户明确要求）

# 项目了解规则

## 新任务启动
- 开始新任务前，先读取 `ARCHITECTURE.md` 了解项目结构和技术栈
- 快速掌握项目整体架构后再进行具体开发
