// lib/ui/pages/games/cloud_backup_dialog.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/webdav_service.dart';
import '../../theme/app_theme.dart';

/// 云端备份列表对话框
class CloudBackupDialog extends ConsumerStatefulWidget {
  final Game game;
  final String webdavUrl;
  final String webdavUsername;
  final String webdavPassword;
  final VoidCallback onBackupDownloaded;

  const CloudBackupDialog({
    super.key,
    required this.game,
    required this.webdavUrl,
    required this.webdavUsername,
    required this.webdavPassword,
    required this.onBackupDownloaded,
  });

  @override
  ConsumerState<CloudBackupDialog> createState() => _CloudBackupDialogState();
}

class _CloudBackupDialogState extends ConsumerState<CloudBackupDialog> {
  List<WebDavFile> _files = [];
  bool _isLoading = true;
  String? _matchedFolder;

  @override
  void initState() {
    super.initState();
    _loadCloudBackups();
  }

  /// 加载云端备份列表（含模糊匹配）
  Future<void> _loadCloudBackups() async {
    setState(() => _isLoading = true);

    final service = ref.read(webdavServiceProvider);
    final gameTitle = widget.game.title ?? '';

    // 列出所有游戏文件夹并进行模糊匹配
    final folders = await service.listGameFolders(
      serverUrl: widget.webdavUrl,
      username: widget.webdavUsername,
      password: widget.webdavPassword,
    );

    // 双向近似匹配：先尝试模糊匹配，回退到精确清理后的名称
    String? matchedFolder = WebdavService.fuzzyMatchGameFolder(gameTitle, folders);
    matchedFolder ??= WebdavService.sanitizeGameTitle(gameTitle);

    List<WebDavFile> files = [];
    if (matchedFolder != null) {
      files = await service.listGameBackups(
        serverUrl: widget.webdavUrl,
        username: widget.webdavUsername,
        password: widget.webdavPassword,
        gameFolder: matchedFolder,
      );
    }

    if (mounted) {
      setState(() {
        _files = files;
        _matchedFolder = matchedFolder;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
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
          child: AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusLarge)),
            title: Row(
              children: [
                const Icon(Icons.cloud_queue, color: AppTheme.primaryColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '云端备份 - ${widget.game.title ?? "未知游戏"}',
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  color: AppTheme.textSecondary,
                  onPressed: _loadCloudBackups,
                  tooltip: '刷新',
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppTheme.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 700,
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _files.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              _matchedFolder == null ? '未找到匹配的云端备份文件夹' : '暂无云端备份',
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 32,
                            horizontalMargin: 12,
                            headingTextStyle: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            dataTextStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            columns: const [
                              DataColumn(label: Text('名称')),
                              DataColumn(label: Text('大小'), numeric: true),
                              DataColumn(label: Text('操作'), numeric: true),
                            ],
                            rows: _files.where((f) => f.sizeBytes > 0).map((f) {
                              return DataRow(cells: [
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 350),
                                    child: Text(
                                      f.name,
                                      softWrap: true,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text(f.sizeFormatted)),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _MiniIconButton(
                                        icon: Icons.download,
                                        tooltip: '下载此备份',
                                        color: AppTheme.primaryColor,
                                        onTap: () => _downloadBackup(f),
                                      ),
                                      const SizedBox(width: 4),
                                      _MiniIconButton(
                                        icon: Icons.restore,
                                        tooltip: '恢复到此备份',
                                        color: AppTheme.successColor,
                                        onTap: () => _restoreFromCloud(f),
                                      ),
                                      const SizedBox(width: 4),
                                      _MiniIconButton(
                                        icon: Icons.delete_outline,
                                        tooltip: '删除',
                                        color: AppTheme.errorColor,
                                        onTap: () => _deleteCloudBackup(f),
                                      ),
                                    ],
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }

  /// 下载云端备份到本地
  Future<void> _downloadBackup(WebDavFile file) async {
    final backupService = ref.read(backupServiceProvider);
    final backupDir = backupService.getBackupDir(widget.game.path);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final localPath = '${backupDir.path}\\${file.name}';

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在下载...', icon: Icons.cloud_download, iconColor: AppTheme.primaryColor);
    }

    final service = ref.read(webdavServiceProvider);
    final success = await service.downloadGameBackup(
      serverUrl: widget.webdavUrl,
      username: widget.webdavUsername,
      password: widget.webdavPassword,
      gameFolder: _matchedFolder!,
      remoteFileName: file.name,
      localPath: localPath,
    );

    if (mounted) {
      if (success) {
        AppTheme.showGlassToast(context, message: '下载成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        widget.onBackupDownloaded();
      } else {
        AppTheme.showGlassToast(context, message: '下载失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 从云端下载并恢复备份
  Future<void> _restoreFromCloud(WebDavFile file) async {
    final savePath = widget.game.savePath;
    if (savePath == null || savePath.isEmpty) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '请先设置存档路径', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return;
    }

    // 先下载到本地，再还原
    final backupService = ref.read(backupServiceProvider);
    final backupDir = backupService.getBackupDir(widget.game.path);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final localPath = '${backupDir.path}\\${file.name}';

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在下载并恢复...', icon: Icons.hourglass_empty, iconColor: AppTheme.primaryColor);
    }

    final service = ref.read(webdavServiceProvider);
    final success = await service.downloadGameBackup(
      serverUrl: widget.webdavUrl,
      username: widget.webdavUsername,
      password: widget.webdavPassword,
      gameFolder: _matchedFolder!,
      remoteFileName: file.name,
      localPath: localPath,
    );

    if (!success) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '下载失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
      return;
    }

    // 还原
    final restored = await backupService.restoreBackup(
      gamePath: widget.game.path,
      backupFilePath: localPath,
      savePath: savePath,
    );

    if (mounted) {
      if (restored) {
        AppTheme.showGlassToast(context, message: '恢复成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
      } else {
        AppTheme.showGlassToast(context, message: '恢复失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 删除云端备份（含确认弹窗，删除后刷新列表）
  Future<void> _deleteCloudBackup(WebDavFile file) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('删除云端备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text('确定要删除云端备份 "${file.name}" 吗？', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final service = ref.read(webdavServiceProvider);
    final success = await service.deleteGameBackup(
      serverUrl: widget.webdavUrl,
      username: widget.webdavUsername,
      password: widget.webdavPassword,
      gameFolder: _matchedFolder!,
      remoteFileName: file.name,
    );

    if (mounted) {
      if (success) {
        AppTheme.showGlassToast(context, message: '已删除', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        _loadCloudBackups(); // 删除后刷新列表
      } else {
        AppTheme.showGlassToast(context, message: '删除失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }
}

/// 迷你图标按钮组件
class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _DismissDialogIntent extends Intent {
  const _DismissDialogIntent();
}
