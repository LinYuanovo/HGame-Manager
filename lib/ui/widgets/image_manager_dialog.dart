import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../core/services/image_service.dart';
import '../../core/utils/game_data_paths.dart';
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final imagePaths =
          await _imageService.pickAndCopyImagesToGameDir(widget.game.path);
      if (!mounted) return;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addImageFromUrl() async {
    final controller = TextEditingController();
    final url = await showAppDialog<String>(
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

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final sourceUrl = widget.game.sourceUrl ?? '';
      final headers = sourceUrl.isNotEmpty
          ? await buildScrapeImageHeaders(sourceUrl)
          : <String, String>{};
      final imagePath = await _imageService.downloadImageFromUrlToGameDir(
        url,
        widget.game.path,
        headers: headers,
      );
      if (!mounted) return;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteImage(int index) async {
    final cover = _images.isEmpty ? null : _images[_coverIndex.clamp(0, _images.length - 1)].imagePath;
    setState(() {
      _images = List<GameImage>.from(_images)..removeAt(index);
      _coverIndex = _images.indexWhere((image) => image.imagePath == cover);
      if (_coverIndex < 0) _coverIndex = 0;
    });
  }

  void _reorderImages(List<GameImage> newOrder) {
    final cover = _images.isEmpty ? null : _images[_coverIndex.clamp(0, _images.length - 1)].imagePath;
    setState(() { _images = newOrder; _coverIndex = newOrder.indexWhere((image) => image.imagePath == cover).clamp(0, newOrder.length - 1); });
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(gameRepositoryProvider);
      final gameId = widget.game.id!;

      await repo.setGameImages(gameId, _images, coverIndex: _coverIndex);
      for (final image in widget.game.images) {
        if (!_images.any((retained) => retained.imagePath == image.imagePath) &&
            GameDataPaths.isManagedImagePath(widget.game.path, image.imagePath)) {
          try { await _imageService.deleteImageFile(image.imagePath); } catch (_) {}
        }
      }

      // 刷新数据
      if (!mounted) return;
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
      if (mounted) setState(() => _isLoading = false);
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
        padding: const EdgeInsets.all(GlassConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library,
                    color: AppTheme.getPrimaryColor(context), size: GlassConstants.iconMedium),
                const SizedBox(width: GlassConstants.spacingCompact),
                Expanded(
                  child: Text(
                    '图片管理 - ${widget.game.title ?? "未命名游戏"}',
                    style: AppTypography.dialogTitle(context),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: AppTheme.getTextSecondary(context),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: GlassConstants.spacingMedium),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _addLocalImage,
                    icon: const Icon(Icons.folder_open, size: GlassConstants.iconAction),
                    label: const Text('本地图片'),
                  ),
                ),
                const SizedBox(width: GlassConstants.spacingCompact),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _addImageFromUrl,
                    icon: const Icon(Icons.link, size: GlassConstants.iconAction),
                    label: const Text('URL图片'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GlassConstants.spacingSmall),
            SizedBox(
              height: 20,
              child: Row(children: [
                if (_isLoading) ...[
                  const SizedBox(width: 16, height: 16,
                      child: AppProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: GlassConstants.spacingSmall),
                ],
                Text(
                  _isLoading ? '正在处理图片…' : '拖动图片调整顺序，点击图片设为封面',
                  style: TextStyle(fontSize: GlassConstants.fontSmall,
                      color: AppTheme.getTextSecondary(context)),
                ),
              ]),
            ),
            const SizedBox(height: GlassConstants.spacingMedium),
            Expanded(
              child: _isLoading && _images.isEmpty
                  ? const AppSkeleton(
                      layout: SkeletonLayout.posters, columns: 4,
                      label: '正在处理图片')
                  : ExcludeFocus(
                    excluding: _isLoading,
                    child: AbsorbPointer(
                      absorbing: _isLoading,
                      child: DraggableImageGrid(
                      images: _images,
                      coverIndex: _coverIndex,
                      onReorder: _reorderImages,
                      onDelete: _deleteImage,
                      onTap: (index) {
                        setState(() => _coverIndex = index);
                      },
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: GlassConstants.spacingMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消',
                      style:
                          TextStyle(color: AppTheme.getTextSecondary(context))),
                ),
                const SizedBox(width: GlassConstants.spacingCompact),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveChanges,
                  icon: const Icon(Icons.save, size: GlassConstants.iconAction),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
