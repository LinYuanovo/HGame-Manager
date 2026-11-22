import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../core/models/models.dart';
import 'app_motion.dart';
export 'app_motion.dart';
export '../widgets/app_loading.dart';

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
  static const double reviewDialogWidth = 1120;
  static const double reviewDialogHeight = 820;
  static const double reviewSplitWidth = 880;
  static const double reviewImageHeight = 160;
  static const double scraperControlPanelWidth = 300;
  static const double scraperControlWidth = 240;
  // 表单控件与批量导入布局
  static const double controlHeight = 44;
  static const double formCompactWidth = 640;
  static const double gameListToolbarCompactWidth = 1000;
  static const double batchImportDialogWidth = 860;
  static const double batchImportDialogHeight = 600;
  static const double batchImportSourceWidth = 104;
  static const double batchImportNameWidth = 220;
  static const double batchImportCompactWidth = 640;
  static const double smallPosterWidth = 140;
  static const double smallPosterHeight = 200;

  // Window
  static const double defaultWindowWidth = 1400;
  static const double defaultWindowHeight = 900;
  static const double titleBarHeight = 40;
  static const double panelControlWidth = 200;
  static const double panelControlHeight = 52;
  static const double sidebarWidth = 220;
  static const double minSidebarWidth = 70;
  static const double maxSidebarWidth = 280;
}

class GlassConstants {
  static const double lineHeightCompact = 1.4;
  static const double iconTiny = 12.0;
  static const double iconBadge = 13.0;
  static const double iconCompact = 14.0;
  static const double iconInline = 15.0;
  static const double iconSmall = 16.0;
  static const double iconAction = 18.0;
  static const double iconControl = 20.0;
  static const double iconSection = 22.0;
  static const double iconMedium = 24.0;
  static const double iconHeading = 28.0;
  static const double iconLarge = 32.0;
  static const double iconAbout = 34.0;
  static const double iconFeature = 36.0;
  static const double iconHero = 40.0;
  static const double iconPlaceholder = 48.0;
  static const double iconEmptyState = 64.0;
  static const double iconErrorState = 72.0;
  static const double iconBrand = 80.0;
  static const double spacingHairline = 1.0;
  static const double spacingMicro = 2.0;
  static const double spacingFine = 3.0;
  static const double spacingTrim = 5.0;
  static const double spacingInline = 10.0;
  static const double spacingControl = 14.0;
  static const double spacingSection = 18.0;
  static const double spacingSpacious = 22.0;
  static const double spacingDialog = 28.0;
  static const double spacingLoose = 30.0;
  static const double spacingPage = 40.0;
  static const double radiusInset = 7.0;
  static const double radiusFloating = 18.0;
  static const double fontBadge = 10.0;
  static const double fontMicro = 9.0;
  static const double fontLog = 11.5;
  static const double fontSubtitle = 17.0;
  static const double fontMarkdownTitle = 19.0;
  static const double fontHeadline = 22.0;
  static const double fontDetailTitle = 26.0;
  static const double fontHero = 34.0;
  static const double radiusIndicator = 3.0;
  static const double radiusTiny = 4.0;
  static const double radiusTight = 6.0;
  static const double radiusCompact = 8.0;
  static const double radiusControl = 10.0;
  static const double spacingTiny = 4.0;
  static const double spacingTight = 6.0;
  static const double spacingCompact = 12.0;
  static const double spacingComfortable = 20.0;
  static const double fontCaption = 11.0;
  static const double fontSmall = 12.0;
  static const double fontBody = 13.0;
  static const double fontControl = 14.0;
  static const double fontBodyLarge = 15.0;
  static const double fontTitle = 16.0;
  static const double fontSection = 18.0;
  static const double fontHeading = 20.0;
  static const double fontDisplay = 24.0;
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
  static const Duration animFast = AppMotion.fast;
  static const Duration animMedium = AppMotion.medium;
  static const Duration animSlow = AppMotion.slow;

  // 动画曲线
  static const Curve animCurve = AppMotion.curve;

  // 间距
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  // 对话框
  static const double dialogWidth = 600.0;
}

abstract final class AppTypography {
  static const family = 'Microsoft YaHei';
  static const bundledFamily = 'MapleMonoNL-NF-CN';
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const labelHeight = 1.3;
  static const compactHeight = 1.4;
  static const bodyHeight = 1.5;
  static const readingHeight = 1.7;
  static const spaciousHeight = 1.8;
  static const buttonLabel = TextStyle(
    fontSize: GlassConstants.fontControl,
    fontWeight: medium,
  );
  static const bundledPreview = TextStyle(fontFamily: bundledFamily);

  static TextStyle dialogTitle(BuildContext context) => TextStyle(
        fontSize: GlassConstants.fontSection,
        fontWeight: bold,
        color: AppTheme.getTextPrimary(context),
      );

  static TextStyle preview(String family, double size, Color color) => TextStyle(
        fontFamily: family.isEmpty ? AppTypography.family : family,
        fontSize: size,
        color: color,
      );
}

abstract final class AppButtonStyles {
  static const _compactPadding = EdgeInsets.symmetric(
    horizontal: GlassConstants.spacingCompact,
    vertical: GlassConstants.spacingTiny,
  );

  static ButtonStyle solid({required Color color, bool compact = false}) =>
      ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color.computeLuminance() > 0.179 ? Colors.black : Colors.white,
        padding: compact ? _compactPadding : null,
      );

  static ButtonStyle tinted(BuildContext context, {Color? color, bool compact = false}) {
    final accent = color ?? AppTheme.getPrimaryColor(context);
    final ink = Theme.of(context).brightness == Brightness.light
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.35), accent)
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.30), accent);
    return ElevatedButton.styleFrom(
      foregroundColor: ink,
      backgroundColor: accent.withValues(alpha: 0.12),
      padding: compact ? _compactPadding : null,
      side: BorderSide(color: accent.withValues(alpha: 0.3)),
    );
  }

  static ButtonStyle outline({Color? color, bool compact = false}) =>
      OutlinedButton.styleFrom(
        foregroundColor: color,
        side: color == null ? null : BorderSide(color: color),
        padding: compact ? _compactPadding : null,
        minimumSize: compact ? Size.zero : null,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      );

  static ButtonStyle get compact => ElevatedButton.styleFrom(padding: _compactPadding);

  static ButtonStyle muted(BuildContext context) =>
      TextButton.styleFrom(foregroundColor: AppTheme.getTextSecondary(context));

  static ButtonStyle iconTint(BuildContext context) => IconButton.styleFrom(
        foregroundColor: AppTheme.getPrimaryColor(context),
        backgroundColor: AppTheme.getPrimaryColor(context).withValues(alpha: 0.12),
      );

  static ButtonStyle caption(BuildContext context, {required bool close, required bool active}) {
    bool highlighted(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) || states.contains(WidgetState.focused);
    return ButtonStyle(
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          close && highlighted(states) ? AppTheme.errorColor : null),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          close && highlighted(states) ? Colors.black : active
              ? AppTheme.getPrimaryColor(context) : AppTheme.getTextSecondary(context)),
    );
  }
}

class AppMiniIconButton extends StatelessWidget {
  const AppMiniIconButton({super.key, required this.icon, required this.tooltip, required this.color, required this.onTap});

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    color: color,
    iconSize: GlassConstants.iconSmall,
    constraints: const BoxConstraints.tightFor(width: GlassConstants.iconLarge, height: GlassConstants.iconLarge),
    padding: const EdgeInsets.all(GlassConstants.spacingTiny),
    icon: Icon(icon),
  );
}

class AppTheme {
  static const Color lightForegroundColor = Colors.white;
  // 暗黑模式颜色
  static const Color darkBackgroundColor = Color(0xFF1A1A2E);
  static const Color darkBackgroundGradientStart = Color(0xFF16213E);
  static const Color darkBackgroundGradientEnd = Color(0xFF1F1F3A);

  static const Color darkSurfaceColor = Color(0xFF2D2D44);
  static const Color darkSurfaceDeepColor = Color(0xFF1B2838); // 详情页背景色
  static const Color darkCardColor = Color(0xFF2D2D44);
  static const Color darkGlassFillColor = Color(0xCC2D2D44);
  static const Color darkGlassBorderWhite = Color(0x33555577);
  static const Color darkGlassBorderBlue = Color(0x1A2563EB);

  static const Color darkTextPrimary = Color(0xFFE0E0E0);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkDetailTextPrimary = Color(0xFFACB2B8); // 详情页文本色
  static const Color darkCardTitleColor = Color(0xFFC5CCD2); // 卡片/侧边栏标题色

  static const Color darkBorderColor = Color(0xFF4A4A6A);

  // 暗黑模式下增强的主色（提高对比度）
  static const Color darkPrimaryColor = Color(0xFF7DD3FC);

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

  // 收藏红
  static const Color favoriteColor = Color(0xFFFF6B9D);
  static const Color darkFavoriteColor = Color(0xFFFF6B9D);

  // 星级金
  static const Color starColor = Color(0xFFFFD700);
  static const Color darkStarColor = Color(0xFFFFD700);

  // 警告橙
  static const Color warningOrange = Color(0xFFFFA000);

  // 工具颜色
  static const Color toolGreen = Color(0xFF4CAF50);
  static const Color toolBlue = Color(0xFF2196F3);
  static const Color toolPurple = Color(0xFF9C27B0);
  static const Color toolGrey = Color(0xFF607D8B);
  static const Color toolRed = Color(0xFFF44336);
  static const Color toolDarkBlue = Color(0xFF1976D2);
  static const Color toolDarkGreen = Color(0xFF388E3C);
  static const Color toolOrange = Color(0xFFFF9800);
  static const Color toolCyan = Color(0xFF00BCD4);
  static const Color toolPink = Color(0xFFE91E63);

  // 深色模式渐变颜色
  static const List<Color> darkGradientColors = [
    Color(0xFF0D1117),
    Color(0xFF161B22),
    Color(0xFF1F2937),
    Color(0xFF161B22),
    Color(0xFF0D1117),
  ];

  // 浅色模式渐变颜色
  static const List<Color> lightGradientColors = [
    Color(0xFFE0E8F0),
    Color(0xFFE8E4F2),
    Color(0xFFF0ECFA),
    Color(0xFFE8EFF8),
    Color(0xFFF2F0FF),
  ];

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

  static const LinearGradient darkBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkBackgroundGradientStart, darkBackgroundGradientEnd],
  );

  static ImageErrorWidgetBuilder imageErrorBuilder =
      (context, error, stackTrace) {
    return Container(
      color: getInputFillColor(context),
      child: Center(
        child: Icon(Icons.broken_image, color: getTextSecondary(context), size: GlassConstants.iconLarge),
      ),
    );
  };

  static ThemeData lightTheme({String? fontFamily}) {
    final effectiveFontFamily = fontFamily ?? AppTypography.family;
    return ThemeData(
      fontFamily: effectiveFontFamily,
      brightness: Brightness.light,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.windows: AppPageTransitionsBuilder(),
      }),
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
        color: cardColor.withValues(alpha: 0.6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.05),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: effectiveFontFamily,
          color: textPrimary,
          fontSize: GlassConstants.fontHeading,
          fontWeight: AppTypography.semibold,
        ),
        iconTheme: IconThemeData(
          color: textSecondary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: GlassConstants.iconMedium,
      ),
      textTheme: TextTheme(
        labelLarge: AppTypography.buttonLabel,
        labelMedium: const TextStyle(fontSize: GlassConstants.fontSmall, fontWeight: FontWeight.w500),
        labelSmall: const TextStyle(fontSize: GlassConstants.fontCaption, fontWeight: FontWeight.w500),
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: GlassConstants.fontHero,
          fontWeight: AppTypography.bold,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: GlassConstants.fontDetailTitle,
          fontWeight: AppTypography.semibold,
        ),
        headlineSmall: TextStyle(
          color: textPrimary,
          fontSize: GlassConstants.fontHeadline,
          fontWeight: AppTypography.semibold,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: GlassConstants.fontHeading,
          fontWeight: AppTypography.medium,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: GlassConstants.fontSection,
          fontWeight: AppTypography.medium,
        ),
        titleSmall: TextStyle(
          color: textSecondary,
          fontSize: GlassConstants.fontTitle,
          fontWeight: AppTypography.regular,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: GlassConstants.fontSection,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: GlassConstants.fontBodyLarge,
        ),
        bodySmall: TextStyle(
          color: textSecondary,
          fontSize: GlassConstants.fontBody,
        ),
      ).apply(fontFamily: effectiveFontFamily),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          foregroundBuilder: AppMotion.buttonFace,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundBuilder: AppMotion.buttonFace,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingLarge, vertical: GlassConstants.spacingCompact),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          ),
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary.withValues(alpha: 0.7),
        ).copyWith(foregroundBuilder: AppMotion.buttonFace),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : surfaceColor,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor.withValues(alpha: 0.55)
              : borderColor.withValues(alpha: 0.55),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor.withValues(alpha: 0.8)
              : borderColor.withValues(alpha: 0.8),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundBuilder: AppMotion.buttonFace,
          foregroundColor: primaryColor,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundBuilder: AppMotion.buttonFace,
          foregroundColor: primaryColor,
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
        fillColor: Colors.white.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: borderColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: borderColor.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: GlassConstants.spacingMedium, vertical: GlassConstants.spacingControl),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.grey.withValues(alpha: 0.3)),
        radius: const Radius.circular(GlassConstants.radiusTiny),
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
        textStyle: TextStyle(
          fontFamily: effectiveFontFamily,
          color: textPrimary,
          fontSize: GlassConstants.fontControl,
          fontWeight: AppTypography.medium,
        ),
      ),
    );
  }

  static ThemeData darkTheme({String? fontFamily}) {
    final effectiveFontFamily = fontFamily ?? AppTypography.family;
    return ThemeData(
      fontFamily: effectiveFontFamily,
      brightness: Brightness.dark,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.windows: AppPageTransitionsBuilder(),
      }),
      primaryColor: darkPrimaryColor,
      scaffoldBackgroundColor: darkBackgroundColor,
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ).copyWith(
        primary: darkPrimaryColor,
        onPrimary: darkBackgroundColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: darkSurfaceColor,
        error: errorColor,
      ),
      cardTheme: CardThemeData(
        color: darkCardColor.withValues(alpha: 0.6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        shadowColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: effectiveFontFamily,
          color: darkTextPrimary,
          fontSize: GlassConstants.fontHeading,
          fontWeight: AppTypography.semibold,
        ),
        iconTheme: IconThemeData(
          color: darkTextSecondary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: darkTextSecondary,
        size: GlassConstants.iconMedium,
      ),
      textTheme: TextTheme(
        labelLarge: AppTypography.buttonLabel,
        labelMedium: const TextStyle(fontSize: GlassConstants.fontSmall, fontWeight: FontWeight.w500),
        labelSmall: const TextStyle(fontSize: GlassConstants.fontCaption, fontWeight: FontWeight.w500),
        headlineLarge: TextStyle(
            color: darkTextPrimary, fontSize: GlassConstants.fontHero, fontWeight: AppTypography.bold),
        headlineMedium: TextStyle(
            color: darkTextPrimary, fontSize: GlassConstants.fontDetailTitle, fontWeight: AppTypography.semibold),
        headlineSmall: TextStyle(
            color: darkTextPrimary, fontSize: GlassConstants.fontHeadline, fontWeight: AppTypography.semibold),
        titleLarge: TextStyle(
            color: darkTextPrimary, fontSize: GlassConstants.fontHeading, fontWeight: AppTypography.medium),
        titleMedium: TextStyle(
            color: darkTextPrimary, fontSize: GlassConstants.fontSection, fontWeight: AppTypography.medium),
        titleSmall: TextStyle(
            color: darkTextSecondary,
            fontSize: GlassConstants.fontTitle,
            fontWeight: AppTypography.regular),
        bodyLarge: TextStyle(color: darkTextPrimary, fontSize: GlassConstants.fontSection),
        bodyMedium: TextStyle(color: darkTextSecondary, fontSize: GlassConstants.fontBodyLarge),
        bodySmall: TextStyle(color: darkTextSecondary, fontSize: GlassConstants.fontBody),
      ).apply(fontFamily: effectiveFontFamily),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimaryColor,
          foregroundColor: darkBackgroundColor,
          foregroundBuilder: AppMotion.buttonFace,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundBuilder: AppMotion.buttonFace,
          backgroundColor: darkPrimaryColor,
          foregroundColor: darkBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingLarge, vertical: GlassConstants.spacingCompact),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          ),
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: darkTextSecondary,
        ).copyWith(foregroundBuilder: AppMotion.buttonFace),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? darkPrimaryColor
              : darkSurfaceColor,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? darkPrimaryColor.withValues(alpha: 0.35)
              : darkBorderColor.withValues(alpha: 0.14),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? darkPrimaryColor.withValues(alpha: 0.45)
              : darkBorderColor.withValues(alpha: 0.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundBuilder: AppMotion.buttonFace,
          foregroundColor: darkPrimaryColor,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundBuilder: AppMotion.buttonFace,
          foregroundColor: darkPrimaryColor,
          side: BorderSide(color: darkPrimaryColor),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: darkPrimaryColor.withValues(alpha: 0.8),
        foregroundColor: darkBackgroundColor,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceColor.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: darkBorderColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: darkBorderColor.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          borderSide: BorderSide(color: darkPrimaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: GlassConstants.spacingMedium, vertical: GlassConstants.spacingControl),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.grey.withValues(alpha: 0.4)),
        radius: const Radius.circular(GlassConstants.radiusTiny),
        thickness: WidgetStateProperty.all(6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        color: darkSurfaceColor.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        textStyle: TextStyle(
          fontFamily: effectiveFontFamily,
          color: darkTextPrimary,
          fontSize: GlassConstants.fontControl,
          fontWeight: AppTypography.medium,
        ),
      ),
    );
  }

  static void showGlassSnackBar(BuildContext context, String message,
      {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingMedium, vertical: GlassConstants.spacingSmall),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.darkSurfaceColor.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(
              color: (color ?? AppTheme.getPrimaryColor(context)).withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: (color ?? AppTheme.getPrimaryColor(context)).withValues(alpha: 0.12),
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
                color: color ?? AppTheme.getPrimaryColor(context),
                size: GlassConstants.iconAction,
              ),
              const SizedBox(width: GlassConstants.spacingSmall),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: color ?? AppTheme.getPrimaryColor(context),
                    fontSize: GlassConstants.fontControl,
                    fontWeight: AppTypography.medium,
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
    final style = _glassMenuStyle(context);
    return showMenu<T>(
      context: context,
      popUpAnimationStyle: AppMotion.overlayStyle(context),
      position: position,
      shape: style.shape,
      color: style.color,
      elevation: style.elevation,
      surfaceTintColor: style.surfaceTintColor,
      shadowColor: style.shadowColor,
      items: items,
      initialValue: initialValue,
    );
  }

  static PopupMenuThemeData _glassMenuStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuTheme.of(context).copyWith(
      color: isDark
          ? darkSurfaceColor.withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.95),
    );
  }

  static Widget _buildToastBlur(
      {required BuildContext context, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: child,
    );
  }

  static void showGlassToast(
    BuildContext context, {
    required String message,
    IconData icon = Icons.check_circle,
    Color iconColor = const Color(0xFF10B981),
    Duration duration = const Duration(seconds: 2),
    int? maxLines = 2,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 40,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: AppEntrance(child: Material(
            color: Colors.transparent,
            child: Center(
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(GlassConstants.radiusMedium),
                child: _buildToastBlur(
                  context: context,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: GlassConstants.spacingComfortable, vertical: GlassConstants.spacingCompact),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkSurfaceColor.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.85),
                      borderRadius:
                          BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.darkGlassBorderWhite
                                .withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: GlassConstants.iconAction, color: iconColor),
                        const SizedBox(width: GlassConstants.spacingSmall),
                        Flexible(
                          child: Text(message,
                              style: TextStyle(
                                  fontSize: GlassConstants.fontTitle,
                                  color: AppTheme.getTextPrimary(context)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: maxLines),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(duration, () {
      overlayEntry.remove();
    });
  }

  /// 根据当前主题获取颜色
  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackgroundColor
        : backgroundColor;
  }

  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceColor
        : surfaceColor;
  }

  /// 获取更深层的表面色（用于详情页、弹窗等）
  static Color getSurfaceDeepColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceDeepColor
        : surfaceColor;
  }

  /// 获取详情页主文本色
  static Color getDetailTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkDetailTextPrimary
        : textPrimary;
  }

  /// 获取卡片/侧边栏标题色
  static Color getCardTitleColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkCardTitleColor
        : textPrimary;
  }

  static Color getCardColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkCardColor
        : cardColor;
  }

  static Color getTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextPrimary
        : textPrimary;
  }

  static Color getTextSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextSecondary
        : textSecondary;
  }

  static Color getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBorderColor
        : borderColor;
  }

  static Color getGlassFillColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkGlassFillColor
        : glassFillColor;
  }

  static LinearGradient getBackgroundGradient(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackgroundGradient
        : backgroundGradient;
  }

  static Color getFavoriteColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkFavoriteColor
        : favoriteColor;
  }

  static Color getStarColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkStarColor
        : starColor;
  }

  /// 根据当前主题获取主色
  static Color getPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkPrimaryColor
        : primaryColor;
  }

  static Color getOnPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackgroundColor
        : surfaceColor;
  }

  static Color getSecondaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFC4B5FD)
        : secondaryColor;
  }

  static Color getPrimaryLightColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkPrimaryColor
        : primaryLightColor;
  }

  static Color getSearchHighlightColor(BuildContext context) {
    return getStarColor(context).withValues(alpha: 0.4);
  }

  /// 获取主色渐变
  static LinearGradient getPrimaryGradient(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [getPrimaryColor(context), getSecondaryColor(context)],
          )
        : primaryGradient;
  }

  // 获取覆盖层颜色（用于模态遮罩、弹窗背景等）
  // 浅色和深色模式都使用相同的 alpha 值，确保遮罩效果一致
  static Color getOverlayColor(BuildContext context) {
    return Colors.black.withValues(alpha: 0.6);
  }

  static Color getDialogBarrierColor(BuildContext context) {
    return Colors.black.withValues(alpha: 0.3);
  }

  // 获取微弱阴影颜色（用于卡片、边框等轻微阴影）
  static Color getShadowColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.05);
  }

  // 获取禁用状态颜色
  // 注意：浅色模式保持与原来 Colors.grey 一致
  static Color getDisabledColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.withValues(alpha: 0.4)
        : Colors.grey;
  }

  // 获取输入框填充色
  static Color getInputFillColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceColor.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.5);
  }

  // 获取标签背景色
  // 注意：浅色模式保持与原来 Colors.white alpha 0.3 一致
  static Color getTagBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceColor.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.3);
  }

  // 获取卡片悬停色
  static Color getCardHoverColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceColor.withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.88);
  }

  // 获取卡片默认色
  static Color getCardDefaultColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceColor.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.65);
  }

  // 获取边框颜色（带透明度）
  static Color getBorderLightColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkGlassBorderWhite.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.35);
  }

  static Color getTextColorOnPrimary(BuildContext context) {
    return getOnPrimaryColor(context);
  }

  static Color getLoadingIndicatorColor(BuildContext context) {
    return getOnPrimaryColor(context);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = color ??
        (isDark ? AppTheme.darkGlassFillColor : AppTheme.glassFillColor);
    final borderColor =
        isDark ? AppTheme.darkGlassBorderWhite : AppTheme.glassBorderWhite;

    final innerContainer = Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: borderColor,
              width: 1,
            ),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppTheme.getPrimaryColor(context)
                    .withValues(alpha: isDark ? 0.05 : 0.03),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
        gradient: gradient,
      ),
      child: child,
    );
    if (isDark || !enableBlur) return innerContainer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: innerContainer,
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
  final FocusNode? focusNode;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(GlassConstants.spacingMedium),
    this.margin,
    this.borderRadius = GlassConstants.radiusLarge,
    this.color,
    this.enableHoverEffect = true,
    this.enableBorderBreathing = false,
    this.onTap,
    this.focusNode,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;
  AnimationController? _borderController;
  Animation<double>? _borderAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _borderController?.removeListener(_onBorderTick);
    if (widget.enableBorderBreathing &&
        !AppMotion.reduced(context) && TickerMode.valuesOf(context).enabled) {
      _borderController ??= AnimationController(
        duration: const Duration(seconds: 3),
        vsync: this,
      );
      if (!_borderController!.isAnimating) {
        _borderController!.repeat(reverse: true);
      }
      _borderAnimation = Tween<double>(begin: 0.15, end: 0.35)
          .chain(CurveTween(curve: Curves.easeInOut))
          .animate(_borderController!);
      _borderController!.addListener(_onBorderTick);
    } else {
      _borderController?.stop();
      _borderAnimation = null;
    }
  }

  void _onBorderTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _borderController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      enabled: widget.onTap != null,
      onShowFocusHighlight: (focused) => setState(() => _isFocused = focused),
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { widget.onTap?.call(); return null; })},
      child: Semantics(button: widget.onTap != null, child: MouseRegion(
      onEnter: widget.enableHoverEffect
          ? (_) => setState(() => _isHovered = true)
          : null,
      onExit: widget.enableHoverEffect
          ? (_) => setState(() {
                _isHovered = false;
                _isPressed = false;
              })
          : null,
      child: GestureDetector(
        onTapDown: widget.onTap != null
            ? (_) => setState(() => _isPressed = true)
            : null,
        onTapUp: widget.onTap != null
            ? (_) => setState(() => _isPressed = false)
            : null,
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AppControlScale(
          pressed: _isPressed && widget.onTap != null,
          hovered: _isHovered && widget.enableHoverEffect,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, GlassConstants.animFast),
            curve: GlassConstants.animCurve,
            margin: widget.margin,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.color ??
                  (isDark
                      ? (_isHovered
                          ? AppTheme.darkSurfaceColor.withValues(alpha: 0.88)
                          : AppTheme.darkSurfaceColor.withValues(alpha: 0.65))
                      : (_isHovered
                          ? Colors.white.withValues(alpha: 0.88)
                          : Colors.white.withValues(alpha: 0.65))),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isHovered || _isFocused
                    ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.25)
                    : widget.enableBorderBreathing
                        ? AppTheme.getPrimaryColor(context)
                            .withValues(alpha: _borderAnimation?.value ?? 0.35)
                        : (isDark
                            ? AppTheme.darkGlassBorderWhite
                                .withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.35)),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: _isHovered ? 28 : 16,
                  spreadRadius: _isHovered ? 2 : 1,
                  offset: Offset(0, _isHovered ? 6 : 4),
                ),
                BoxShadow(
                  color: (_isHovered
                          ? AppTheme.getSecondaryColor(context)
                          : AppTheme.getPrimaryColor(context))
                      .withValues(alpha: _isHovered ? 0.06 : 0.03),
                  blurRadius: _isHovered ? 50 : 40,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    )));
  }
}

// ===== 边框呼吸动画 =====
class BreathingBorder extends StatefulWidget {
  final Widget child;
  final bool isBreathing;
  final Color? color;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const BreathingBorder({
    super.key,
    required this.child,
    this.isBreathing = false,
    this.color,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    if (widget.isBreathing &&
        !AppMotion.reduced(context) && TickerMode.valuesOf(context).enabled) {
      _controller ??= AnimationController(
        duration: widget.duration,
        vsync: this,
      );
      _controller!.duration = widget.duration;
      if (!_controller!.isAnimating) _controller!.repeat(reverse: true);
      _animation = Tween<double>(
        begin: widget.minOpacity,
        end: widget.maxOpacity,
      ).chain(CurveTween(curve: Curves.easeInOut)).animate(_controller!);
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
              color: (widget.color ?? AppTheme.getPrimaryColor(context))
                  .withValues(alpha: opacity),
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
    this.padding = const EdgeInsets.symmetric(horizontal: GlassConstants.spacingComfortable, vertical: GlassConstants.spacingCompact),
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
    final enabled = widget.isEnabled && widget.onPressed != null;
    return MouseRegion(
      onEnter:
          widget.isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.isEnabled
          ? (_) => setState(() {
                _isHovered = false;
                _isPressed = false;
              })
          : null,
      child: GestureDetector(
        onTapDown:
            widget.isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp:
            widget.isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            widget.isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: AppControlScale(
          pressed: _isPressed, hovered: _isHovered, enabled: enabled,
          child: AnimatedContainer(
          duration: AppMotion.duration(context, GlassConstants.animFast),
          curve: GlassConstants.animCurve,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.gradient == null
                ? (widget.color ??
                    (Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkSurfaceColor.withValues(
                            alpha: _isPressed
                                ? 0.5
                                : _isHovered
                                    ? 0.6
                                    : 0.4)
                        : Colors.white.withValues(
                            alpha: _isPressed
                                ? 0.5
                                : _isHovered
                                    ? 0.6
                                    : 0.4)))
                : null,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.gradient == null
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.darkGlassBorderWhite
                          .withValues(alpha: _isHovered ? 0.4 : 0.2)
                      : Colors.white.withValues(alpha: _isHovered ? 0.4 : 0.2))
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isHovered ? AppTheme.getPrimaryColor(context) : Colors.black)
                    .withValues(alpha: 0.1),
                blurRadius: _isHovered ? 15 : 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: widget.child,
          ),
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

class _GradientBackgroundState extends State<GradientBackground> {
  static const double _fixedGlowOpacity = 0.045;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? AppTheme.darkGradientColors
              : AppTheme.lightGradientColors,
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFF2563EB).withValues(
                        alpha: isDark
                            ? _fixedGlowOpacity * 0.5
                            : _fixedGlowOpacity),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFF7C3AED).withValues(
                        alpha: isDark
                            ? _fixedGlowOpacity * 0.4
                            : _fixedGlowOpacity * 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
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
  final bool enableBlur;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.enableBlur = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBar = Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingMedium),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurfaceColor.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.7),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppTheme.darkGlassBorderWhite.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) leading!,
          Expanded(child: Align(alignment: Alignment.centerLeft, child: title)),
          if (actions != null) ...actions!,
        ],
      ),
    );
    if (isDark || !enableBlur) return appBar;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassConstants.blurLarge,
          sigmaY: GlassConstants.blurLarge,
        ),
        child: appBar,
      ),
    );
  }
}

// ===== 搜索栏 =====
class GlassSearchBar extends StatefulWidget {
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
  State<GlassSearchBar> createState() => _GlassSearchBarState();
}

class _GlassSearchBarState extends State<GlassSearchBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: _buildSearchBar(context),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return GlassContainer(
      margin: widget.margin ?? EdgeInsets.zero,
      borderRadius: GlassConstants.radiusXLarge,
      blur: GlassConstants.blurSmall,
      color: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkSurfaceColor.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingMedium),
      border: Border.all(
        color: _focused
            ? AppTheme.getPrimaryColor(context)
            : AppTheme.getBorderLightColor(context).withValues(alpha: 0.4),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: widget.controller,
          onChanged: widget.onChanged,
          style:
              TextStyle(color: AppTheme.getTextPrimary(context), fontSize: GlassConstants.fontControl),
          decoration: InputDecoration(
            hintText: widget.hintText ?? '搜索...',
            filled: false,
            hintStyle: TextStyle(
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.6),
              fontSize: GlassConstants.fontControl,
            ),
            prefixIcon: Icon(
              Icons.search,
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.6),
              size: GlassConstants.iconControl,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: GlassConstants.spacingInline),
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
    final chipColor = color ?? AppTheme.getPrimaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, GlassConstants.animFast),
        curve: GlassConstants.animCurve,
        padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingControl, vertical: GlassConstants.spacingSmall),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.2)
              : (Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkSurfaceColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(
            color: isSelected
                ? chipColor.withValues(alpha: 0.5)
                : (Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkGlassBorderWhite.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.3)),
          ),
          boxShadow: [
            BoxShadow(
              color: chipColor.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : AppTheme.getTextSecondary(context),
            fontSize: GlassConstants.fontBody,
            fontWeight: isSelected ? AppTypography.semibold : AppTypography.regular,
          ),
        ),
      ),
    );
  }
}

// ===== 交错动画列表项 =====
class StaggeredItem extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;
  final bool animate;

  const StaggeredItem({
    super.key,
    required this.child,
    required this.index,
    this.baseDelay = const Duration(milliseconds: 30),
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppEntrance(
      animate: animate && index < 6,
      delay: baseDelay * index.clamp(0, 4),
      child: child,
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
              child: AppTheme._buildToastBlur(
                context: context,
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
        _controller.duration = AppMotion.duration(context, AppMotion.fast);
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
          horizontal: GlassConstants.spacingLarge,
          vertical: GlassConstants.spacingCompact,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkSurfaceColor.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(
            GlassConstants.radiusMedium,
          ),
          border: Border.all(
            color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.12),
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
             Icon(
              Icons.check_circle_rounded,
              color: AppTheme.getPrimaryColor(context),
              size: GlassConstants.iconAction,
            ),
            const SizedBox(width: GlassConstants.spacingSmall),
            Flexible(
              child: Text(
                widget.text,
                overflow: TextOverflow.ellipsis,
                style:  TextStyle(
                  color: AppTheme.getPrimaryColor(context),
                  fontSize: GlassConstants.fontControl,
                  fontWeight: AppTypography.medium,
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
      ViewMode.list => Icons.view_list,
      ViewMode.poster => Icons.grid_view,
    };

// ===== 玻璃拟态 TabBar =====
class GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  final AppTabController controller;
  final List<Widget> tabs;

  const GlassTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    controller.reducedMotion = AppMotion.reduced(context);
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassConstants.blurSmall,
          sigmaY: GlassConstants.blurSmall,
        ),
        child: Container(
          height: preferredSize.height,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.darkSurfaceColor.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.35),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkGlassBorderWhite.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: TabBar(
            controller: controller,
            tabs: tabs,
            labelColor: AppTheme.getPrimaryColor(context),
            unselectedLabelColor: AppTheme.getTextSecondary(context),
            labelStyle: const TextStyle(
              fontWeight: AppTypography.semibold,
              fontSize: GlassConstants.fontControl,
              height: 1.0,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: AppTypography.regular,
              fontSize: GlassConstants.fontControl,
              height: 1.0,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            ),
            indicatorPadding:
                const EdgeInsets.symmetric(horizontal: GlassConstants.spacingTight, vertical: GlassConstants.spacingTight),
            dividerColor: Colors.transparent,
            splashBorderRadius:
                BorderRadius.circular(GlassConstants.radiusSmall),
          ),
        ),
      ),
    );
  }
}

// ===== 玻璃拟态对话框 =====
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final animationStyle = AppMotion.overlayStyle(context);
  return navigator.push<T>(_SpringDialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    animationStyle: animationStyle,
  ));
}

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showAppDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: AppTheme.getDialogBarrierColor(context),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape):
              const _DismissDialogIntent(),
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
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkSurfaceColor.withValues(alpha: 0.88)
                        : Colors.white.withValues(alpha: 0.88),
                    borderRadius:
                        BorderRadius.circular(GlassConstants.radiusLarge),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkGlassBorderWhite.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.05),
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

Widget buildAppTextSelectionToolbar(
  BuildContext context,
  TextSelectionToolbarAnchors anchors,
  List<ContextMenuButtonItem> buttonItems, {
  VoidCallback? onCopy,
}) {
  final availableItems =
      buttonItems.where((item) => _textSelectionLabel(item).isNotEmpty);
  if (availableItems.isEmpty) return const SizedBox.shrink();

  final style = AppTheme._glassMenuStyle(context);
  final mediaPadding = MediaQuery.paddingOf(context);
  const screenPadding = GlassConstants.spacingSmall;
  final insets = EdgeInsets.only(
    left: mediaPadding.left + screenPadding,
    top: mediaPadding.top + screenPadding,
    right: mediaPadding.right + screenPadding,
    bottom: mediaPadding.bottom + screenPadding,
  );
  final items = availableItems
      .map((item) => item.type == ContextMenuButtonType.copy && onCopy != null
          ? item.copyWith(onPressed: onCopy)
          : item);

  return Padding(
    padding: insets,
    child: CustomSingleChildLayout(
      delegate: DesktopTextSelectionToolbarLayoutDelegate(
        anchor: anchors.primaryAnchor - Offset(insets.left, insets.top),
      ),
      child: Material(
        color: style.color,
        shape: style.shape,
        elevation: style.elevation ?? 0,
        surfaceTintColor: style.surfaceTintColor,
        shadowColor: style.shadowColor,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
          child: IntrinsicWidth(
            stepWidth: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    enabled: item.onPressed != null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: GlassConstants.spacingCompact,
                    ),
                    leading: Icon(_textSelectionIcon(item.type),
                        size: GlassConstants.iconAction),
                    title: Text(_textSelectionLabel(item),
                        style: style.textStyle),
                    onTap: item.onPressed == null
                        ? null
                        : () {
                            ContextMenuController.removeAny();
                            item.onPressed!();
                          },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildAppEditableTextContextMenu(
        BuildContext context, EditableTextState state,
        {VoidCallback? onCopy}) =>
    buildAppTextSelectionToolbar(
        context, state.contextMenuAnchors, state.contextMenuButtonItems,
        onCopy: onCopy);

Widget buildAppSelectableTextContextMenu(
        BuildContext context, SelectableRegionState state,
        {VoidCallback? onCopy}) =>
    buildAppTextSelectionToolbar(
        context, state.contextMenuAnchors, state.contextMenuButtonItems,
        onCopy: onCopy);

String _textSelectionLabel(ContextMenuButtonItem item) => switch (item.type) {
      ContextMenuButtonType.cut => '剪切',
      ContextMenuButtonType.copy => '复制',
      ContextMenuButtonType.paste => '粘贴',
      ContextMenuButtonType.selectAll => '全选',
      ContextMenuButtonType.delete => '删除',
      ContextMenuButtonType.lookUp => '查找',
      ContextMenuButtonType.searchWeb => '网页搜索',
      ContextMenuButtonType.share => '分享',
      ContextMenuButtonType.liveTextInput => '识别文字',
      ContextMenuButtonType.custom => item.label ?? '',
    };

IconData _textSelectionIcon(ContextMenuButtonType type) => switch (type) {
      ContextMenuButtonType.cut => Icons.content_cut,
      ContextMenuButtonType.copy => Icons.content_copy,
      ContextMenuButtonType.paste => Icons.content_paste,
      ContextMenuButtonType.selectAll => Icons.select_all,
      ContextMenuButtonType.delete => Icons.delete_outline,
      ContextMenuButtonType.lookUp => Icons.search,
      ContextMenuButtonType.searchWeb => Icons.public,
      ContextMenuButtonType.share => Icons.share,
      ContextMenuButtonType.liveTextInput => Icons.text_fields,
      ContextMenuButtonType.custom => Icons.more_horiz,
    };

class _DismissDialogIntent extends Intent {
  const _DismissDialogIntent();
}

class _SpringDialogRoute<T> extends DialogRoute<T> {
  _SpringDialogRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    required bool barrierDismissible,
    required Color? barrierColor,
    required AnimationStyle animationStyle,
  })  : _reverseDuration = animationStyle.reverseDuration,
        super(
          context: context,
          builder: builder,
          themes: InheritedTheme.capture(
              from: context,
              to: Navigator.of(context, rootNavigator: true).context),
          barrierDismissible: barrierDismissible,
          barrierColor: barrierColor,
          animationStyle: animationStyle,
        );

  final Duration? _reverseDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reverseDuration ?? super.reverseTransitionDuration;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) =>
      AppDialogTransition(
        animation: animation,
        child: child,
      );
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
          AppEntrance(child: Icon(icon,
              size: GlassConstants.iconEmptyState,
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.4))),
          const SizedBox(height: GlassConstants.spacingMedium),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.6),
              fontSize: GlassConstants.fontTitle,
              fontWeight: AppTypography.medium,
            ),
          ),
          if (subMessage != null) ...[
            const SizedBox(height: GlassConstants.spacingSmall),
            Text(
              subMessage!,
              style: TextStyle(
                color:
                    AppTheme.getTextSecondary(context).withValues(alpha: 0.4),
                fontSize: GlassConstants.fontBody,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: GlassConstants.spacingComfortable),
            action!,
          ],
        ],
      ),
    );
  }
}
