import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_motion.dart';

class SelectionSurface extends StatelessWidget {
  const SelectionSurface(
      {super.key,
      required this.index,
      required this.decoration,
      required this.child,
      this.insets = EdgeInsets.zero});
  final int index;
  final BoxDecoration decoration;
  final EdgeInsets insets;
  final Flex child;

  @override
  Widget build(BuildContext context) => AppMotionValue(
      key: ValueKey(index >= 0),
      target: index.toDouble(),
      builder: (context, position, child) => _Surface(
          position: position,
          decoration: decoration,
          insets: insets,
          child: child!),
      child: child);
}

class _Surface extends SingleChildRenderObjectWidget {
  const _Surface(
      {required this.position,
      required this.decoration,
      required this.insets,
      required super.child});
  final double position;
  final BoxDecoration decoration;
  final EdgeInsets insets;
  @override
  _RenderSurface createRenderObject(BuildContext context) =>
      _RenderSurface(position, decoration, insets);
  @override
  void updateRenderObject(BuildContext context, _RenderSurface renderObject) =>
      renderObject.update(position, decoration, insets);
}

class _RenderSurface extends RenderProxyBox {
  _RenderSurface(this._position, this._decoration, this._insets);
  double _position;
  BoxDecoration _decoration;
  EdgeInsets _insets;
  BoxPainter? _painter;
  void update(double position, BoxDecoration decoration, EdgeInsets insets) {
    if (_position == position && _decoration == decoration && _insets == insets)
      return;
    if (_decoration != decoration) {
      _painter?.dispose();
      _painter = null;
      _decoration = decoration;
    }
    _position = position;
    _insets = insets;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = child! as RenderFlex;
    if (_position >= 0 && layout.childCount > 0) {
      final slot = _position.clamp(0.0, (layout.childCount - 1).toDouble());
      var row = layout.firstChild!;
      for (var index = 0; index < slot.floor(); index++) {
        row = layout.childAfter(row)!;
      }
      Rect bounds(RenderBox box) =>
          (box.parentData! as FlexParentData).offset & box.size;
      final rect = _insets.deflateRect(Rect.lerp(bounds(row),
          bounds(layout.childAfter(row) ?? row), slot - slot.floor())!);
      (_painter ??= _decoration.createBoxPainter()).paint(context.canvas,
          offset + rect.topLeft, ImageConfiguration(size: rect.size));
    }
    super.paint(context, offset);
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}
