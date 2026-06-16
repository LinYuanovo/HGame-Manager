import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../core/services/image_service.dart';
import '../theme/app_theme.dart';
import 'draggable_image_grid.dart';

class ImageManagerDialog extends ConsumerStatefulWidget {
  final Game game;

  const ImageManagerDialog({super.key, required this.game});

  @override
  ConsumerState<ImageManagerDialog> createState() => _ImageManagerDialogState();
}

class _ImageManagerDialogState extends ConsumerState<ImageManagerDialog> {
  late List<GameImage> _images;
  final ImageService _imageService = ImageService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.game.images);
  }

  Future<void> _addLocalImage() async {
    setState(() => _isLoading = true);
    try {
      final imagePaths = await _imageService.pickAndCopyImages();
      if (imagePaths.isNotEmpty) {
        setState(() {
          for (final path in imagePaths) {
            _images.add(GameImage(
              gameId: widget.game.id!,
              imagePath: path,
              sortOrder: _images.length,
            ));
          }
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addImageFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从URL添加图片'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入图片URL',
            labelText: '图片地址',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final imagePath = await _imageService.downloadImageFromUrl(url);
      if (imagePath != null) {
        final newImage = GameImage(
          gameId: widget.game.id!,
          imagePath: imagePath,
          sortOrder: _images.length,
        );
        setState(() => _images.add(newImage));
      } else {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '下载图片失败');
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _deleteImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _reorderImages(List<GameImage> newOrder) {
    setState(() => _images = newOrder);
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(gameRepositoryProvider);
      final gameId = widget.game.id!;

      // 删除原有图片记录
      await repo.deleteGameImagesByGameId(gameId);

      // 添加新图片记录
      for (int i = 0; i < _images.length; i++) {
        await repo.addGameImage(gameId, _images[i].imagePath, i);
      }

      // 刷新数据
      ref.invalidate(allGamesProvider);
      ref.invalidate(playedGamesProvider);
      ref.invalidate(favoriteGamesProvider);
      ref.invalidate(clearedGamesProvider);

      if (mounted) {
        Navigator.pop(context, true);
        AppTheme.showGlassToast(context, message: '图片保存成功');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '保存失败: $e');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_library, color: AppTheme.primaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '图片管理 - ${widget.game.title ?? "未命名游戏"}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _addLocalImage,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('本地图片'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _addImageFromUrl,
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('URL图片'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '点击图片设为封面，封面将显示在第一张',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : DraggableImageGrid(
                      images: _images,
                      onReorder: _reorderImages,
                      onDelete: _deleteImage,
                      onTap: (_) {},
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveChanges,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
