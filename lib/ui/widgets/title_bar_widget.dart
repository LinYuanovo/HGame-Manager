import 'dart:ui';
import 'package:flutter/material.dart';
import '../controllers/window_controller.dart';
import '../theme/app_theme.dart';

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
                fontWeight: FontWeight.w600,
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
            _WindowButton(
              icon: Icons.remove,
              onPressed: () => windowController.minimize(),
            ),
            _WindowButton(
              icon: windowController.isMaximized
                  ? Icons.filter_none
                  : Icons.crop_square,
              iconSize: GlassConstants.iconBadge,
              onPressed: () => windowController.toggleMaximize(),
            ),
            _WindowButton(
              icon: Icons.close,
              onPressed: () => windowController.close(),
              isClose: true,
            ),
          ],
        );
      },
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  final double? iconSize;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
    this.iconSize,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, GlassConstants.animFast),
          width: 46,
          height: 40,
          color: _isHovered
              ? (widget.isClose
                  ? AppTheme.accentColor.withValues(alpha: 0.8)
                  : AppTheme.getSurfaceColor(context).withValues(alpha: isDark ? 0.1 : 0.15))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize ?? GlassConstants.iconSmall,
            color: _isHovered && widget.isClose
                ? AppTheme.lightForegroundColor
                : AppTheme.getTextSecondary(context),
          ),
        ),
      ),
    );
  }
}
