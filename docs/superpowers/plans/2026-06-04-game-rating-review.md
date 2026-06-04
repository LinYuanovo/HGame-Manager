# 游戏评分与评论系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为"已玩"和"已通关"页面的游戏添加评分（0-5星）和评论功能，高评分游戏优先排序，并在游戏卡片和详情页展示评分和评论。

**Architecture:** 在 games 表新增 `rating` 和 `review` 字段；通过 GameRepository 提供 CRUD；在 GameListWidget 右键菜单添加"评论"入口，弹出评分评论对话框；海报模式卡片左下角显示星星；排序逻辑中加入评分权重；游戏详情页版本号旁显示星星和红色评论按钮。

**Tech Stack:** Flutter, Riverpod, SQLite (sqflite_common_ffi), Dart

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/core/database/database_helper.dart` | 修改 | 数据库升级 v2→v3，添加 rating/review 列 |
| `lib/core/models/models.dart` | 修改 | Game 模型添加 rating/review 字段 |
| `lib/core/repositories/game_repository.dart` | 修改 | 添加 updateRatingReview 方法 |
| `lib/core/providers/providers.dart` | 修改 | 添加 ratingDesc 排序模式支持 |
| `lib/ui/widgets/game_list_widget.dart` | 修改 | 右键菜单添加"评论"、海报卡片显示星星、排序加入评分权重 |
| `lib/ui/pages/games/game_detail_page.dart` | 修改 | 版本号旁显示星星和红色评论按钮 |
| `test/rating_review_test.dart` | 创建 | 评分评论功能单元测试 |

---

### Task 1: 数据库升级 — 添加 rating 和 review 列

**Files:**
- Modify: `lib/core/database/database_helper.dart:7,35-39,42-60`

- [ ] **Step 1: 修改数据库版本号**

将 `lib/core/database/database_helper.dart` 第 7 行的版本号从 2 改为 3：

```dart
static const int _databaseVersion = 3;
```

- [ ] **Step 2: 添加 v2→v3 升级逻辑**

在 `_onUpgrade` 方法中添加新的升级分支（第 35-39 行之后）：

```dart
static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE games ADD COLUMN cover_index INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE games ADD COLUMN rating INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE games ADD COLUMN review TEXT');
    }
  }
```

- [ ] **Step 3: 修改 CREATE TABLE 语句**

在 `_onCreate` 方法的 games 表定义中（`cover_index` 行之后）添加两个新列：

```sql
    cover_index INTEGER DEFAULT 0,
    rating INTEGER DEFAULT 0,
    review TEXT
```

- [ ] **Step 4: 验证数据库变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 5: Commit**

```bash
git add lib/core/database/database_helper.dart
git commit -m "feat(db): 添加 rating 和 review 列，数据库升级至 v3"
```

---

### Task 2: Game 模型 — 添加 rating 和 review 字段

**Files:**
- Modify: `lib/core/models/models.dart:17-138`

- [ ] **Step 1: 添加字段定义**

在 Game 类的字段列表中（`coverIndex` 字段之后，约第 34 行后）添加：

```dart
  final int rating;           // 评分 0-5
  final String? review;       // 评论内容
```

- [ ] **Step 2: 更新构造函数**

在 Game 构造函数中添加参数（`this.coverIndex = 0` 之后）：

```dart
    this.rating = 0,
    this.review,
```

- [ ] **Step 3: 更新 fromMap 工厂方法**

在 `Game.fromMap` 中（读取 `coverIndex` 之后）添加：

```dart
        rating: map['rating'] as int? ?? 0,
        review: map['review'] as String?,
```

- [ ] **Step 4: 更新 toMap 方法**

在 `toMap` 方法中（写入 `cover_index` 之后）添加：

```dart
        'rating': rating,
        if (review != null) 'review': review,
```

- [ ] **Step 5: 更新 copyWith 方法**

在 `copyWith` 方法的参数列表中添加：

```dart
    Object? rating = _undefined,
    Object? review = _undefined,
```

在 copyWith 的返回语句中添加：

```dart
      rating: identical(rating, _undefined) ? this.rating : rating as int,
      review: identical(review, _undefined) ? this.review : review as String?,
```

- [ ] **Step 6: 验证模型变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 7: Commit**

```bash
git add lib/core/models/models.dart
git commit -m "feat(model): Game 模型添加 rating 和 review 字段"
```

---

### Task 3: GameRepository — 添加评分评论更新方法

**Files:**
- Modify: `lib/core/repositories/game_repository.dart:313-320`

- [ ] **Step 1: 添加 updateRatingReview 方法**

在 `game_repository.dart` 中（`updateCoverIndex` 方法之后，约第 320 行后）添加：

```dart
  /// 更新游戏评分和评论
  Future<void> updateRatingReview(int id, int rating, String? review) async {
    final db = await _db.database;
    await db.update(
      'games',
      {
        'rating': rating,
        'review': review,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
```

- [ ] **Step 2: 验证变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 3: Commit**

```bash
git add lib/core/repositories/game_repository.dart
git commit -m "feat(repo): 添加 updateRatingReview 方法"
```

---

### Task 4: 排序逻辑 — 评分优先排序

**Files:**
- Modify: `lib/ui/widgets/game_list_widget.dart:112-140`

- [ ] **Step 1: 修改 _sortGames 方法**

在 `_sortGames` 方法中，收藏优先排序之后、switch 之前，添加评分排序权重。修改后的完整方法：

```dart
  List<Game> _sortGames(List<Game> games) {
    final sorted = List<Game>.from(games);
    sorted.sort((a, b) {
      // 收藏优先
      final fav = (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0);
      if (fav != 0) return fav;
      // 评分高的优先（仅在已玩/已通关页面生效）
      if (widget.contextMenuMode == ContextMenuMode.played || widget.isClearedPage) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) return ratingDiff;
      }
      switch (_sortMode) {
        case SortMode.titleAsc:
          return (a.title ?? '').compareTo(b.title ?? '');
        case SortMode.titleDesc:
          return (b.title ?? '').compareTo(a.title ?? '');
        case SortMode.addedTimeDesc:
          return (b.addedTime ?? DateTime.now()).compareTo(a.addedTime ?? DateTime.now());
        case SortMode.addedTimeAsc:
          return (a.addedTime ?? DateTime.now()).compareTo(b.addedTime ?? DateTime.now());
        case SortMode.recentlyPlayedDesc:
          return (b.lastPlayedTime ?? epoch0).compareTo(a.lastPlayedTime ?? epoch0);
        case SortMode.recentlyPlayedAsc:
          return (a.lastPlayedTime ?? epoch0).compareTo(b.lastPlayedTime ?? epoch0);
      }
    });
    return sorted;
  }
```

- [ ] **Step 2: 验证变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/widgets/game_list_widget.dart
git commit -m "feat(sort): 已玩/已通关页面评分高的游戏优先排序"
```

---

### Task 5: 评分评论对话框

**Files:**
- Modify: `lib/ui/widgets/game_list_widget.dart` (在文件末尾 class 结束前添加)

- [ ] **Step 1: 添加 _showReviewDialog 方法**

在 `game_list_widget.dart` 的 `_GameListWidgetState` 类中（`_showContextMenu` 方法之后）添加：

```dart
  void _showReviewDialog(Game game) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ReviewDialog(
        game: game,
        onSave: (rating, review) async {
          final repo = ref.read(gameRepositoryProvider);
          await repo.updateRatingReview(game.id!, rating, review.isEmpty ? null : review);
          // Refresh providers
          ref.invalidate(allGamesProvider);
          ref.invalidate(playedGamesProvider);
          ref.invalidate(clearedGamesProvider);
          ref.invalidate(favoriteGamesProvider);
        },
      ),
    );
  }
```

- [ ] **Step 2: 添加 _ReviewDialog 组件**

在 `game_list_widget.dart` 文件末尾（`_GameListWidgetState` 类结束后）添加对话框组件：

```dart
class _ReviewDialog extends StatefulWidget {
  final Game game;
  final void Function(int rating, String review) onSave;

  const _ReviewDialog({required this.game, required this.onSave});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late int _rating;
  late TextEditingController _reviewController;

  @override
  void initState() {
    super.initState();
    _rating = widget.game.rating;
    _reviewController = TextEditingController(text: widget.game.review ?? '');
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.game.title ?? '未命名游戏',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            const Text(
              '评分',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () => setState(() => _rating = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      size: 32,
                      color: index < _rating ? const Color(0xFFFFD700) : Colors.grey.shade400,
                    ),
                  ),
                );
              }),
            ),
            if (_rating > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$_rating / 5',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              '评论',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              maxLines: 5,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '写下你的评论...',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_rating, _reviewController.text);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 验证变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/game_list_widget.dart
git commit -m "feat(ui): 添加评分评论对话框组件"
```

---

### Task 6: 右键菜单 — 添加"评论"按钮

**Files:**
- Modify: `lib/ui/widgets/game_list_widget.dart:946-1162`

- [ ] **Step 1: 在右键菜单中添加"评论"项**

在 `_showContextMenu` 方法的 `items` 列表中，在 `'cover'` 菜单项之后、`PopupMenuDivider` 之前添加：

```dart
              PopupMenuItem(
                  value: 'review',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.rate_review_outlined, size: 18, color: AppTheme.primaryColor),
                      title: const Text('评论', style: TextStyle(color: AppTheme.textPrimary)))),
```

- [ ] **Step 2: 添加菜单动作处理**

在 `_showContextMenu` 的 `.then((value) async { ... switch(value) { ... } })` 中，`'cover'` case 之前添加：

```dart
              case 'review':
                _showReviewDialog(game);
                break;
```

- [ ] **Step 3: 验证变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/game_list_widget.dart
git commit -m "feat(menu): 右键菜单添加评论按钮"
```

---

### Task 7: 海报卡片 — 左下角显示评分星星

**Files:**
- Modify: `lib/ui/widgets/game_list_widget.dart:732-844`

- [ ] **Step 1: 在海报卡片 Stack 中添加星星显示**

在 `_buildPosterItem` 方法的 `Stack` 中（`Positioned` 收藏按钮之后，`children` 列表末尾）添加：

```dart
                    if (game.rating > 0)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 14, color: Color(0xFFFFD700)),
                              const SizedBox(width: 2),
                              Text(
                                '${game.rating}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
```

- [ ] **Step 2: 验证变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/widgets/game_list_widget.dart
git commit -m "feat(poster): 海报卡片左下角显示评分星星"
```

---

### Task 8: 游戏详情页 — 版本号旁显示星星和评论按钮

**Files:**
- Modify: `lib/ui/pages/games/game_detail_page.dart:484-494`

- [ ] **Step 1: 修改版本号区域，添加星星和评论按钮**

将 `_buildContentPanel` 中的版本号显示代码（行 484-494）替换为包含星星和评论按钮的版本：

原代码：
```dart
          if (widget.game.version != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.game.version ?? '',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
            ),
          ],
```

替换为：
```dart
          if (widget.game.version != null || widget.game.rating > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.game.version != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.game.version ?? '',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
                  ),
                if (widget.game.rating > 0) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) => Icon(
                      index < widget.game.rating ? Icons.star : Icons.star_border,
                      size: 18,
                      color: index < widget.game.rating ? const Color(0xFFFFD700) : Colors.grey.shade400,
                    )),
                  ),
                  if (widget.game.review != null && widget.game.review!.isNotEmpty)
                    Tooltip(
                      message: widget.game.review!,
                      waitDuration: const Duration(milliseconds: 300),
                      child: GestureDetector(
                        onTap: () => _showReviewDetail(context),
                        onDoubleTap: () {
                          Clipboard.setData(ClipboardData(text: widget.game.review!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制评论内容'), duration: Duration(seconds: 1)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.comment, size: 14, color: Colors.red),
                              SizedBox(width: 4),
                              Text('评论', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
```

- [ ] **Step 2: 添加 _showReviewDetail 方法**

在 `_GameDetailDialogState` 类中添加方法：

```dart
  void _showReviewDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.comment, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('评论详情', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: List.generate(5, (index) => Icon(
                  index < widget.game.rating ? Icons.star : Icons.star_border,
                  size: 22,
                  color: index < widget.game.rating ? const Color(0xFFFFD700) : Colors.grey.shade400,
                )),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: SelectableText(
                  widget.game.review ?? '暂无评论',
                  style: const TextStyle(fontSize: 14, height: 1.6, color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.game.review ?? ''));
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('已复制评论内容'), duration: Duration(seconds: 1)),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      // Open edit dialog via parent
                      _openEditReview();
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('编辑'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditReview() {
    // Reuse the same review dialog from GameListWidget
    showDialog(
      context: context,
      builder: (dialogContext) => _DetailReviewDialog(
        game: widget.game,
        onSave: (rating, review) async {
          final repo = ref.read(gameRepositoryProvider);
          await repo.updateRatingReview(widget.game.id!, rating, review.isEmpty ? null : review);
          ref.invalidate(allGamesProvider);
          ref.invalidate(playedGamesProvider);
          ref.invalidate(clearedGamesProvider);
          ref.invalidate(favoriteGamesProvider);
        },
      ),
    );
  }
```

- [ ] **Step 3: 添加 _DetailReviewDialog 组件**

在 `game_detail_page.dart` 文件末尾（`_GameDetailDialogState` 类结束后，`_ImageViewerDialog` 之前或之后）添加：

```dart
class _DetailReviewDialog extends StatefulWidget {
  final Game game;
  final void Function(int rating, String review) onSave;

  const _DetailReviewDialog({required this.game, required this.onSave});

  @override
  State<_DetailReviewDialog> createState() => _DetailReviewDialogState();
}

class _DetailReviewDialogState extends State<_DetailReviewDialog> {
  late int _rating;
  late TextEditingController _reviewController;

  @override
  void initState() {
    super.initState();
    _rating = widget.game.rating;
    _reviewController = TextEditingController(text: widget.game.review ?? '');
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.game.title ?? '未命名游戏',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            const Text('评分', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () => setState(() => _rating = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      size: 32,
                      color: index < _rating ? const Color(0xFFFFD700) : Colors.grey.shade400,
                    ),
                  ),
                );
              }),
            ),
            if (_rating > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$_rating / 5', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
            const SizedBox(height: 20),
            const Text('评论', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              maxLines: 5,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '写下你的评论...',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_rating, _reviewController.text);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 验证变更**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认无编译错误。

- [ ] **Step 5: Commit**

```bash
git add lib/ui/pages/games/game_detail_page.dart
git commit -m "feat(detail): 游戏详情页显示评分星星和评论按钮"
```

---

### Task 9: Providers 刷新 — 确保评分更新后数据同步

**Files:**
- Modify: `lib/core/providers/providers.dart`

- [ ] **Step 1: 确认 invalidated providers**

在 Task 5 和 Task 8 的 `onSave` 回调中，已经 invalidates 了以下 providers：
- `allGamesProvider`
- `playedGamesProvider`
- `clearedGamesProvider`
- `favoriteGamesProvider`

无需额外修改 providers.dart，因为这些 provider 已经存在且会重新从数据库加载数据（包含新的 rating/review 字段）。

- [ ] **Step 2: 验证端到端数据流**

运行 `flutter analyze --no-fatal-infos --no-fatal-warnings`，确认整个数据流无编译错误。

- [ ] **Step 3: Commit（如有修改）**

如果无需修改，跳过此 commit。

---

### Task 10: 更新 CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: 添加更新日志条目**

在 `CHANGELOG.md` 的 v1.0.8 版本的 `### ✨ 新功能` 部分添加：

```markdown
- **游戏评分与评论系统**：为"已玩"和"已通关"页面添加评分评论功能
  - 右键菜单新增"评论"按钮，支持 0-5 星评分和文字评论
  - 海报卡片左下角显示评分星星
  - 高评分游戏在已玩/已通关页面优先排列
  - 游戏详情页版本号旁显示评分星星
  - 红色评论按钮：悬停预览评论、点击查看/编辑详情、双击复制评论内容
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: 更新 CHANGELOG 添加评分评论系统说明"
```

---

## Self-Review Checklist

**1. Spec coverage:**
- ✅ 右键菜单添加评论按钮（Task 6）
- ✅ 评分 0-5 星（Task 5）
- ✅ 写下评论（Task 5）
- ✅ 高评分游戏优先排序（Task 4）
- ✅ 海报卡片左下角显示星星（Task 7）
- ✅ 游戏详情页版本号旁显示星星（Task 8）
- ✅ 红色评论按钮 - 悬停显示评论内容（Task 8, Tooltip）
- ✅ 红色评论按钮 - 点击查看评论详情并可编辑（Task 8, _showReviewDetail）
- ✅ 红色评论按钮 - 双击复制评论内容（Task 8, onDoubleTap）
- ✅ 已玩页面和已通关页面均生效（Task 6, 菜单项无条件显示）

**2. Placeholder scan:** 无 TBD/TODO/占位符。

**3. Type consistency:** `rating` 为 `int`（0-5），`review` 为 `String?`，贯穿所有层（DB → Model → Repository → UI）。
