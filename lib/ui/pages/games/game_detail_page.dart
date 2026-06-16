import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/services/version_check_service.dart';
import '../../../core/services/image_service.dart';
import '../../widgets/image_manager_dialog.dart';

class GameDetailDialog extends ConsumerStatefulWidget {
  final Game game;
  final void Function(Tag tag)? onTagTap;

  const GameDetailDialog({super.key, required this.game, this.onTagTap});

  @override
  ConsumerState<GameDetailDialog> createState() => _GameDetailDialogState();
}

class _GameDetailDialogState extends ConsumerState<GameDetailDialog> {
  bool _isEditing = false;
  late TextEditingController _titleController;
  late TextEditingController _versionController;
  late TextEditingController _introController;
  late TextEditingController _featuresController;
  late TextEditingController _changelogController;
  late TextEditingController _downloadUrlController;
  late TextEditingController _sourceUrlController;
  List<Tag> _editedTags = [];
  late Game _currentGame;

  bool _isImageViewerOpen = false;
  int _currentImageIndex = 0;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _currentGame = widget.game;
    _titleController = TextEditingController(text: _currentGame.title);
    _versionController = TextEditingController(text: _currentGame.version);
    _introController = TextEditingController(text: _currentGame.intro);
    _featuresController = TextEditingController(text: _currentGame.features);
    _changelogController = TextEditingController(text: _currentGame.changelog);
    _downloadUrlController = TextEditingController(text: _currentGame.downloadUrl ?? '');
    _sourceUrlController = TextEditingController(text: _currentGame.sourceUrl ?? '');
    _editedTags = List.from(_currentGame.tags);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _versionController.dispose();
    _introController.dispose();
    _featuresController.dispose();
    _changelogController.dispose();
    _downloadUrlController.dispose();
    _sourceUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.9;
    final dialogHeight = screenSize.height * 0.9;

    return PopScope(
      canPop: !_isImageViewerOpen,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              Container(height: 1, color: AppTheme.borderColor),
              Expanded(child: _buildBody()),
              if (_isEditing) Container(height: 1, color: AppTheme.borderColor),
              if (_isEditing) _buildEditBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor.withValues(alpha: 0.08), Colors.transparent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.videogame_asset, color: AppTheme.primaryColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing ? (_titleController.text.isEmpty ? '游戏详情' : _titleController.text) : (_currentGame.title ?? '游戏详情'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!_isEditing) ...[
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 20, color: AppTheme.textPrimary),
              tooltip: '编辑',
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 22, color: AppTheme.textPrimary),
              tooltip: '关闭 (ESC)',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      children: [
        SizedBox(width: 320, child: _buildLeftPanel()),
        Container(
          width: 1,
          color: AppTheme.borderColor,
        ),
        Expanded(child: _buildContentPanel()),
      ],
    );
  }

  Widget _buildLeftPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageCarousel(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final repo = ref.read(gameRepositoryProvider);
                await repo.markAsPlayed(_currentGame.id!);

                // 尝试查找并启动游戏exe
                final saveService = ref.read(savePathServiceProvider);
                final exePath = saveService.findGameExe(_currentGame.path);
                if (exePath != null) {
                  try {
                    await Process.run(exePath, [], workingDirectory: _currentGame.path);
                  } catch (e) {
                    if (mounted) {
                      AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
                    }
                  }
                } else {
                  // 如果找不到exe，打开游戏文件夹
                  try {
                    await launchUrl(Uri.file(_currentGame.path));
                  } catch (_) {}
                }

                ref.invalidate(allGamesProvider);
                ref.invalidate(playedGamesProvider);
              },
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('开始游玩'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 存档按钮 - 仅在已玩/已通关时显示
          if (_currentGame.isPlayed || _currentGame.playCount > 0)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openSaveLocation(),
                icon: const Icon(Icons.folder_special, size: 18),
                label: const Text('存档'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
                ),
              ),
            ),
          const SizedBox(height: 24),
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildImageCarousel() {
    final images = _currentGame.images;
    
    return Column(
      children: [
        if (images.isEmpty)
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 48, color: AppTheme.textPrimary.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Text('暂无图片', style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.5), fontSize: 13)),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () => setState(() => _currentImageIndex = (_currentImageIndex + 1) % images.length),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium - 1),
                    child: Image.file(
                      File(images[_currentImageIndex].imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.backgroundColor.withValues(alpha: 0.3),
                        child: Center(child: Icon(Icons.broken_image, size: 36, color: AppTheme.textPrimary.withValues(alpha: 0.3))),
                      ),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${_currentImageIndex + 1} / ${images.length}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openImageManager,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('管理图片'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  void _openImageManager() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ImageManagerDialog(game: _currentGame),
    );

    if (result == true) {
      final repo = ref.read(gameRepositoryProvider);
      final freshGame = await repo.getGameById(_currentGame.id!);
      if (freshGame != null && mounted) {
        setState(() {
          _currentGame = freshGame;
          _currentImageIndex = 0;
        });
      }
    }
  }

  void _insertImageToContent(String sectionTitle) async {
    final imageService = ImageService();
    final imagePath = await imageService.pickAndCopyImage();
    if (imagePath == null) return;

    // 获取对应的 TextEditingController
    TextEditingController controller;
    switch (sectionTitle) {
      case '简介':
        controller = _introController;
        break;
      case '特性':
        controller = _featuresController;
        break;
      case '更新日志':
        controller = _changelogController;
        break;
      default:
        return;
    }

    // 在光标位置插入图片标记
    final text = controller.text;
    final selection = controller.selection;
    final imageTag = '\n[图片:$imagePath]\n';
    
    final newText = text.replaceRange(selection.start, selection.end, imageTag);
    controller.text = newText;
    
    // 更新光标位置
    final newCursorPos = selection.start + imageTag.length;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newCursorPos),
    );

    if (mounted) {
      AppTheme.showGlassToast(context, message: '图片已插入');
    }
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags above path (Change 2)
          if (_isEditing) ...[
            _buildEditableTags(),
          ] else if (_currentGame.tags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: {for (final t in _currentGame.tags) t.name.toLowerCase(): t}.values.map((tag) => GestureDetector(
                onTap: () {
                  if (widget.onTagTap != null) {
                    Navigator.of(context).pop(tag);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Text(tag.name, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                ),
              )).toList(),
            ),
            const SizedBox(height: 10),
          ],
          _InfoRow(icon: Icons.folder_outlined, label: '路径', value: _currentGame.path, isPath: true),
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tag, size: 15, color: AppTheme.textPrimary),
                const SizedBox(width: 8),
                const Text('版本:', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _versionController,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.version != null) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.tag, label: '版本', value: _currentGame.version!),
          ],
          const SizedBox(height: 10),
          _InfoRow(
            icon: _currentGame.isPlayed ? Icons.check_circle : Icons.circle_outlined,
            label: '状态',
            value: _currentGame.isPlayed ? '已游玩 (${_currentGame.playCount}次)' : '未游玩',
            valueColor: _currentGame.isPlayed ? AppTheme.successColor : AppTheme.textPrimary,
          ),
          if (_currentGame.lastPlayedTime != null) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.access_time, label: '最后游玩', value: _formatDate(_currentGame.lastPlayedTime!)),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.link, size: 15, color: AppTheme.textPrimary),
                const SizedBox(width: 8),
                const Text('来源:', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _sourceUrlController,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      hintText: '输入来源链接',
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.sourceUrl != null && _currentGame.sourceUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.link, label: '来源', value: _currentGame.sourceUrl!, isLink: true),
          ],
          // 存档路径信息（仅编辑模式或有存档路径时显示）
          if (_isEditing && (_currentGame.isPlayed || _currentGame.playCount > 0)) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.folder_special, size: 15, color: AppTheme.textPrimary),
                const SizedBox(width: 8),
                const Text('存档:', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showEditSavePathDialog(),
                    child: Text(
                      _currentGame.savePath ?? '点击设置存档路径',
                      style: TextStyle(
                        fontSize: 12,
                        color: _currentGame.savePath != null ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.5),
                        decoration: _currentGame.savePath != null ? TextDecoration.underline : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.savePath != null && _currentGame.savePath!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.folder_special, label: '存档', value: _currentGame.savePath!, isPath: true),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.download, size: 15, color: AppTheme.textPrimary),
                const SizedBox(width: 8),
                const Text('下载:', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _downloadUrlController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      isDense: true,
                      hintText: '输入下载链接',
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.downloadUrl != null && _currentGame.downloadUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildDownloadLinks(_currentGame.downloadUrl!),
          ],
        ],
      ),
    );
  }

  Widget _buildEditableTags() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ..._editedTags.map((tag) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tag.name, style: const TextStyle(fontSize: 11, color: Colors.blue)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _editedTags.remove(tag)),
                child: const Icon(Icons.close, size: 12, color: Colors.blue),
              ),
            ],
          ),
        )),
        GestureDetector(
          onTap: () => _showAddTagDialog(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.add, size: 12, color: AppTheme.primaryColor),
          ),
        ),
      ],
    );
  }

  void _showAddTagDialog() {
    final controller = TextEditingController();
    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('添加标签', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '输入标签名称'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      setState(() {
                        _editedTags.add(Tag(name: name, type: Tag.typeCustom));
                      });
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentPanel() {
    final images = _currentGame.images;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isEditing)
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textPrimary, height: 1.4),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                hintText: '输入游戏标题',
              ),
              maxLines: null,
            )
          else
            SelectableText(
              _currentGame.title ?? '未命名游戏', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textPrimary, height: 1.4),
            ),

          if (_currentGame.version != null || _currentGame.rating > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_currentGame.version != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_currentGame.version ?? '',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _isCheckingUpdate ? null : _checkForUpdate,
                          child: _isCheckingUpdate
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                                )
                              : Icon(Icons.system_update, size: 16, color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                  ),
                if (_currentGame.rating > 0) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      if (_currentGame.rating >= starValue) {
                        return const Icon(Icons.star, size: 18, color: Color(0xFFFFD700));
                      } else if (_currentGame.rating >= starValue - 0.5) {
                        return const Icon(Icons.star_half, size: 18, color: Color(0xFFFFD700));
                      } else {
                        return Icon(Icons.star_border, size: 18, color: Colors.grey.shade400);
                      }
                    }),
                  ),
                  if (_currentGame.review != null && _currentGame.review!.isNotEmpty)
                    _HoverReviewButton(
                      review: _currentGame.review!,
                      onTap: () => _showReviewDetail(context),
                      onDoubleTap: () {
                        Clipboard.setData(ClipboardData(text: _currentGame.review!));
                        AppTheme.showGlassToast(context, message: '已复制评论内容');
                      },
                    ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 32),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),

          // Insert images between sections, matching original article layout
          _buildSectionWithImages(title: '简介', icon: Icons.description_outlined, content: _currentGame.intro, images: images, sectionIndex: 0),

          if (_currentGame.features != null && _currentGame.features!.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildSectionWithImages(title: '特性', icon: Icons.stars_outlined, content: _currentGame.features, images: images, sectionIndex: 1),
          ],

          if (_currentGame.changelog != null && _currentGame.changelog!.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildSectionWithImages(title: '更新日志', icon: Icons.history, content: _currentGame.changelog, images: images, sectionIndex: 2),
          ],

          // Show all remaining images at the bottom
          if (images.length > 3) ...[
            const SizedBox(height: 32),
            _buildImageGallery(images.skip(3).toList()),
          ],

          // Show all images in gallery section if there are any images
          if (images.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildAllImagesGallery(images),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionWithImages({
    required String title,
    required IconData icon,
    String? content,
    required List<GameImage> images,
    required int sectionIndex,
  }) {
    // Each section gets 1 image (if available)
    final sectionImage = sectionIndex < images.length ? images[sectionIndex] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        if (_isEditing) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: title == '简介' ? _introController : title == '特性' ? _featuresController : _changelogController,
                  maxLines: null,
                  style: const TextStyle(fontSize: 14, height: 1.7, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    onPressed: () => _insertImageToContent(title),
                    icon: const Icon(Icons.add_photo_alternate, size: 20),
                    tooltip: '插入图片',
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                      foregroundColor: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('插入图片', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ),
        ] else
          _buildRichIntro(content ?? '暂无信息', ref.watch(detailFontSizeProvider)),
        if (sectionImage != null && !_isEditing) ...[
          const SizedBox(height: 16),
          _buildArticleImage(sectionImage),
        ],
      ],
    );
  }

  Widget _buildRichIntro(String content, double fontSize) {
    // 检查是否包含图片标记
    final imagePattern = RegExp(r'\[图片:(.*?)\]');
    if (!imagePattern.hasMatch(content)) {
      // 没有图片标记，使用原来的纯文本显示
      final lines = content.split('\n');
      final spans = <InlineSpan>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimRight();
        final isHeading = RegExp(r'^.{1,6}[：:]\s*$').hasMatch(line);
        if (isHeading && i > 0 && lines[i - 1].trim().isNotEmpty) {
          spans.add(const TextSpan(text: '\n'));
        }
        spans.add(TextSpan(
          text: '$line\n',
          style: isHeading
              ? TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)
              : TextStyle(fontSize: fontSize, height: 1.8, color: AppTheme.textPrimary),
        ));
      }
      return SelectableText.rich(TextSpan(children: spans));
    }

    // 包含图片标记，使用 Column 组合文本和图片
    final parts = content.split(imagePattern);
    final widgets = <Widget>[];
    
    for (var i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        // 文本部分
        final text = parts[i].trim();
        if (text.isNotEmpty) {
          final lines = text.split('\n');
          final spans = <InlineSpan>[];
          for (var j = 0; j < lines.length; j++) {
            final line = lines[j].trimRight();
            final isHeading = RegExp(r'^.{1,6}[：:]\s*$').hasMatch(line);
            if (isHeading && j > 0 && lines[j - 1].trim().isNotEmpty) {
              spans.add(const TextSpan(text: '\n'));
            }
            spans.add(TextSpan(
              text: '$line\n',
              style: isHeading
                  ? TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)
                  : TextStyle(fontSize: fontSize, height: 1.8, color: AppTheme.textPrimary),
            ));
          }
          widgets.add(SelectableText.rich(TextSpan(children: spans)));
        }
      } else {
        // 图片部分
        final imagePath = parts[i];
        final file = File(imagePath);
        if (file.existsSync()) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildDownloadLinks(String downloadUrl) {
    final lines = downloadUrl.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final grouped = <String, List<String>>{};
    final decompressCodes = <String>[];

    for (final line in lines) {
      // Check for decompress code
      final decompressMatch = RegExp(r'解压(?:码|密码)[：:]?\s*(.{1,50})').firstMatch(line);
      if (decompressMatch != null) {
        final code = decompressMatch.group(1)?.trim() ?? '';
        if (code.isNotEmpty) {
          decompressCodes.add(code);
        }
        continue; // Don't add decompress code line to download links
      }

      // Check for labeled download link (e.g., "飞猫直连：https://..." or "飞猫直链① https://...")
      final labeledMatch = RegExp(r'^([^：:]+)[：:]\s*(https?://.+)').firstMatch(line.trim());
      if (labeledMatch != null) {
        final customLabel = labeledMatch.group(1)!.trim();
        final url = labeledMatch.group(2)!.trim();
        grouped.putIfAbsent(customLabel, () => []).add(url);
        continue;
      }

      final uri = RegExp(r'https?://([^/]+)').firstMatch(line);
      final domain = uri?.group(1) ?? '其他';
      final label = _getDomainLabel(domain);
      if (label == '其他') continue;
      grouped.putIfAbsent(label, () => []).add(line.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Download links section
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.download, size: 15, color: AppTheme.textPrimary),
            const SizedBox(width: 8),
            const Text('下载:', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 8),
        ...grouped.entries.map((entry) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...entry.value.map((link) {
                final urlMatch = RegExp('https?://[^\\s"\\)]+').firstMatch(link);
                final url = urlMatch?.group(0) ?? '';
                final extractCodeMatch = RegExp(r'(?:提取码|密码)[：:]\s*(\w+)').firstMatch(link);
                final extractCode = extractCodeMatch?.group(1);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onDoubleTap: () {
                          Clipboard.setData(ClipboardData(text: url));
                          AppTheme.showGlassToast(context, message: '已复制链接');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(entry.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
                        ),
                      ),
                      if (extractCode != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onDoubleTap: () {
                            Clipboard.setData(ClipboardData(text: extractCode));
                            AppTheme.showGlassToast(context, message: '已复制提取码');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                            ),
                            child: const Text('提取码', style: TextStyle(fontSize: 11, color: Colors.orange)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        )),
        // Decompress code section (separate from download links)
        if (decompressCodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.vpn_key_outlined, size: 15, color: AppTheme.textPrimary),
              const SizedBox(width: 8),
              const Text('解压码:', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
              const SizedBox(width: 8),
              ...decompressCodes.map((code) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    AppTheme.showGlassToast(context, message: '已复制解压码');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                    ),
                    child: const Text('解压码', style: TextStyle(fontSize: 11, color: Colors.purple)),
                  ),
                ),
              )),
            ],
          ),
        ],
      ],
    );
  }

  String _getDomainLabel(String domain) {
    if (domain.contains('baidu') || domain.contains('bds')) return '百度网盘';
    if (domain.contains('xunlei')) return '迅雷网盘';
    if (domain.contains('weiyun')) return '微云网盘';
    if (domain.contains('uc.cn') || domain.contains('quark')) return 'UC网盘';
    if (domain.contains('gofile')) return 'GoFile';
    if (domain.contains('mega')) return 'Mega';
    if (domain.contains('mediafire')) return 'MediaFire';
    if (domain.contains('cm1.hk') || domain.contains('cm2.hk') || domain.contains('feimaocloud')) return '飞猫网盘';
    return domain;
  }

  Widget _buildArticleImage(GameImage image) {
    final index = _currentGame.images.indexOf(image);
    return GestureDetector(
      onTap: () => _showImageViewer(index >= 0 ? index : 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Image.file(
            File(image.imagePath!),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  void _showImageViewer(int initialIndex) {
    setState(() => _isImageViewerOpen = true);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => _ImageViewerDialog(
        images: _currentGame.images,
        initialIndex: initialIndex,
        onClose: () {
          setState(() => _isImageViewerOpen = false);
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isImageViewerOpen = false);
    });
  }

  Widget _buildImageGallery(List<GameImage> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('更多图片', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: images.map((img) => _buildArticleImage(img)).toList(),
        ),
      ],
    );
  }

  Widget _buildAllImagesGallery(List<GameImage> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text('全部图片 (${images.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: images.map((img) => _buildArticleImage(img)).toList(),
        ),
      ],
    );
  }

  Widget _buildEditBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor.withValues(alpha: 0.05),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _isEditing = false),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('取消'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textPrimary),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存修改'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    try {
      final repo = ref.read(gameRepositoryProvider);
      final tagRepo = ref.read(tagRepositoryProvider);
      final gameId = _currentGame.id;

      final newTitle = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final newVersion = _versionController.text.trim().isEmpty ? null : _versionController.text.trim();
      final newIntro = _introController.text.trim().isEmpty ? null : _introController.text.trim();
      final newFeatures = _featuresController.text.trim().isEmpty ? null : _featuresController.text.trim();
      final newChangelog = _changelogController.text.trim().isEmpty ? null : _changelogController.text.trim();
      final newDownloadUrl = _downloadUrlController.text.trim().isEmpty ? null : _downloadUrlController.text.trim();
      final newSourceUrl = _sourceUrlController.text.trim().isEmpty ? null : _sourceUrlController.text.trim();

      await repo.updateGame(_currentGame.copyWith(
        title: newTitle,
        version: newVersion,
        intro: newIntro,
        features: newFeatures,
        changelog: newChangelog,
        downloadUrl: newDownloadUrl,
        sourceUrl: newSourceUrl,
        tags: _editedTags,
      ));

      // Update tag relations if game has an id
      if (gameId != null) {
        final existingTags = _currentGame.tags;
        for (final tag in existingTags) {
          if (tag.id != null) {
            await repo.removeTagFromGame(gameId, tag.id!);
          }
        }
        for (final tag in _editedTags) {
          final tagId = await tagRepo.insertOrGetTag(tag.name, tag.type);
          await repo.addTagToGame(gameId, tagId);
        }
      }

      // Sync metadata.json
      try {
        final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
        if (await metadataFile.exists()) {
          final content = await metadataFile.readAsString();
          final metadata = jsonDecode(content) as Map<String, dynamic>;
          if (newTitle != null) metadata['title'] = newTitle;
          if (newVersion != null) metadata['version'] = newVersion;
          if (newIntro != null) metadata['intro'] = newIntro;
          if (newFeatures != null) metadata['features'] = newFeatures;
          if (newChangelog != null) metadata['changelog'] = newChangelog;
          if (newDownloadUrl != null) metadata['download_url'] = newDownloadUrl;
          await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
          debugPrint('[Edit] metadata.json updated for: ${_currentGame.path}');
        }
      } catch (e) {
        debugPrint('[Edit] Failed to update metadata.json: $e');
      }

      // Sync source_url.txt
      if (newSourceUrl != null) {
        try {
          final sourceUrlFile = File('${_currentGame.path}${Platform.pathSeparator}source_url.txt');
          await sourceUrlFile.writeAsString(newSourceUrl, flush: true);
          debugPrint('[Edit] source_url.txt updated: $newSourceUrl');
        } catch (e) {
          debugPrint('[Edit] Failed to update source_url.txt: $e');
        }
      }

      ref.invalidate(allGamesProvider);
      ref.invalidate(allTagsProvider);
      ref.invalidate(allSeriesProvider);
      ref.invalidate(playedGamesProvider);
      ref.invalidate(favoriteGamesProvider);
      ref.invalidate(clearedGamesProvider);

      // 更新本地状态以实现实时刷新
      final freshGame = await repo.getGameById(gameId!);
      if (freshGame != null && mounted) {
        setState(() {
          _currentGame = freshGame;
          _isEditing = false;
          _titleController.text = freshGame.title ?? '';
          _versionController.text = freshGame.version ?? '';
          _introController.text = freshGame.intro ?? '';
          _featuresController.text = freshGame.features ?? '';
          _changelogController.text = freshGame.changelog ?? '';
          _downloadUrlController.text = freshGame.downloadUrl ?? '';
          _sourceUrlController.text = freshGame.sourceUrl ?? '';
          _editedTags = List.from(freshGame.tags);
        });

        if (newSourceUrl != null && newSourceUrl != _currentGame.sourceUrl) {
          final shouldRescrape = await showGlassDialog<bool>(
            context: context,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('重新刮削', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  const Text('来源链接已修改，是否立即重新刮削该游戏？', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('稍后手动刮削'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('立即刮削'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          if (shouldRescrape == true && mounted) {
            Navigator.of(context).pop();
            AppTheme.showGlassToast(context, message: '请在刮削页面点击"扫描游戏库"后刮削该游戏');
            return;
          }
        }

        AppTheme.showGlassToast(context, message: '保存成功');
      } else if (mounted) {
        setState(() => _isEditing = false);
        AppTheme.showGlassToast(context, message: '保存成功');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '保存失败: $e');
      }
    }
  }

  void _openSaveLocation() async {
    if (_currentGame.savePath == null || _currentGame.savePath!.isEmpty) {
      _showEditSavePathDialog();
      return;
    }

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('打开存档位置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(
              '该存档位置为自动扫描结果，可能存在错误。\n\n${_currentGame.savePath}',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                    _showEditSavePathDialog();
                  },
                  child: const Text('修改路径'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('打开'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await launchUrl(Uri.file(_currentGame.savePath!));
      } catch (e) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '无法打开路径: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
      }
    }
  }

  void _showEditSavePathDialog() {
    final controller = TextEditingController(text: _currentGame.savePath ?? '');
    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑存档路径', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入存档文件夹路径',
                labelText: '存档路径',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final newPath = controller.text.trim();
                    final repo = ref.read(gameRepositoryProvider);
                    await repo.updateSavePath(_currentGame.id!, newPath.isEmpty ? null : newPath);
                    final freshGame = await repo.getGameById(_currentGame.id!);
                    if (freshGame != null && mounted) {
                      setState(() => _currentGame = freshGame);
                    }
                    ref.invalidate(allGamesProvider);
                    ref.invalidate(playedGamesProvider);
                    Navigator.pop(context);
                    AppTheme.showGlassToast(context, message: '存档路径已更新');
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    if (_currentGame.title == null || _currentGame.title!.isEmpty) {
      AppTheme.showGlassToast(context, message: '游戏标题为空，无法检查更新');
      return;
    }

    setState(() => _isCheckingUpdate = true);
    AppTheme.showGlassToast(context, message: '正在检查更新...', icon: Icons.system_update, iconColor: AppTheme.primaryColor);

    try {
      final service = VersionCheckService();
      final result = await service.checkForUpdate(
        _currentGame.title!,
        _currentGame.version ?? '',
      );

      if (!mounted) return;

      setState(() => _isCheckingUpdate = false);

      if (result != null) {
        _showUpdateDialog(result);
      } else {
        AppTheme.showGlassToast(context, message: '未发现新版本');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        AppTheme.showGlassToast(context, message: '检查更新失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  void _showUpdateDialog(VersionCheckResult result) {
    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: AppTheme.successColor, size: 22),
                const SizedBox(width: 8),
                const Text('发现新版本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 16),
            Text('来源: ${result.siteName}', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text('当前版本: ${_currentGame.version ?? "未知"}', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text('最新版本: ${result.maxVersion}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.successColor)),
            const SizedBox(height: 8),
            Text('帖子标题: ${result.postTitle}', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: result.downloadUrl == null
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          try {
                            await launchUrl(Uri.parse(result.downloadUrl!));
                          } catch (_) {}
                        },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('前往下载'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showReviewDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _DetailReviewDialog(
        game: _currentGame,
        onSave: (rating, review) async {
          try {
            final repo = ref.read(gameRepositoryProvider);
            var gameId = _currentGame.id;
            if (gameId == null) {
              debugPrint('[Review] Game has no id, inserting into DB: ${_currentGame.path}');
              gameId = await repo.insertGame(_currentGame);
              debugPrint('[Review] Inserted game with id: $gameId');
            }
            await repo.updateRatingReview(gameId, rating, review.isEmpty ? null : review);
            debugPrint('[Review] Updated rating=$rating, review=${review.isEmpty ? "null" : review} for game id=$gameId');
            ref.invalidate(allGamesProvider);
            ref.invalidate(playedGamesProvider);
            ref.invalidate(clearedGamesProvider);
            ref.invalidate(favoriteGamesProvider);
            if (mounted) {
              AppTheme.showGlassToast(context, message: '评论已保存');
            }
          } catch (e, stackTrace) {
            debugPrint('[Review] Error saving review: $e\n$stackTrace');
            if (mounted) {
              AppTheme.showGlassToast(
                context,
                message: '保存失败: $e',
                icon: Icons.error_outline,
                iconColor: AppTheme.errorColor,
              );
            }
          }
        },
        onDelete: () async {
          try {
            final repo = ref.read(gameRepositoryProvider);
            var gameId = _currentGame.id;
            if (gameId == null) {
              debugPrint('[Review] Game has no id, inserting into DB: ${_currentGame.path}');
              gameId = await repo.insertGame(_currentGame);
              debugPrint('[Review] Inserted game with id: $gameId');
            }
            await repo.deleteRatingReview(gameId);
            debugPrint('[Review] Deleted rating/review for game id=$gameId');
            ref.invalidate(allGamesProvider);
            ref.invalidate(playedGamesProvider);
            ref.invalidate(clearedGamesProvider);
            ref.invalidate(favoriteGamesProvider);
            if (mounted) {
              AppTheme.showGlassToast(context, message: '评论已删除');
            }
          } catch (e, stackTrace) {
            debugPrint('[Review] Error deleting review: $e\n$stackTrace');
            if (mounted) {
              AppTheme.showGlassToast(
                context,
                message: '删除失败: $e',
                icon: Icons.error_outline,
                iconColor: AppTheme.errorColor,
              );
            }
          }
        },
      ),
    );
  }
}

class _HoverReviewButton extends StatefulWidget {
  final String review;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _HoverReviewButton({
    required this.review,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_HoverReviewButton> createState() => _HoverReviewButtonState();
}

class _HoverReviewButtonState extends State<_HoverReviewButton> {
  OverlayEntry? _overlayEntry;

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.6;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        left: MediaQuery.of(context).size.width / 2 - 180,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 360,
              constraints: BoxConstraints(maxHeight: maxHeight),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.comment, size: 14, color: Colors.red),
                      SizedBox(width: 6),
                      Text('评论预览', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        widget.review,
                        style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try { _showOverlay(); } catch (_) {}
          }
        });
      },
      onExit: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _removeOverlay();
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
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
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isPath;
  final bool isLink;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isPath = false,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.textPrimary),
        const SizedBox(width: 8),
        Text('$label:', style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
        const SizedBox(width: 6),
        Expanded(
          child: isLink
              ? InkWell(
                  onTap: () async { try { await launchUrl(Uri.parse(value)); } catch (_) {} },
                  child: Text(value, style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor, decoration: TextDecoration.underline), maxLines: 2, overflow: TextOverflow.ellipsis),
                )
              : SelectableText(
                  value,
                  style: TextStyle(fontSize: 12, color: valueColor ?? AppTheme.textPrimary),
                  maxLines: isPath ? 2 : 1,
                ),
        ),
      ],
    );
  }
}

class _DetailReviewDialog extends StatefulWidget {
  final Game game;
  final void Function(double rating, String review) onSave;
  final VoidCallback onDelete;

  const _DetailReviewDialog({required this.game, required this.onSave, required this.onDelete});

  @override
  State<_DetailReviewDialog> createState() => _DetailReviewDialogState();
}

class _DetailReviewDialogState extends State<_DetailReviewDialog> {
  late double _rating;
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

  double _calcRatingFromX(double x, double totalWidth) {
    final starWidth = totalWidth / 5;
    final rawRating = x / starWidth;
    final clamped = rawRating.clamp(0.0, 5.0);
    return (clamped * 2).round() / 2;
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
            Row(
              children: [
                const Icon(Icons.comment, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.game.title ?? '未命名游戏',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('评分', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                const starSize = 32.0;
                const starGap = 4.0;
                const starAreaWidth = 5 * (starSize + starGap) - starGap;
                return Listener(
                  onPointerDown: (event) {
                    final newRating = _calcRatingFromX(event.localPosition.dx, starAreaWidth);
                    if (newRating != _rating) setState(() => _rating = newRating);
                  },
                  onPointerMove: (event) {
                    final newRating = _calcRatingFromX(event.localPosition.dx, starAreaWidth);
                    if (newRating != _rating) setState(() => _rating = newRating);
                  },
                  child: Row(
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      IconData icon;
                      if (_rating >= starValue) {
                        icon = Icons.star;
                      } else if (_rating >= starValue - 0.5) {
                        icon = Icons.star_half;
                      } else {
                        icon = Icons.star_border;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: starGap),
                        child: Icon(
                          icon,
                          size: starSize,
                          color: icon == Icons.star_border ? Colors.grey.shade400 : const Color(0xFFFFD700),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
            if (_rating > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _rating == _rating.roundToDouble() ? '${_rating.toInt()} / 5' : '$_rating / 5',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    widget.onDelete();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.errorColor),
                  label: const Text('删除', style: TextStyle(color: AppTheme.errorColor)),
                ),
                Row(
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
          ],
        ),
      ),
    );
  }
}

class _ImageViewerDialog extends StatefulWidget {
  final List<GameImage> images;
  final int initialIndex;
  final VoidCallback onClose;

  const _ImageViewerDialog({required this.images, required this.initialIndex, required this.onClose});

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late int _currentIndex;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _previous() {
    if (_currentIndex > 0) setState(() => _currentIndex--);
  }

  void _next() {
    if (_currentIndex < widget.images.length - 1) setState(() => _currentIndex++);
  }

  void _close() {
    widget.onClose();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final viewerW = screenSize.width * 0.8;
    final viewerH = screenSize.height * 0.8;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _close();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previous();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _next();
          }
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: _close,
          child: Container(
            width: screenSize.width,
            height: screenSize.height,
            color: Colors.transparent,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {}, // Prevent closing when clicking on image area
              child: Container(
                width: viewerW,
                height: viewerH,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
                  border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Image area - use most of the space
                    Positioned.fill(
                      child: Row(
                        children: [
                          // Left navigation area
                          SizedBox(
                            width: 60,
                            child: GestureDetector(
                              onTap: _previous,
                              child: Container(
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: _currentIndex > 0
                                    ? Icon(Icons.chevron_left, size: 48, color: AppTheme.textPrimary.withValues(alpha: 0.5))
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          // Center image - takes most of the width
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: widget.images.isNotEmpty && _currentIndex < widget.images.length
                                    ? Image.file(
                                        File(widget.images[_currentIndex].imagePath!),
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 64, color: AppTheme.textPrimary.withValues(alpha: 0.3)),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          // Right navigation area
                          SizedBox(
                            width: 60,
                            child: GestureDetector(
                              onTap: _next,
                              child: Container(
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: _currentIndex < widget.images.length - 1
                                    ? Icon(Icons.chevron_right, size: 48, color: AppTheme.textPrimary.withValues(alpha: 0.5))
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Close button - top right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _close,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundColor.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close, size: 22, color: AppTheme.textPrimary),
                          ),
                        ),
                      ),
                    ),
                    // Counter - top left
                    Positioned(
                      top: 12,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${_currentIndex + 1} / ${widget.images.length}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
