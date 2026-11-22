import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';
import 'layout_reflow.dart';

class DraggableImageGrid extends StatefulWidget {
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

  @override
  State<DraggableImageGrid> createState() => _DraggableImageGridState();
}

class _DraggableImageGridState extends State<DraggableImageGrid> {
  static const _columns = 4;
  static const _spacing = 8.0;
  static const _aspectRatio = 16 / 9;

  final _gridKey = GlobalKey();
  final _scrollController = ScrollController();
  String? _draggingImagePath;
  Offset? _lastPointerPosition;

  List<GameImage> get images => widget.images;
  int get coverIndex => widget.coverIndex;
  Function(List<GameImage>) get onReorder => widget.onReorder;
  Future<void> Function(int index) get onDelete => widget.onDelete;
  Function(int index) get onTap => widget.onTap;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onGridPointerMove(Offset globalPosition) {
    final draggedPath = _draggingImagePath;
    if (draggedPath == null) return;
    final from = images.indexWhere((image) => image.imagePath == draggedPath);
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (from < 0 || box == null || !box.hasSize) return;

    final local = box.globalToLocal(globalPosition);
    final cellWidth =
        (box.size.width - _spacing * (_columns - 1)) / _columns;
    if (cellWidth <= 0) return;
    final cellHeight = cellWidth / _aspectRatio;
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final column = (local.dx / (cellWidth + _spacing))
        .floor()
        .clamp(0, _columns - 1);
    final row = ((local.dy + scrollOffset) / (cellHeight + _spacing)).floor();
    if (row < 0) return;

    final rawIndex = row * _columns + column;
    var to = rawIndex >= images.length ? images.length : rawIndex;
    if (rawIndex < images.length) {
      final cellStartX = column * (cellWidth + _spacing);
      if (local.dx - cellStartX > cellWidth / 2) to++;
    }
    if (to > from) to--;
    if (to == from) return;

    final order = List<GameImage>.from(images);
    final dragged = order.removeAt(from);
    order.insert(to, dragged);
    onReorder(order);
  }

  void _onImageTap(int index) => onTap(index);

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
              Icon(Icons.add_photo_alternate_outlined, size: GlassConstants.iconPlaceholder, color: AppTheme.getTextPrimary(context).withValues(alpha: 0.3)),
              const SizedBox(height: GlassConstants.spacingSmall),
              Text('暂无图片，点击添加', style: TextStyle(color: AppTheme.getTextPrimary(context).withValues(alpha: 0.5), fontSize: GlassConstants.fontBody)),
            ],
          ),
        ),
      );
    }

    return Listener(
      onPointerMove: (event) {
        _lastPointerPosition = event.position;
        _onGridPointerMove(event.position);
      },
      child: GridView.builder(
      key: _gridKey,
      controller: _scrollController,
      padding: EdgeInsets.zero,
      findChildIndexCallback: (key) {
        final index = images.indexWhere((image) => ValueKey(image.imagePath) == key);
        return index < 0 ? null : index;
      },
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: _spacing,
        mainAxisSpacing: _spacing,
        childAspectRatio: _aspectRatio,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final image = images[index];
        final isCover = index == coverIndex;

        return LayoutReflow(key: ValueKey(image.imagePath), revision: images,
          child: LayoutBuilder(builder: (context, constraints) => DragTarget<GameImage>(
            onWillAcceptWithDetails: (details) => details.data != image && images.contains(details.data),
            builder: (context, candidates, rejected) => Draggable<GameImage>(
              data: image,
              onDragStarted: () {
                _draggingImagePath = image.imagePath;
                final position = _lastPointerPosition;
                if (position != null) _onGridPointerMove(position);
              },
              onDragEnd: (_) => _draggingImagePath = null,
              feedback: Material(color: Colors.transparent, child: SizedBox(width: constraints.maxWidth, height: constraints.maxHeight,
                child: Image.file(File(image.imagePath), fit: BoxFit.contain))),
              childWhenDragging: Container(decoration: BoxDecoration(color: AppTheme.getPrimaryColor(context).withValues(alpha: .1), borderRadius: BorderRadius.circular(GlassConstants.radiusSmall))),
              child: AnimatedContainer(duration: AppMotion.duration(context, AppMotion.fast),
                color: candidates.isEmpty ? Colors.transparent : AppTheme.getPrimaryColor(context).withValues(alpha: .15),
                child: Stack(
          children: [
            GestureDetector(
              onTap: () => _onImageTap(index),
              child: AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.fast),
                curve: AppMotion.curve,
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
                    frameBuilder: appImageFrameBuilder,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
                      child: const Center(child: Icon(Icons.broken_image, size: GlassConstants.iconLarge)),
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
                  padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingTight, vertical: GlassConstants.spacingMicro),
                  decoration: BoxDecoration(
                    color: AppTheme.getPrimaryColor(context),
                    borderRadius: BorderRadius.circular(GlassConstants.radiusTiny),
                  ),
                  child: Text('封面', style: TextStyle(fontSize: GlassConstants.fontBadge, color: AppTheme.getTextColorOnPrimary(context))),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => onDelete(index),
                child: Container(
                  padding: const EdgeInsets.all(GlassConstants.spacingTiny),
                  decoration: BoxDecoration(
                    color: AppTheme.getOverlayColor(context),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: GlassConstants.iconCompact, color: AppTheme.lightForegroundColor),
                ),
              ),
            ),
          ],
        ))))));
      },
      ),
    );
  }
}
