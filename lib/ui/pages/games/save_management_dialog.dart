// lib/ui/pages/games/save_management_dialog.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/models/models.dart';
import '../../../core/models/backup_entry.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/fan2d_service.dart';
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
  bool _isBatchDeleteMode = false;
  final Set<String> _selectedForDelete = {};
  bool _isEditingPath = false;
  bool _isDownloading = false;
  late TextEditingController _pathEditController;

  @override
  void initState() {
    super.initState();
    _savePath = widget.game.savePath;
    _pathEditController = TextEditingController(text: _savePath ?? '');
    _loadBackups();
    _autoImportSaveFolder();
  }

  @override
  void dispose() {
    _pathEditController.dispose();
    super.dispose();
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 950, maxHeight: 700),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.getSurfaceColor(context),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusXLarge),
                  border: Border.all(color: AppTheme.getBorderColor(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.15),
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
                    Divider(height: 1, color: AppTheme.getBorderColor(context)),
                    Expanded(child: _buildBackupList()),
                  ],
                ),
              ),
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
          Icon(Icons.folder_special, color: AppTheme.getPrimaryColor(context), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '存档管理 - ${widget.game.title ?? "未知游戏"}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            color: AppTheme.getTextSecondary(context),
            onPressed: _loadBackups,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppTheme.getTextSecondary(context),
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
          Icon(Icons.folder_open, size: 16, color: AppTheme.getTextSecondary(context)),
          const SizedBox(width: 8),
          if (_isEditingPath) ...[
            Expanded(
              child: TextField(
                controller: _pathEditController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (_) => _savePathEdit(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: _selectSaveFolder,
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('选择', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  side: BorderSide(color: AppTheme.successColor.withValues(alpha: 0.3)),
                  foregroundColor: AppTheme.successColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: _savePathEdit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('保存', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 32,
              child: TextButton(
                onPressed: () => setState(() => _isEditingPath = false),
                child: const Text('取消', style: TextStyle(fontSize: 12)),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                _savePath ?? '未设置存档路径',
                style: TextStyle(
                  fontSize: 13,
                  color: _savePath != null ? AppTheme.getTextSecondary(context) : AppTheme.warningColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: _selectSaveFolder,
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('选择路径', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: AppTheme.successColor.withValues(alpha: 0.3)),
                  foregroundColor: AppTheme.successColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () {
                  _pathEditController.text = _savePath ?? '';
                  setState(() => _isEditingPath = true);
                },
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('编辑', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isBatchDeleteMode) ...[
              _buildActionButton(Icons.folder_open, '打开存档', AppTheme.primaryColor, _openSaveFolder),
              const SizedBox(width: 10),
              _buildActionButton(Icons.backup, '打开备份', AppTheme.secondaryColor, _openBackupFolder),
              const SizedBox(width: 10),
              _buildActionButton(Icons.add_circle_outline, '导入存档', AppTheme.warningColor, _addCustomBackup),
              const SizedBox(width: 10),
              _buildActionButton(Icons.cloud_download_outlined, '下载存档', AppTheme.primaryColor, _downloadFrom2dfan),
              const SizedBox(width: 10),
              _buildActionButton(Icons.save_alt, '备份存档', AppTheme.successColor, _backupCurrentSave),
              const SizedBox(width: 10),
              _buildActionButton(Icons.cloud_outlined, '云端备份', AppTheme.primaryColor, _showCloudBackups),
              const SizedBox(width: 10),
              _buildActionButton(Icons.delete_sweep_outlined, '批量删除', AppTheme.errorColor, _toggleBatchDeleteMode),
            ],
            if (_isBatchDeleteMode) ...[
              _buildActionButton(Icons.cancel_outlined, '取消', AppTheme.getTextSecondary(context), _toggleBatchDeleteMode),
              const SizedBox(width: 10),
              _buildActionButton(Icons.delete_forever, '删除 ${_selectedForDelete.length} 项', AppTheme.errorColor, _confirmBatchDelete),
            ],
          ],
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
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
      return Center(
        child: Text('暂无备份', style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 14)),
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
    if (_isBatchDeleteMode) {
      final isSelected = _selectedForDelete.contains(backup.filePath);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedForDelete.add(backup.filePath);
                  } else {
                    _selectedForDelete.remove(backup.filePath);
                  }
                });
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(backup.name, style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)), overflow: TextOverflow.ellipsis),
            ),
            Text(backup.sizeFormatted, style: TextStyle(fontSize: 13, color: AppTheme.getTextSecondary(context))),
          ],
        ),
      );
    }

    final isImported = backup.source == BackupSource.imported;
    final isPreRestore = backup.source == BackupSource.preRestore;

    // 背景色：还原前备份=黄色，导入备份=蓝色，手动备份=默认
    final bgColor = isPreRestore
        ? AppTheme.warningColor.withValues(alpha: 0.08)
        : isImported
            ? AppTheme.primaryColor.withValues(alpha: 0.08)
            : AppTheme.getBackgroundColor(context).withValues(alpha: 0.5);
    final borderColor = isPreRestore
        ? AppTheme.warningColor.withValues(alpha: 0.3)
        : isImported
            ? AppTheme.primaryColor.withValues(alpha: 0.3)
            : AppTheme.getBorderColor(context).withValues(alpha: 0.5);
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
            color: accentColor ?? AppTheme.getTextSecondary(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              backup.name,
              style: TextStyle(
                fontSize: 14,
                color: accentColor ?? AppTheme.getTextPrimary(context),
                fontWeight: (isImported || isPreRestore) ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            backup.sizeFormatted,
            style: TextStyle(fontSize: 13, color: AppTheme.getTextSecondary(context)),
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

  /// 打开存档文件夹
  Future<void> _openSaveFolder() async {
    if (_savePath == null || _savePath!.isEmpty) {
      AppTheme.showGlassToast(context, message: '请先设置存档路径', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      return;
    }
    try {
      await Process.run('explorer.exe', [_savePath!]);
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
      await Process.run('explorer.exe', [backupDir.path]);
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '无法打开路径: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  /// 添加自定义备份（支持 zip 文件和文件夹）
  Future<void> _addCustomBackup() async {
    // 先让用户选择导入方式
     final importType = await showGlassDialog<String>(
      context: context,
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('添加自定义备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
              const SizedBox(height: 16),
              Text('请选择要导入的类型：', style: TextStyle(color: AppTheme.getTextSecondary(context))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'cancel'),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'zip'),
                    icon: const Icon(Icons.archive, size: 16),
                    label: const Text('选择 zip 文件'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, 'folder'),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('选择文件夹'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (importType == null || importType == 'cancel') return;

    String? selectedPath;
    if (importType == 'zip') {
      final result = await FilePicker.pickFiles(
        dialogTitle: '选择存档导入',
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result != null && result.files.single.path != null) {
        selectedPath = result.files.single.path!;
      }
    } else {
      selectedPath = await FilePicker.getDirectoryPath(dialogTitle: '选择存档文件夹');
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

  Future<void> _downloadFrom2dfan() async {
    if (_isDownloading) return;
    final gameTitle = widget.game.title ?? '';
    final launcher = widget.game.gameLauncher ?? '';
    if (gameTitle.isEmpty && launcher.isEmpty) {
      AppTheme.showGlassToast(context, message: '游戏标题和启动器均为空，无法搜索', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final fan2dService = ref.read(fan2dServiceProvider);
      AppTheme.showGlassToast(context, message: '正在尝试搜索存档', icon: Icons.search, iconColor: AppTheme.primaryColor);
      final results = await fan2dService.searchWithFallback(
        gamePath: widget.game.path,
        gameLauncher: widget.game.gameLauncher,
        gameTitle: gameTitle,
      );

      if (results.isEmpty) {
        if (mounted) AppTheme.showGlassToast(context, message: '未找到相关存档', icon: Icons.search_off, iconColor: AppTheme.warningColor);
        return;
      }
      if (!mounted) return;

      final selected = await _showSearchResultsDialog(results);
      if (selected == null) return;
      if (!mounted) return;

      AppTheme.showGlassToast(context, message: '正在下载存档...', icon: Icons.downloading, iconColor: AppTheme.primaryColor);
      final result = await fan2dService.downloadAndImport(
        downloadPageUrl: selected.downloadUrl,
        gamePath: widget.game.path,
      );

      // kind 页面：让用户选择具体存档
      if (result.hasSaveFiles) {
        if (!mounted) return;
        final picked = await _showSaveFilesDialog(result.saveFiles);
        if (picked == null) return;
        if (!mounted) return;

        AppTheme.showGlassToast(context, message: '正在下载存档...', icon: Icons.downloading, iconColor: AppTheme.primaryColor);
        final entry = await fan2dService.downloadSaveFile(
          saveFileUrl: picked.downloadUrl,
          gamePath: widget.game.path,
        );
        if (mounted) {
          if (entry != null) {
            AppTheme.showGlassToast(context, message: '下载成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
            _loadBackups();
          } else {
            AppTheme.showGlassToast(context, message: '下载失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
          }
        }
        return;
      }

      if (mounted) {
        if (result.hasEntry) {
          AppTheme.showGlassToast(context, message: '下载成功', icon: Icons.check_circle, iconColor: AppTheme.successColor);
          _loadBackups();
        } else {
          AppTheme.showGlassToast(context, message: '下载失败，请检查网络或域名设置', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
      }
    } catch (e) {
      if (mounted) AppTheme.showGlassToast(context, message: '下载异常: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<Fan2dSearchResult?> _showSearchResultsDialog(List<Fan2dSearchResult> results) async {
    return showGlassDialog<Fan2dSearchResult>(
      context: context,
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        height: 500,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_download_outlined, color: AppTheme.primaryColor, size: 22),
                  const SizedBox(width: 10),
                  Text('选择要下载的存档', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ],
              ),
              const SizedBox(height: 8),
              Text('找到 ${results.length} 个结果，请选择：', style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 13)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                          onTap: () => Navigator.pop(context, result),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                              border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.archive_outlined, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 12),
                                Expanded(child: Text(result.title, style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)), overflow: TextOverflow.ellipsis)),
                                Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.getTextSecondary(context)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示 kind 页面的具体存档列表，让用户选择
  Future<Fan2dSaveFile?> _showSaveFilesDialog(List<Fan2dSaveFile> saveFiles) async {
    return showGlassDialog<Fan2dSaveFile>(
      context: context,
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        height: 500,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_open, color: AppTheme.primaryColor, size: 22),
                  const SizedBox(width: 10),
                  Text('选择存档', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ],
              ),
              const SizedBox(height: 8),
              Text('找到 ${saveFiles.length} 个存档，请选择：', style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 13)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: saveFiles.length,
                  itemBuilder: (context, index) {
                    final sf = saveFiles[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                          onTap: () => Navigator.pop(context, sf),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                              border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.save_alt, size: 18, color: AppTheme.successColor),
                                const SizedBox(width: 12),
                                Expanded(child: Text(sf.title, style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)), overflow: TextOverflow.ellipsis)),
                                Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.getTextSecondary(context)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 进入/退出批量删除模式
  void _toggleBatchDeleteMode() {
    setState(() {
      if (_isBatchDeleteMode) {
        _isBatchDeleteMode = false;
        _selectedForDelete.clear();
      } else {
        _isBatchDeleteMode = true;
      }
    });
  }

  /// 确认批量删除
  Future<void> _confirmBatchDelete() async {
    if (_selectedForDelete.isEmpty) return;

    final service = ref.read(backupServiceProvider);
    int count = 0;
    for (final path in _selectedForDelete) {
      if (await service.deleteBackup(path)) count++;
    }
    if (mounted) {
      setState(() {
        _isBatchDeleteMode = false;
        _selectedForDelete.clear();
      });
      AppTheme.showGlassToast(context, message: '已删除 $count 个备份', icon: Icons.check_circle, iconColor: AppTheme.successColor);
      _loadBackups();
    }
  }

  /// 保存内联编辑的路径
  Future<void> _savePathEdit() async {
    final newPath = _pathEditController.text.trim();
    final repo = ref.read(gameRepositoryProvider);
    await repo.updateSavePath(widget.game.id!, newPath.isEmpty ? null : newPath);
    if (mounted) {
      setState(() {
        _savePath = newPath.isEmpty ? null : newPath;
        _isEditingPath = false;
      });
      AppTheme.showGlassToast(context, message: '存档路径已更新');
    }
  }

  /// 通过文件夹选择器选择存档路径
  Future<void> _selectSaveFolder() async {
    final dirPath = await FilePicker.getDirectoryPath(dialogTitle: '选择存档文件夹');
    if (dirPath == null) return;

    final repo = ref.read(gameRepositoryProvider);
    await repo.updateSavePath(widget.game.id!, dirPath);
    if (mounted) {
      setState(() {
        _savePath = dirPath;
        _isEditingPath = false;
        _pathEditController.text = dirPath;
      });
      AppTheme.showGlassToast(context, message: '存档路径已更新');
    }
  }

  /// 重命名备份
  Future<void> _renameBackup(BackupEntry backup) async {
    final controller = TextEditingController(text: backup.name);

    final newName = await showGlassDialog<String>(
      context: context,
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑备份名称', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
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
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确认还原', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
              const SizedBox(height: 12),
              Text(
                '将还原备份 "${backup.name}" 到存档目录。\n\n当前存档会先自动备份为"还原前备份"。\n\n目标路径: $_savePath',
                style: TextStyle(color: AppTheme.getTextSecondary(context)),
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
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('删除备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
              const SizedBox(height: 12),
              Text('确定要删除备份 "${backup.name}" 吗？\n此操作不可撤销。', style: TextStyle(color: AppTheme.getTextSecondary(context))),
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

class _DismissDialogIntent extends Intent {
  const _DismissDialogIntent();
}
