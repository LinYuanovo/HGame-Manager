import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';

class DraggableImageGrid extends StatelessWidget {
  final List<GameImage> images;
  final Function(List<GameImage>) onReorder;
  final Function(int index) onDelete;
  final Function(int index) onTap;

  const DraggableImageGrid({
    super.key,
    required this.images,
    required this.onReorder,
    required this.onDelete,
    required this.onTap,
  });

  void _onImageTap(int index) {
    // 将选中的图片移到第一位作为封面
    final selectedImage = images.removeAt(index);
    images.insert(0, selectedImage);
    onReorder(images);
  }

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 48, color: AppTheme.textPrimary.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('暂无图片，点击添加', style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.5), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final image = images[index];
        final isCover = index == 0;

        return Stack(
          children: [
            GestureDetector(
              onTap: () => _onImageTap(index),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                  border: Border.all(
                    color: isCover
                        ? AppTheme.primaryColor
                        : AppTheme.borderColor.withValues(alpha: 0.3),
                    width: isCover ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall - 1),
                  child: Image.file(
                    File(image.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.backgroundColor.withValues(alpha: 0.3),
                      child: const Center(child: Icon(Icons.broken_image, size: 32)),
                    ),
                  ),
                ),
              ),
            ),
            if (isCover)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('封面', style: TextStyle(fontSize: 10, color: Colors.white)),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => onDelete(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
