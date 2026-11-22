import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SkeletonLayout { posters, rows, tags, tools, image }

class AppLoadError extends StatelessWidget {
  const AppLoadError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GlassConstants.spacingMedium),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: GlassConstants.spacingSmall),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试')),
          ]),
        ),
      );
}

Widget appImageFrameBuilder(BuildContext context, Widget child, int? frame,
    bool wasSynchronouslyLoaded) {
  if (wasSynchronouslyLoaded) return child;
  if (frame != null) {
    return AppMotionValue(
        begin: 0,
        target: 1,
        duration: AppMotion.fast,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: child);
  }
  return LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: constraints.hasBoundedWidth ? constraints.maxWidth : 160,
      child: AppSkeleton(
        layout: SkeletonLayout.image,
        height: constraints.hasBoundedHeight ? constraints.maxHeight : 160,
        label: '正在加载图片',
      ),
    ),
  );
}

class AppSkeleton extends StatefulWidget {
  final SkeletonLayout layout;
  final String label;
  final int columns;
  final double coverAspectRatio;
  final double? height;
  final bool showToolbar;

  const AppSkeleton({
    super.key,
    this.layout = SkeletonLayout.rows,
    this.label = '正在加载',
    this.columns = 3,
    this.coverAspectRatio = 16 / 9,
    this.height,
    this.showToolbar = false,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.shimmer);
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _updateAnimation();
  }

  void _updateAnimation() {
    if (_active &&
        !AppMotion.reduced(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: widget.height,
      child: Semantics(
        label: widget.label,
        liveRegion: true,
        child: IgnorePointer(
          child: ClipRect(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(640, widget.height ?? 320),
                painter: _SkeletonPainter(
                  animation: _controller,
                  layout: widget.layout,
                  columns: widget.columns,
                  coverAspectRatio: widget.coverAspectRatio,
                  showToolbar: widget.showToolbar,
                  base: AppMotion.reduced(context)
                      ? AppTheme.getPrimaryColor(context)
                          .withValues(alpha: 0.12)
                      : AppTheme.getBorderColor(context).withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.42
                              : 0.24),
                  highlight: AppTheme.getPrimaryColor(context).withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.24
                          : 0.16),
                  reduced: AppMotion.reduced(context),
                ),
              ),
            ),
          ),
        ),
      ));
}

class _SkeletonPainter extends CustomPainter {
  final Animation<double> animation;
  final SkeletonLayout layout;
  final int columns;
  final double coverAspectRatio;
  final bool showToolbar;
  final Color base;
  final Color highlight;
  final bool reduced;

  _SkeletonPainter({
    required this.animation,
    required this.layout,
    required this.columns,
    required this.coverAspectRatio,
    required this.showToolbar,
    required this.base,
    required this.highlight,
    required this.reduced,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..color = base;
    if (!reduced) {
      final center = (animation.value * 2 - 0.5) * size.width;
      paint.color = base.withValues(alpha: 1);
      paint.shader = LinearGradient(
        colors: [base, highlight, base],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(
          center - size.width / 2, 0, size.width, math.max(size.height, 1)));
    }
    void block(double left, double top, double width, double height,
        [double radius = GlassConstants.radiusCompact]) {
      if (width <= 0 || height <= 0) return;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(left, top, width, height), Radius.circular(radius)),
          paint);
    }

    if (layout == SkeletonLayout.image) {
      block(0, 0, size.width, size.height);
      return;
    }
    const padding = GlassConstants.spacingMedium;
    final gap = layout == SkeletonLayout.tags
        ? GlassConstants.spacingSmall
        : GlassConstants.spacingMedium;
    final available = math.max(0.0, size.width - padding * 2);
    var contentTop = padding;
    if (showToolbar) {
      block(
          padding, padding, available * 0.55, 40, GlassConstants.radiusXLarge);
      for (var index = 0; index < 4; index++) {
        block(padding + available * (0.62 + index * 0.1), padding + 4,
            available * 0.07, 32);
      }
      contentTop += 66;
    }
    if (layout == SkeletonLayout.rows) {
      for (var row = 0; row < 8 && contentTop + row * 88 < size.height; row++) {
        final top = contentTop + row * 88;
        final thumbnail = math.min(100.0, available * 0.25);
        final textWidth = math.max(0.0, available - thumbnail - gap);
        block(padding, top, thumbnail, 64);
        block(padding + thumbnail + gap, top + 6, textWidth * 0.68, 14);
        block(padding + thumbnail + gap, top + 31, textWidth * 0.9, 10);
        block(padding + thumbnail + gap, top + 51, textWidth * 0.45, 8);
      }
      return;
    }
    final count = switch (layout) {
      SkeletonLayout.tags => 6,
      SkeletonLayout.tools => math.max(1, (available / 160).ceil()),
      _ => columns.clamp(1, 8),
    };
    final width = math.max(1.0, (available - (count - 1) * gap) / count);
    final imageHeight = switch (layout) {
      SkeletonLayout.tags => width / 2.5,
      SkeletonLayout.tools => width * 0.85,
      _ => width / coverAspectRatio,
    };
    final tileHeight = imageHeight + (layout == SkeletonLayout.tags ? 0 : 62);
    for (var index = 0; index < 36; index++) {
      final top = contentTop + (index ~/ count) * (tileHeight + gap);
      if (top >= size.height) break;
      final left = padding + (index % count) * (width + gap);
      block(left, top, width, imageHeight, GlassConstants.radiusSmall);
      if (layout != SkeletonLayout.tags) {
        block(left + 6, top + imageHeight + 14, width * 0.8, 12);
        block(left + 6, top + imageHeight + 36, width * 0.5, 8);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter oldDelegate) =>
      layout != oldDelegate.layout ||
      columns != oldDelegate.columns ||
      coverAspectRatio != oldDelegate.coverAspectRatio ||
      showToolbar != oldDelegate.showToolbar ||
      base != oldDelegate.base ||
      highlight != oldDelegate.highlight ||
      reduced != oldDelegate.reduced;
}

class AppProgressIndicator extends StatelessWidget {
  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  final double strokeWidth;

  const AppProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.valueColor,
    this.strokeWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null && AppMotion.reduced(context)) {
      return Semantics(
        label: '正在处理',
        child: Icon(Icons.hourglass_top_rounded,
            size: GlassConstants.iconMedium, color: color ?? valueColor?.value),
      );
    }
    return CircularProgressIndicator(
      value: value,
      color: color,
      backgroundColor: backgroundColor,
      valueColor: valueColor,
      strokeWidth: strokeWidth,
      semanticsLabel: '正在处理',
    );
  }
}

class AppLinearProgress extends StatelessWidget {
  final double? value;
  final double? minHeight;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  final BorderRadiusGeometry? borderRadius;

  const AppLinearProgress({
    super.key,
    this.value,
    this.minHeight,
    this.backgroundColor,
    this.valueColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null && AppMotion.reduced(context)) {
      return Semantics(
        label: '正在处理',
        child: Container(
          height: minHeight ?? 4,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppTheme.getBorderColor(context),
            borderRadius: borderRadius,
          ),
        ),
      );
    }
    final target = value;
    Widget indicator(double? painted) => LinearProgressIndicator(
          value: painted,
          semanticsValue: target == null ? null : '${(target * 100).round()}',
          minHeight: minHeight,
          backgroundColor: backgroundColor,
          valueColor: valueColor,
          borderRadius: borderRadius,
          semanticsLabel: '正在处理',
        );
    if (target == null) return indicator(null);
    return AppMotionValue(
        target: target.clamp(0.0, 1.0),
        duration: AppMotion.fast,
        builder: (context, painted, child) => indicator(painted));
  }
}
