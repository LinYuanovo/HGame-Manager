import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';

class DraggableImageGrid extends StatelessWidget {
  final List<GameImage> images;
  final int coverIndex;
  final Function(List<GameImage>) onReorder;
  final Future<void> Function(int index) onDelete;
  final Function(int index) onTap;

  const DraggableImageGrid({
    super.key,
    required this.images,
    this.coverIndex = 0,
    required this.onReorder,
    required this.onDelete,
    required this.onTap,
  });

  void _onImageTap(int index) {
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 48, color: AppTheme.getTextPrimary(context).withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('暂无图片，点击添加', style: TextStyle(color: AppTheme.getTextPrimary(context).withValues(alpha: 0.5), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final image = images[index];
        final isCover = index == coverIndex;

        return Stack(
          children: [
            GestureDetector(
              onTap: () => _onImageTap(index),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                  border: Border.all(
                    color: isCover
                        ? AppTheme.getPrimaryColor(context)
                        : AppTheme.getBorderColor(context).withValues(alpha: 0.3),
                    width: isCover ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall - 1),
                  child: Image.file(
                    File(image.imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
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
                    color: AppTheme.getPrimaryColor(context),
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
