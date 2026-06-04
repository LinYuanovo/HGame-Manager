import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 侧边栏状态控制器，管理侧边栏的宽度、展开/折叠状态
class SidebarController extends ChangeNotifier {
  double _width;
  final double _minWidth;
  final double _maxWidth;
  double _targetWidth;

  SidebarController({
    double width = LayoutConstants.sidebarWidth,
    double minWidth = LayoutConstants.minSidebarWidth,
    double maxWidth = LayoutConstants.maxSidebarWidth,
  })  : _width = width,
        _targetWidth = width,
        _minWidth = minWidth,
        _maxWidth = maxWidth;

  double get width => _width;
  bool get isExpanded => _width > 100;

  /// 根据拖拽增量更新侧边栏宽度
  void updateWidth(double delta) {
    final newWidth = (_width - delta).clamp(_minWidth, _maxWidth);
    if (newWidth != _width) {
      _width = newWidth;
      _targetWidth = newWidth;
      notifyListeners();
    }
  }

  /// 平滑过渡到目标宽度
  void animateToWidth(double targetWidth) {
    _targetWidth = targetWidth.clamp(_minWidth, _maxWidth);
    notifyListeners();
  }

  /// 更新当前宽度（由动画驱动）
  void updateAnimatedWidth(double width) {
    _width = width;
    notifyListeners();
  }
}
