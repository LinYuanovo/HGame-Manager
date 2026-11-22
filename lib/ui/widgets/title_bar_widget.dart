import 'dart:ui';
import 'package:flutter/material.dart';
import '../controllers/window_controller.dart';
import '../theme/app_theme.dart';
import 'window_caption_button.dart';

/// 标题栏独立组件，负责标题栏的UI渲染和窗口操作交互
class TitleBarWidget extends StatelessWidget {
  final WindowController windowController;

  const TitleBarWidget({
    super.key,
    required this.windowController,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onPanStart: (_) => windowController.startDragging(),
        onDoubleTap: () => windowController.toggleMaximize(),
        child: _buildBlurredChild(context),
      ),
    );
  }

  Widget _buildBlurredChild(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final container = Container(
      height: LayoutConstants.titleBarHeight,
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.getSurfaceColor(context).withValues(alpha: 0.8)
            : AppTheme.getSurfaceColor(context).withValues(alpha: 0.7),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppTheme.getBorderColor(context).withValues(alpha: 0.3)
                : AppTheme.getSurfaceColor(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: GlassConstants.spacingMedium),
          Image.asset(
            isDark ? 'app_icon_dark.png' : 'app_icon.png',
            width: 28,
            height: 28,
          ),
          const SizedBox(width: GlassConstants.spacingCompact),
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.getPrimaryGradient(context).createShader(bounds),
            child: const Text(
              'HGame Manager',
              style: TextStyle(
                color: AppTheme.lightForegroundColor,
                fontSize: GlassConstants.fontControl,
                fontWeight: AppTypography.semibold,
              ),
            ),
          ),
          const Spacer(),
          _buildWindowButtons(),
        ],
      ),
    );
    if (isDark) return container;
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: GlassConstants.blurMedium,
        sigmaY: GlassConstants.blurMedium,
      ),
      child: container,
    );
  }

  Widget _buildWindowButtons() {
    return ListenableBuilder(
      listenable: windowController,
      builder: (context, _) {
        return Row(
          children: [
            WindowCaptionButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onPressed: () => windowController.minimize(),
            ),
            WindowCaptionButton(
              icon: windowController.isMaximized
                  ? Icons.filter_none
                  : Icons.crop_square,
              iconSize: GlassConstants.iconBadge,
              tooltip: windowController.isMaximized ? '还原' : '最大化',
              onPressed: () => windowController.toggleMaximize(),
            ),
            WindowCaptionButton(
              icon: Icons.close,
              tooltip: '关闭',
              onPressed: () => windowController.close(),
              isClose: true,
            ),
          ],
        );
      },
    );
  }
}
