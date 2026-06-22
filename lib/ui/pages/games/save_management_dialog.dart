// lib/ui/pages/games/save_management_dialog.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/models.dart';
import '../../../core/models/backup_entry.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import 'cloud_backup_dialog.dart';

/// 存档管理对话框
class SaveManagementDialog extends ConsumerStatefulWidget {
  final Game game;

  const SaveManagementDialog({super.key, required this.game});

  @override
  ConsumerState<SaveManagementDialog> createState() => _SaveManagementDialogState();
}

class _SaveManagementDialogState extends ConsumerState<SaveManagementDialog> {
  late String? _savePath;
  List<BackupEntry> _backups = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _savePath = widget.game.savePath;
    _loadBackups();
    _autoImportSaveFolder();
  }

  /// 自动导入游戏目录下的"存档"文件夹
  Future<void> _autoImportSaveFolder() async {
    final service = ref.read(backupServiceProvider);
    final result = await service.autoImportSaveFolder(widget.game.path);
    if (result != null && mounted) {
      _loadBackups();
    }
  }

  /// 加载本地备份列表
  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    final service = ref.read(backupServiceProvider);
    final backups = await service.listBackups(widget.game.path);
    if (mounted) {
      setState(() {
        _backups = backups;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Focus(
        autofocus: true,
        onKey: (node, event) {
          if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(GlassConstants.radiusXLarge),
              border: Border.all(color: AppTheme.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(),
                _buildSavePathSection(),
                _buildActionButtons(),
                const Divider(height: 1),
                Expanded(child: _buildBackupList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建顶部标题栏
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.folder_special, color: AppTheme.primaryColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '存档管理 - ${widget.game.title ?? "未知游戏"}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppTheme.textSecondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 构建存档路径显示区域
  Widget _buildSavePathSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _savePath ?? '未设置存档路径',
              style: TextStyle(
                fontSize: 13,
                color: _savePath != null ? AppTheme.textSecondary : AppTheme.warningColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: _editSavePath,
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('修改路径', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                foregroundColor: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建六个操作按钮
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildActionButton(Icons.folder_open, '打开存档文件夹', AppTheme.primaryColor, _openSaveFolder),
          _buildActionButton(Icons.backup, '打开备份文件夹', AppTheme.secondaryColor, _openBackupFolder),
          _buildActionButton(Icons.add_circle_outline, '添加自定义备份', AppTheme.warningColor, _addCustomBackup),
          _buildActionButton(Icons.save_alt, '备份当前存档', AppTheme.successColor, _backupCurrentSave),
          _buildActionButton(Icons.cloud_outlined, '查看云端备份', AppTheme.primaryColor, _showCloudBackups),
          _buildActionButton(Icons.delete_sweep_outlined, '批量删除备份', AppTheme.errorColor, _batchDeleteBackups),
        ],
      ),
    );
  }

  /// 构建单个操作按钮
  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建备份列表
  Widget _buildBackupList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_backups.isEmpty) {
      return const Center(
        child: Text('暂无备份', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _backups.length,
      itemBuilder: (context, index) {
        final backup = _backups[index];
        return _buildBackupItem(backup);
      },
    );
  }

  /// 构建单个备份条目
  Widget _buildBackupItem(BackupEntry backup) {
    final isImported = backup.source == BackupSource.imported;
    final isPreRestore = backup.source == BackupSource.preRestore;

    // 背景色：还原前备份=黄色，导入备份=蓝色，手动备份=默认
    final bgColor = isPreRestore
        ? AppTheme.warningColor.withValues(alpha: 0.08)
        : isImported
            ? AppTheme.primaryColor.withValues(alpha: 0.08)
            : AppTheme.backgroundColor.withValues(alpha: 0.5);
    final borderColor = isPreRestore
        ? AppTheme.warningColor.withValues(alpha: 0.3)
        : isImported
            ? AppTheme.primaryColor.withValues(alpha: 0.3)
            : AppTheme.borderColor.withValues(alpha: 0.5);
    final accentColor = isPreRestore
        ? AppTheme.warningColor
        : isImported
            ? AppTheme.primaryColor
            : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isImported ? Icons.input : (isPreRestore ? Icons.history : Icons.save),
            size: 18,
            color: accentColor ?? AppTheme.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              backup.name,
              style: TextStyle(
                fontSize: 14,
                color: accentColor ?? AppTheme.textPrimary,
                fontWeight: (isImported || isPreRestore) ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            backup.sizeFormatted,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 16),
          _buildMiniButton(Icons.edit, '编辑名称', AppTheme.primaryColor, () => _renameBackup(backup)),
          const SizedBox(width: 4),
          _buildMiniButton(Icons.cloud_upload_outlined, '备份至云端', AppTheme.secondaryColor, () => _uploadToCloud(backup)),
          const SizedBox(width: 4),
          _buildMiniButton(Icons.restore, '还原到此备份', AppTheme.successColor, () => _restoreBackup(backup)),
          const SizedBox(width: 4),
          _buildMiniButton(Icons.delete_outline, '删除', AppTheme.errorColor, () => _deleteBackup(backup)),
        ],
      ),
    );
  }

  /// 构建操作小图标按钮
  Widget _buildMiniButton(IconData icon, String tooltip, Color color, VoidCallback onTap) {
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

  // --- 操作方法 ---

  /// 修改存档路径
  Future<void> _editSavePath() async {
    final controller = TextEditingController(text: _savePath ?? '');
    await showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑存档路径', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '输入存档文件夹路径', labelText: '存档路径'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final newPath = controller.text.trim();
                    final repo = ref.read(gameRepositoryProvider);
                    await repo.updateSavePath(widget.game.id!, newPath.isEmpty ? null : newPath);
                    if (mounted) {
                      setState(() => _savePath = newPath.isEmpty ? null : newPath);
                      Navigator.pop(context);
                      AppTheme.showGlassToast(context, message: '存档路径已更新');
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  /// 打开存档文件夹
  Future<void> _openSaveFolder() async {
    if (_savePath == null || _savePath!.isEmpty) {
      AppTheme.showGlassToast(context, message: '请先设置存档路径', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      return;
    }
    try {
      await launchUrl(Uri.file(_savePath!));
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '无法打开路径: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 打开备份文件夹
  Future<void> _openBackupFolder() async {
    final backupDir = ref.read(backupServiceProvider).getBackupDir(widget.game.path);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    try {
      await launchUrl(Uri.file(backupDir.path));
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '无法打开路径: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 添加自定义备份（支持 zip 文件和文件夹）
  Future<void> _addCustomBackup() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    String? selectedPath;

    if (result != null && result.files.single.path != null) {
      selectedPath = result.files.single.path!;
    } else {
      // 尝试选择文件夹
      final dirPath = await FilePicker.getDirectoryPath();
      if (dirPath != null) {
        selectedPath = dirPath;
      }
    }

    if (selectedPath == null) return;

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在导入备份...', icon: Icons.hourglass_empty, iconColor: AppTheme.primaryColor);
    }

    final service = ref.read(backupServiceProvider);
    final entry = await service.importBackup(
      gamePath: widget.game.path,
      sourcePath: selectedPath,
    );

    if (mounted) {
      if (entry != null) {
        AppTheme.showGlassToast(context, message: '导入成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        _loadBackups();
      } else {
        AppTheme.showGlassToast(context, message: '导入失败，请检查文件格式', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 备份当前存档
  Future<void> _backupCurrentSave() async {
    if (_savePath == null || _savePath!.isEmpty) {
      AppTheme.showGlassToast(context, message: '请先设置存档路径', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      return;
    }

    final saveDir = Directory(_savePath!);
    if (!await saveDir.exists()) {
      AppTheme.showGlassToast(context, message: '存档目录不存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      return;
    }

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在备份...', icon: Icons.hourglass_empty, iconColor: AppTheme.primaryColor);
    }

    final service = ref.read(backupServiceProvider);
    final entry = await service.createBackup(
      gamePath: widget.game.path,
      savePath: _savePath!,
    );

    if (mounted) {
      if (entry != null) {
        AppTheme.showGlassToast(context, message: '备份成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        _loadBackups();
      } else {
        AppTheme.showGlassToast(context, message: '备份失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 打开云端备份对话框
  Future<void> _showCloudBackups() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final url = prefs.getString('webdav_url') ?? '';
    final username = prefs.getString('webdav_username') ?? '';
    final password = prefs.getString('webdav_password') ?? '';

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '请先在设置中配置 WebDAV', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => CloudBackupDialog(
          game: widget.game,
          webdavUrl: url,
          webdavUsername: username,
          webdavPassword: password,
          onBackupDownloaded: _loadBackups,
        ),
      );
    }
  }

  /// 批量删除备份
  Future<void> _batchDeleteBackups() async {
    final selected = <String>{};

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('批量删除备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              SizedBox(
                width: 500,
                height: 300,
                child: ListView.builder(
                  itemCount: _backups.length,
                  itemBuilder: (ctx, index) {
                    final backup = _backups[index];
                    final isSelected = selected.contains(backup.filePath);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            selected.add(backup.filePath);
                          } else {
                            selected.remove(backup.filePath);
                          }
                        });
                      },
                      title: Text(backup.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(backup.sizeFormatted, style: const TextStyle(fontSize: 12)),
                      dense: true,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
                    child: Text('删除 ${selected.length} 项'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && selected.isNotEmpty) {
      final service = ref.read(backupServiceProvider);
      int count = 0;
      for (final path in selected) {
        if (await service.deleteBackup(path)) count++;
      }
      if (mounted) {
        AppTheme.showGlassToast(context, message: '已删除 $count 个备份', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        _loadBackups();
      }
    }
  }

  /// 重命名备份
  Future<void> _renameBackup(BackupEntry backup) async {
    final controller = TextEditingController(text: backup.name);

    final newName = await showGlassDialog<String>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑备份名称', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '输入新名称'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, controller.text.trim()),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != backup.name) {
      final service = ref.read(backupServiceProvider);
      final success = await service.renameBackup(backup.filePath, newName);
      if (mounted) {
        if (success) {
          AppTheme.showGlassToast(context, message: '重命名成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
          _loadBackups();
        } else {
          AppTheme.showGlassToast(context, message: '重命名失败，可能名称已存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
      }
    }
  }

  /// 上传备份到云端
  Future<void> _uploadToCloud(BackupEntry backup) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final url = prefs.getString('webdav_url') ?? '';
    final username = prefs.getString('webdav_username') ?? '';
    final password = prefs.getString('webdav_password') ?? '';

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '请先在设置中配置 WebDAV', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return;
    }

    final gameTitle = widget.game.title ?? 'unknown';
    final service = ref.read(webdavServiceProvider);

    // 检查是否已上传（根据文件名判断，避免重复上传）
    final existingFiles = await service.listGameBackups(
      serverUrl: url, username: username, password: password, gameFolder: gameTitle,
    );
    final alreadyUploaded = existingFiles.any((f) => f.name == backup.fileName);

    if (alreadyUploaded) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '该备份已存在于云端', icon: Icons.info_outline, iconColor: AppTheme.primaryColor);
      }
      return;
    }

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在上传...', icon: Icons.cloud_upload, iconColor: AppTheme.primaryColor);
    }

    final success = await service.uploadGameBackup(
      serverUrl: url, username: username, password: password,
      gameFolder: gameTitle, localFilePath: backup.filePath,
    );

    if (mounted) {
      if (success) {
        AppTheme.showGlassToast(context, message: '上传成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
      } else {
        AppTheme.showGlassToast(context, message: '上传失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 还原到指定备份
  Future<void> _restoreBackup(BackupEntry backup) async {
    if (_savePath == null || _savePath!.isEmpty) {
      AppTheme.showGlassToast(context, message: '请先设置存档路径', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      return;
    }

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确认还原', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(
              '将还原备份 "${backup.name}" 到存档目录。\n\n当前存档会先自动备份为"还原前备份"。\n\n目标路径: $_savePath',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningColor, foregroundColor: Colors.white),
                  child: const Text('确认还原'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在还原...', icon: Icons.hourglass_empty, iconColor: AppTheme.primaryColor);
    }

    final service = ref.read(backupServiceProvider);
    bool success;

    // 根据备份来源选择不同的还原策略
    if (backup.source == BackupSource.imported) {
      success = await service.restoreCustomBackup(
        gamePath: widget.game.path,
        backupFilePath: backup.filePath,
        savePath: _savePath!,
      );
    } else {
      success = await service.restoreBackup(
        gamePath: widget.game.path,
        backupFilePath: backup.filePath,
        savePath: _savePath!,
      );
    }

    if (mounted) {
      if (success) {
        AppTheme.showGlassToast(context, message: '还原成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        _loadBackups();
      } else {
        AppTheme.showGlassToast(context, message: '还原失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 删除单个备份
  Future<void> _deleteBackup(BackupEntry backup) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('删除备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text('确定要删除备份 "${backup.name}" 吗？\n此操作不可撤销。', style: const TextStyle(color: AppTheme.textSecondary)),
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

    if (confirmed == true) {
      final service = ref.read(backupServiceProvider);
      await service.deleteBackup(backup.filePath);
      if (mounted) {
        AppTheme.showGlassToast(context, message: '已删除', icon: Icons.check_circle, iconColor: AppTheme.successColor);
        _loadBackups();
      }
    }
  }
}
