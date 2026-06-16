import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';

class DraggableImageGrid extends StatefulWidget {
  final List<GameImage> images;
  final Function(List<GameImage>) onReorder;
  final Function(int index) onDelete;
  final Function(int index) onTap;
  final int? coverIndex;

  const DraggableImageGrid({
    super.key,
    required this.images,
    required this.onReorder,
    required this.onDelete,
    required this.onTap,
    this.coverIndex,
  });

  @override
  State<DraggableImageGrid> createState() => _DraggableImageGridState();
}

class _DraggableImageGridState extends State<DraggableImageGrid> {
  late List<GameImage> _images;
  int? _dragTargetIndex;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.images);
  }

  @override
  void didUpdateWidget(DraggableImageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.images != oldWidget.images) {
      _images = List.from(widget.images);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);
      _dragTargetIndex = null;
    });
    widget.onReorder(_images);
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final image = _images[index];
        final isCover = index == 0;

        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.8,
              child: SizedBox(
                width: 120,
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
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
          ),
          childWhenDragging: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
              border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
              color: AppTheme.backgroundColor.withValues(alpha: 0.15),
            ),
          ),
          onDragStarted: () => setState(() => _dragTargetIndex = index),
          onDragEnd: (_) => setState(() => _dragTargetIndex = null),
          child: DragTarget<int>(
            onWillAcceptWithDetails: (details) {
              setState(() => _dragTargetIndex = index);
              return details.data != index;
            },
            onLeave: (_) {
              if (_dragTargetIndex == index) {
                setState(() => _dragTargetIndex = null);
              }
            },
            onAcceptWithDetails: (details) {
              _onReorder(details.data, index);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = _dragTargetIndex == index && candidateData.isNotEmpty;

              return Stack(
                children: [
                  GestureDetector(
                    onTap: () => widget.onTap(index),
                    child: AnimatedContainer(
                      duration: GlassConstants.animFast,
                      curve: GlassConstants.animCurve,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                        border: Border.all(
                          color: isHovered
                              ? AppTheme.primaryColor
                              : isCover
                                  ? AppTheme.primaryColor
                                  : AppTheme.borderColor.withValues(alpha: 0.3),
                          width: isCover || isHovered ? 2 : 1,
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
                      onTap: () => widget.onDelete(index),
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
          ),
        );
      },
    );
  }
}
