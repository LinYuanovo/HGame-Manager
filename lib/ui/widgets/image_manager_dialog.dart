import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../core/services/image_service.dart';
import '../../core/utils/proxy_client.dart';
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
  late int _coverIndex;
  final ImageService _imageService = ImageService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.game.images);
    _coverIndex = widget.game.coverIndex;
  }

  Future<void> _addLocalImage() async {
    setState(() => _isLoading = true);
    try {
      final imagePaths = await _imageService.pickAndCopyImagesToGameDir(widget.game.path);
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
      final sourceUrl = widget.game.sourceUrl ?? '';
      final headers = sourceUrl.isNotEmpty ? await buildScrapeHeaders(sourceUrl) : <String, String>{};
      final imagePath = await _imageService.downloadImageFromUrl(url, headers: headers);
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

  Future<void> _deleteImage(int index) async {
    final image = _images[index];
    // 删除应用存储目录下的图片
    final storageDir = await _imageService.getImageStorageDir();
    if (image.imagePath.startsWith(storageDir)) {
      await _imageService.deleteImageFile(image.imagePath);
    }
    // 删除游戏目录 images 文件夹下的图片（刮削下载的图片）
    final gameImagesDir = '${widget.game.path}${Platform.pathSeparator}images';
    if (image.imagePath.startsWith(gameImagesDir)) {
      await _imageService.deleteImageFile(image.imagePath);
    }
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

      // 更新封面索引
      if (_coverIndex < _images.length) {
        await repo.updateCoverIndex(gameId, _coverIndex);
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
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.5,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(color: AppTheme.getBorderColor(context)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library, color: AppTheme.getPrimaryColor(context), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '图片管理 - ${widget.game.title ?? "未命名游戏"}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: AppTheme.getTextSecondary(context),
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
                      foregroundColor: AppTheme.getPrimaryColor(context),
                      side: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
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
                      foregroundColor: AppTheme.getPrimaryColor(context),
                      side: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '点击图片设为封面，封面将显示在第一张',
              style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : DraggableImageGrid(
                      images: _images,
                      coverIndex: _coverIndex,
                      onReorder: _reorderImages,
                      onDelete: _deleteImage,
                      onTap: (index) {
                        setState(() => _coverIndex = index);
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: AppTheme.getTextSecondary(context))),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveChanges,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getPrimaryColor(context),
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
