import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 询问是否删除本次刮削后待处理的旧配图。
Future<bool> confirmScrapedImageCleanup({
  required BuildContext context,
  required String gameTitle,
  required int imageCount,
}) async {
  if (!context.mounted) return false;

  final deleteImages = await showGlassDialog<bool>(
    context: context,
    child: Builder(
      builder: (dialogContext) => SizedBox(
        width: GlassConstants.dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GlassConstants.spacingLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('处理旧配图',
                        style: AppTypography.dialogTitle(dialogContext)),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(dialogContext, false),
                    icon: Icon(Icons.close,
                        size: GlassConstants.iconControl,
                        color: AppTheme.getTextSecondary(dialogContext)),
                  ),
                ],
              ),
              const SizedBox(height: GlassConstants.spacingMedium),
              Text(
                '「$gameTitle」有 $imageCount 张旧配图，是否保留？',
                style: TextStyle(
                  fontSize: GlassConstants.fontControl,
                  height: AppTypography.bodyHeight,
                  color: AppTheme.getTextPrimary(dialogContext),
                ),
              ),
              const SizedBox(height: GlassConstants.spacingSmall),
              Text(
                '保留后仍可在图库查看。删除会移除这些旧图。',
                style: TextStyle(
                  fontSize: GlassConstants.fontBody,
                  height: AppTypography.bodyHeight,
                  color: AppTheme.getTextSecondary(dialogContext),
                ),
              ),
              const SizedBox(height: GlassConstants.spacingLarge),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: GlassConstants.spacingSmall,
                overflowSpacing: GlassConstants.spacingSmall,
                children: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('保留旧图'),
                  ),
                  ElevatedButton(
                    style: AppButtonStyles.solid(color: AppTheme.errorColor),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('删除旧图'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return deleteImages == true;
}
