import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../core/models/models.dart';

// ===== 统一常量 =====
class LayoutConstants {
  // Card dimensions
  static const double posterWidth = 180;
  static const double listThumbnailWidth = 200;
  static const double listThumbnailHeight = 300;
  static const double actorCardWidth = 140;

  // Detail page
  static const double detailAvatarSize = 180;
  static const double detailInfoPanelWidth = 320;
  static const double smallPosterWidth = 140;
  static const double smallPosterHeight = 200;

  // Window
  static const double defaultWindowWidth = 1400;
  static const double defaultWindowHeight = 900;
  static const double titleBarHeight = 40;
  static const double sidebarWidth = 220;
  static const double minSidebarWidth = 70;
  static const double maxSidebarWidth = 280;
}

class GlassConstants {
  // 圆角
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 24.0;

  // 模糊
  static const double blurSmall = 10.0;
  static const double blurMedium = 18.0;
  static const double blurLarge = 30.0;

  // 动画时长
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 400);

  // 动画曲线
  static const Curve animCurve = Curves.easeInOut;

  // 间距
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  // 缩放
  static const double hoverScale = 1.02;
  static const double pressScale = 0.97;

  // 对话框
  static const double dialogWidth = 600.0;
}

class AppTheme {
  // 主色调 - 蓝紫渐变色系
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color primaryLightColor = Color(0xFF3B82F6);
  static const Color secondaryColor = Color(0xFF7C3AED);
  static const Color accentColor = Color(0xFFFF6B6B);

  // 背景色 - 带有微妙渐变的浅色
  static const Color backgroundColor = Color(0xFFF0F4F8);
  static const Color backgroundGradientStart = Color(0xFFE8EEF4);
  static const Color backgroundGradientEnd = Color(0xFFF5F0FF);

  // 表面/卡片色 - 半透明
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color glassFillColor = Color(0xCCFFFFFF); // 80%白
  static const Color glassBorderWhite = Color(0x33FFFFFF); // 20%白边框
  static const Color glassBorderBlue = Color(0x1A2563EB); // 10%蓝边框

  // 文字
  static const Color textPrimary = Color(0xFF374244);
  static const Color textSecondary = Color(0xFF6B7280);

  // 状态色
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);

  // 边框
  static const Color borderColor = Color(0xFFE5E7EB);

  // 渐变
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, secondaryColor],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [backgroundGradientStart, backgroundGradientEnd],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLightColor, secondaryColor],
  );

  static ImageErrorWidgetBuilder imageErrorBuilder = (context, error, stackTrace) {
    return Container(
      color: const Color(0xFFE8E8E8),
      child: const Center(
        child: Icon(Icons.broken_image, color: Color(0xFFBDBDBD), size: 32),
      ),
    );
  };

  static ThemeData lightTheme({String? fontFamily}) {
    final effectiveFontFamily = fontFamily ?? 'Microsoft YaHei';
    return ThemeData(
      fontFamily: effectiveFontFamily,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ).copyWith(
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: surfaceColor,
        error: errorColor,
      ),
      cardTheme: CardThemeData(
        color: cardColor.withValues(alpha:0.6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        shadowColor: Colors.black.withValues(alpha:0.05),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: textSecondary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 34,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        titleSmall: TextStyle(
          color: textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 15,
        ),
        bodySmall: TextStyle(
          color: textSecondary,
          fontSize: 13,
        ),
      ).apply(fontFamily: effectiveFontFamily),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          ),
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary.withValues(alpha: 0.7),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor.withValues(alpha: 0.7),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor.withValues(alpha: 0.7),
          side: BorderSide(color: primaryColor.withValues(alpha: 0.7)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor.withValues(alpha: 0.7),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha:0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: borderColor.withValues(alpha:0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: borderColor.withValues(alpha:0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.grey.withValues(alpha:0.3)),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        color: Colors.white.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
        elevation: 12,
        textStyle: const TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  static void showGlassSnackBar(BuildContext context, String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(
              color: (color ?? AppTheme.primaryColor).withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: (color ?? AppTheme.primaryColor).withValues(alpha: 0.12),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                color == AppTheme.errorColor
                    ? Icons.error_outline
                    : color == AppTheme.successColor
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                color: color ?? AppTheme.primaryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: color ?? AppTheme.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.1,
          left: MediaQuery.of(context).size.width * 0.3,
          right: MediaQuery.of(context).size.width * 0.3,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static Future<T?> showGlassMenu<T>({
    required BuildContext context,
    required RelativeRect position,
    required List<PopupMenuEntry<T>> items,
    T? initialValue,
  }) {
    return showMenu<T>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      color: Colors.white.withValues(alpha: 0.95),
      elevation: 12,
      shadowColor: Colors.black26,
      items: items,
      initialValue: initialValue,
    );
  }

  static void showGlassToast(
    BuildContext context, {
    required String message,
    IconData icon = Icons.check_circle,
    Color iconColor = const Color(0xFF10B981),
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 40,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: iconColor),
                        const SizedBox(width: 8),
                        Text(message, style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(duration, () {
      overlayEntry.remove();
    });
  }
}

// ===== 玻璃拟态容器 =====
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? color;
  final double? width;
  final double? height;
  final bool enableBlur;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final Gradient? gradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = GlassConstants.radiusMedium,
    this.blur = GlassConstants.blurMedium,
    this.color,
    this.width,
    this.height,
    this.enableBlur = true,
    this.border,
    this.boxShadow,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: enableBlur ? blur : 0,
            sigmaY: enableBlur ? blur : 0,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? AppTheme.glassFillColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: border ??
                  Border.all(
                    color: AppTheme.glassBorderWhite,
                    width: 1,
                  ),
              boxShadow: boxShadow ??
                  [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.06),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha:0.03),
                      blurRadius: 40,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                  ],
              gradient: gradient,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ===== 玻璃卡片 =====
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final bool enableHoverEffect;
  final bool enableBorderBreathing;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = GlassConstants.radiusLarge,
    this.color,
    this.enableHoverEffect = true,
    this.enableBorderBreathing = false,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  AnimationController? _borderController;
  Animation<double>? _borderAnimation;

  @override
  void initState() {
    super.initState();
    _setupBorderAnimation();
  }

  @override
  void didUpdateWidget(GlassCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableBorderBreathing != widget.enableBorderBreathing) {
      _setupBorderAnimation();
    }
  }

  void _setupBorderAnimation() {
    if (widget.enableBorderBreathing) {
      _borderController?.dispose();
      _borderController = AnimationController(
        duration: const Duration(seconds: 3),
        vsync: this,
      )..repeat(reverse: true);
      _borderAnimation = Tween<double>(begin: 0.15, end: 0.35).animate(
        CurvedAnimation(parent: _borderController!, curve: Curves.easeInOut),
      );
    } else {
      _borderController?.stop();
      _borderAnimation = null;
    }
  }

  @override
  void dispose() {
    _borderController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enableHoverEffect ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enableHoverEffect ? (_) => setState(() { _isHovered = false; _isPressed = false; }) : null,
      child: GestureDetector(
        onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: widget.onTap != null ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed
              ? GlassConstants.pressScale
              : (_isHovered ? GlassConstants.hoverScale : 1.0),
          duration: GlassConstants.animFast,
          curve: GlassConstants.animCurve,
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            curve: GlassConstants.animCurve,
            margin: widget.margin,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlassConstants.blurMedium,
                  sigmaY: GlassConstants.blurMedium,
                ),
                child: AnimatedBuilder(
                  animation: _borderController ?? const AlwaysStoppedAnimation(0),
                  builder: (context, child) {
                    final borderOpacity = _borderAnimation?.value ?? 0.35;
                    return AnimatedContainer(
                      duration: GlassConstants.animFast,
                      curve: GlassConstants.animCurve,
                      padding: widget.padding,
                      decoration: BoxDecoration(
                        color: widget.color ??
                            (_isHovered
                                ? Colors.white.withValues(alpha: 0.88)
                                : Colors.white.withValues(alpha: 0.65)),
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        border: Border.all(
                          color: _isHovered
                              ? AppTheme.primaryColor.withValues(alpha: 0.25)
                              : widget.enableBorderBreathing
                                  ? AppTheme.primaryColor.withValues(alpha: borderOpacity)
                                  : Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isHovered
                                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.05),
                            blurRadius: _isHovered ? 28 : 16,
                            spreadRadius: _isHovered ? 2 : 1,
                            offset: Offset(0, _isHovered ? 6 : 4),
                          ),
                          BoxShadow(
                            color: (_isHovered
                                ? AppTheme.secondaryColor
                                : AppTheme.primaryColor).withValues(alpha: _isHovered ? 0.06 : 0.03),
                            blurRadius: _isHovered ? 50 : 40,
                            spreadRadius: 0,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== 边框呼吸动画 =====
class BreathingBorder extends StatefulWidget {
  final Widget child;
  final bool isBreathing;
  final Color color;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const BreathingBorder({
    super.key,
    required this.child,
    this.isBreathing = false,
    this.color = AppTheme.primaryColor,
    this.duration = const Duration(seconds: 3),
    this.minOpacity = 0.15,
    this.maxOpacity = 0.35,
    this.borderRadius = GlassConstants.radiusLarge,
    this.padding,
  });

  @override
  State<BreathingBorder> createState() => _BreathingBorderState();
}

class _BreathingBorderState extends State<BreathingBorder>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(BreathingBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isBreathing != widget.isBreathing ||
        oldWidget.duration != widget.duration ||
        oldWidget.minOpacity != widget.minOpacity ||
        oldWidget.maxOpacity != widget.maxOpacity) {
      _setupAnimation();
    }
  }

  void _setupAnimation() {
    if (widget.isBreathing) {
      _controller?.dispose();
      _controller = AnimationController(
        duration: widget.duration,
        vsync: this,
      )..repeat(reverse: true);
      _animation = Tween<double>(
        begin: widget.minOpacity,
        end: widget.maxOpacity,
      ).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeInOut),
      );
    } else {
      _controller?.stop();
      _animation = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller ?? const AlwaysStoppedAnimation(0),
      builder: (context, child) {
        final opacity = _animation?.value ?? widget.minOpacity;
        return Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.color.withValues(alpha: opacity),
              width: 1,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ===== 玻璃按钮 =====
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;
  final Gradient? gradient;
  final bool isEnabled;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.borderRadius = GlassConstants.radiusMedium,
    this.color,
    this.gradient,
    this.isEnabled = true,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.isEnabled ? (_) => setState(() { _isHovered = false; _isPressed = false; }) : null,
      child: GestureDetector(
        onTapDown: widget.isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: widget.isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: widget.isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: GlassConstants.animFast,
          curve: GlassConstants.animCurve,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.gradient == null
                ? (widget.color ?? Colors.white.withValues(alpha:_isPressed ? 0.5 : _isHovered ? 0.6 : 0.4))
                : null,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.gradient == null
                  ? Colors.white.withValues(alpha:_isHovered ? 0.4 : 0.2)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isHovered ? AppTheme.primaryColor : Colors.black).withValues(alpha:0.1),
                blurRadius: _isHovered ? 15 : 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ===== 渐变背景层 =====
class GradientBackground extends StatefulWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.03, end: 0.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE0E8F0),
            Color(0xFFE8E4F2),
            Color(0xFFF0ECFA),
            Color(0xFFE8EFF8),
            Color(0xFFF2F0FF),
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF2563EB).withValues(alpha: _glowAnimation.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Positioned(
                bottom: -150,
                left: -100,
                child: Container(
                  width: 600,
                  height: 600,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF7C3AED).withValues(alpha: _glowAnimation.value * 0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}

// ===== 毛玻璃AppBar =====
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassConstants.blurLarge,
          sigmaY: GlassConstants.blurLarge,
        ),
        child: Container(
          height: preferredSize.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.7),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha:0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              if (leading != null) leading!,
              title,
              const Spacer(),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 搜索栏 =====
class GlassSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final EdgeInsetsGeometry? margin;

  const GlassSearchBar({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin ?? EdgeInsets.zero,
      borderRadius: 24,
      blur: GlassConstants.blurSmall,
      color: Colors.white.withValues(alpha:0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      border: Border.all(
        color: Colors.white.withValues(alpha:0.4),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha:0.03),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hintText ?? '搜索...',
            hintStyle: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha:0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search,
              color: AppTheme.textSecondary.withValues(alpha:0.6),
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }
}

// ===== 标签芯片 =====
class GlassChip extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final bool isSelected;

  const GlassChip({
    super.key,
    required this.label,
    this.color,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: GlassConstants.animFast,
        curve: GlassConstants.animCurve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha:0.2)
              : Colors.white.withValues(alpha:0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor.withValues(alpha:0.5)
                : Colors.white.withValues(alpha:0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: chipColor.withValues(alpha:0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ===== 交错动画列表项 =====
class StaggeredItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;

  const StaggeredItem({
    super.key,
    required this.child,
    required this.index,
    this.baseDelay = const Duration(milliseconds: 50),
  });

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();  // Start IMMEDIATELY, no delay
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: _slideAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ===== 玻璃拟态复制提示弹窗 =====
void showCopyToast(BuildContext context, String text) {
  final overlay = Overlay.of(context);
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: 60,
      left: MediaQuery.of(context).size.width * 0.3,
      right: MediaQuery.of(context).size.width * 0.3,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlassConstants.blurSmall,
                  sigmaY: GlassConstants.blurSmall,
                ),
                child: _CopyToastContent(
                  text: text,
                  onRemove: () => overlayEntry.remove(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(overlayEntry);
}

class _CopyToastContent extends StatefulWidget {
  final String text;
  final VoidCallback onRemove;

  const _CopyToastContent({required this.text, required this.onRemove});

  @override
  State<_CopyToastContent> createState() => _CopyToastContentState();
}

class _CopyToastContentState extends State<_CopyToastContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    // Display for 1.5 seconds, then fade out
    Future.delayed(const Duration(seconds: 1, milliseconds: 500), () {
      if (mounted) {
        _controller.forward().then((_) {
          widget.onRemove();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(
            GlassConstants.radiusMedium,
          ),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 30,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.primaryColor,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 视图模式图标辅助函数 =====
IconData getViewModeIcon(ViewMode mode) => switch (mode) {
  ViewMode.list   => Icons.view_list,
  ViewMode.poster => Icons.grid_view,
};

// ===== 玻璃拟态 TabBar =====
class GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<Widget> tabs;

  const GlassTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassConstants.blurSmall,
          sigmaY: GlassConstants.blurSmall,
        ),
        child: Container(
          height: preferredSize.height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: TabBar(
            controller: controller,
            tabs: tabs,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            ),
            indicatorPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            dividerColor: Colors.transparent,
            splashBorderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
          ),
        ),
      ),
    );
  }
}

// ===== 玻璃拟态对话框 =====
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape): const _DismissDialogIntent(),
        },
        child: Actions(
          actions: {
            _DismissDialogIntent: CallbackAction<_DismissDialogIntent>(
              onInvoke: (_) {
                Navigator.of(context).pop();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlassConstants.blurLarge,
                  sigmaY: GlassConstants.blurLarge,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.05),
                        blurRadius: 50,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DismissDialogIntent extends Intent {
  const _DismissDialogIntent();
}

// ===== 空状态占位组件 =====
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subMessage;
  final Widget? action;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.message,
    this.subMessage,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              subMessage!,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}
