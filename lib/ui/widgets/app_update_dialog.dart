import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/app_update_service.dart';
import '../../core/utils/changelog_parser.dart';
import '../theme/app_theme.dart';

enum AppUpdatePromptAction {
  later,
  manualDownload,
  install,
}

Future<AppUpdatePromptAction?> showAppUpdatePrompt(
  BuildContext context,
  AppUpdateCheckResult result,
) {
  final textTheme = Theme.of(context).textTheme;
  return showGlassDialog<AppUpdatePromptAction>(
    context: context,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700, maxHeight: 620),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '发现新版本',
              style: textTheme.titleMedium?.copyWith(
                color: AppTheme.getTextPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '当前版本：v${result.currentVersion}\n'
              '最新版本：v${result.latestEntry?.version ?? result.currentVersion}',
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.getTextSecondary(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '更新日志',
              style: textTheme.titleSmall?.copyWith(
                color: AppTheme.getTextPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 380,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: result.updateEntries
                      .map((entry) => _buildChangelogEntry(context, entry))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    AppUpdatePromptAction.later,
                  ),
                  child: const Text('稍后更新'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    AppUpdatePromptAction.manualDownload,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('手动下载'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    AppUpdatePromptAction.install,
                  ),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('立即更新'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildChangelogEntry(BuildContext context, ChangelogEntry entry) {
  final primaryColor = AppTheme.getTextPrimary(context);
  final secondaryColor = AppTheme.getTextSecondary(context);
  final textTheme = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.date == null
              ? 'v${entry.version}'
              : 'v${entry.version} (${entry.date})',
          style: textTheme.bodySmall?.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        MarkdownBody(
          data: entry.body,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: textTheme.bodySmall?.copyWith(
              color: secondaryColor,
              height: 1.5,
            ),
            h3: textTheme.titleSmall?.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w600,
            ),
            strong: textTheme.bodySmall?.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w700,
            ),
            listBullet: textTheme.bodySmall?.copyWith(
              color: secondaryColor,
            ),
            code: textTheme.bodySmall?.copyWith(
              color: primaryColor,
              backgroundColor: AppTheme.getSurfaceColor(context),
            ),
            blockSpacing: 6,
            listIndent: 20,
          ),
        ),
      ],
    ),
  );
}

Future<bool?> showAppUpdateFallbackDialog({
  required BuildContext context,
  required String title,
  required String message,
}) {
  final textTheme = Theme.of(context).textTheme;
  return showGlassDialog<bool>(
    context: context,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: AppTheme.getTextPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.getTextSecondary(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开网盘'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 下载进度对话框，由 [progressListenable] 驱动实时刷新。
Future<void> showAppUpdateDownloadProgress(
  BuildContext context, {
  required String version,
  required ValueListenable<AppUpdateDownloadProgress> progressListenable,
}) {
  final textTheme = Theme.of(context).textTheme;
  return showGlassDialog<void>(
    context: context,
    barrierDismissible: false,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<AppUpdateDownloadProgress>(
          valueListenable: progressListenable,
          builder: (context, progress, _) {
            final fraction = progress.fraction;
            final percentText = fraction == null
                ? null
                : '${(fraction * 100).toStringAsFixed(1)}%';
            final totalBytes = progress.totalBytes;
            final sizeText = totalBytes == null
                ? _formatBytes(progress.receivedBytes)
                : '${_formatBytes(progress.receivedBytes)} / '
                    '${_formatBytes(totalBytes)}';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在下载更新 v$version',
                  style: textTheme.titleMedium?.copyWith(
                    color: AppTheme.getTextPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: fraction,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                  valueColor: AlwaysStoppedAnimation(
                    AppTheme.getPrimaryColor(context),
                  ),
                  backgroundColor: AppTheme.getBorderColor(context),
                ),
                const SizedBox(height: 10),
                Text(
                  percentText == null ? sizeText : '$percentText（$sizeText）',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// 上次安装未完成的提示：返回 true 继续安装，false 删除缓存，null 稍后处理。
Future<bool?> showAppUpdateResumeDialog(
  BuildContext context, {
  required String version,
}) {
  final textTheme = Theme.of(context).textTheme;
  return showGlassDialog<bool>(
    context: context,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '上次更新未完成',
              style: textTheme.titleMedium?.copyWith(
                color: AppTheme.getTextPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '检测到 v$version 的更新包已下载，但安装未能完成。'
              '是否继续安装？（无需重新下载）',
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.getTextSecondary(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('删除缓存'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.system_update_alt, size: 16),
                  label: const Text('继续安装'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

Future<void> openAppUpdateQuarkPan(BuildContext context) async {
  final uri = Uri.parse(appQuarkUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (context.mounted) {
      AppTheme.showGlassToast(
        context,
        message: '下载后解压替换原文件夹即可升级软件',
        icon: Icons.info_outline,
        iconColor: AppTheme.getPrimaryColor(context),
        duration: const Duration(seconds: 5),
      );
    }
  }
}
