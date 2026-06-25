import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/models/tool.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  @override
  Widget build(BuildContext context) {
    final toolsAsync = ref.watch(allToolsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          Expanded(
            child: toolsAsync.when(
              data: (tools) {
                if (tools.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildToolGrid(tools);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.build, color: AppTheme.getPrimaryColor(context), size: 28),
        const SizedBox(width: 12),
        Text(
          '工具',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _importTool,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('导入工具'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.getPrimaryColor(context),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.build_circle_outlined, size: 64, color: AppTheme.getTextPrimary(context).withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            '还没有工具',
            style: TextStyle(fontSize: 16, color: AppTheme.getTextPrimary(context).withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角"导入工具"添加文件',
            style: TextStyle(fontSize: 13, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildToolGrid(List<Tool> tools) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return _buildToolCard(tool);
      },
    );
  }

  Widget _buildToolCard(Tool tool) {
    final fileName = tool.path.split(RegExp(r'[/\\]')).last;
    final ext = fileName.contains('.') ? '.${fileName.split('.').last.toLowerCase()}' : '';
    final iconData = _getFileIcon(ext);
    final iconColor = _getFileIconColor(ext);

    return GestureDetector(
      onDoubleTap: () => _launchTool(tool),
      onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition, tool),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          child: InkWell(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            onDoubleTap: () => _launchTool(tool),
            onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition, tool),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: Icon(iconData, size: 80, color: iconColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tool.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.getTextPrimary(context),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importTool() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择工具文件',
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    final existingTool = await ref.read(toolRepositoryProvider).getToolByPath(file.path!);
    if (existingTool != null) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '该工具已存在', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return;
    }

    final tool = Tool(name: file.name, path: file.path!);
    await ref.read(toolRepositoryProvider).insertTool(tool);
    ref.invalidate(allToolsProvider);
  }

  Future<void> _launchTool(Tool tool) async {
    try {
      await Process.run(tool.path, [], workingDirectory: Directory(tool.path).parent.path);
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  void _showContextMenu(Offset position, Tool tool) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.play_arrow, size: 18),
              SizedBox(width: 8),
              Text('启动该工具'),
            ],
          ),
          onTap: () => _launchTool(tool),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 8),
              Text('编辑工具名'),
            ],
          ),
          onTap: () => _editToolName(tool),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_open, size: 18),
              SizedBox(width: 8),
              Text('修改工具路径'),
            ],
          ),
          onTap: () => _changeToolPath(tool),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
          onTap: () => _deleteTool(tool),
        ),
      ],
    );
  }

  Future<void> _editToolName(Tool tool) async {
    final controller = TextEditingController(text: tool.name);
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
              Text('编辑工具名', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: '输入工具名称'),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
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

    if (newName != null && newName.isNotEmpty && newName != tool.name) {
      await ref.read(toolRepositoryProvider).updateTool(tool.copyWith(name: newName));
      ref.invalidate(allToolsProvider);
    }
  }

  Future<void> _changeToolPath(Tool tool) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择新的工具文件',
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;

    final newPath = result.files.first.path!;
    final newName = result.files.first.name;
    await ref.read(toolRepositoryProvider).updateTool(tool.copyWith(path: newPath, name: newName));
    ref.invalidate(allToolsProvider);
  }

  Future<void> _deleteTool(Tool tool) async {
    await ref.read(toolRepositoryProvider).deleteTool(tool.id!);
    ref.invalidate(allToolsProvider);
    if (mounted) {
      AppTheme.showGlassToast(context, message: '已删除工具: ${tool.name}');
    }
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case '.exe':
        return Icons.apps;
      case '.bat':
      case '.cmd':
      case '.ps1':
        return Icons.terminal;
      case '.lnk':
        return Icons.link;
      case '.txt':
      case '.log':
        return Icons.description;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.article;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return Icons.archive;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return Icons.image;
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        return Icons.music_note;
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
        return Icons.movie;
      case '.html':
      case '.htm':
        return Icons.language;
      case '.json':
      case '.xml':
      case '.yaml':
      case '.yml':
        return Icons.data_object;
      case '.dll':
      case '.sys':
        return Icons.settings;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String ext) {
    switch (ext) {
      case '.exe':
        return const Color(0xFF4CAF50);
      case '.bat':
      case '.cmd':
      case '.ps1':
        return const Color(0xFF2196F3);
      case '.lnk':
        return const Color(0xFF9C27B0);
      case '.txt':
      case '.log':
        return const Color(0xFF607D8B);
      case '.pdf':
        return const Color(0xFFF44336);
      case '.doc':
      case '.docx':
        return const Color(0xFF1976D2);
      case '.xls':
      case '.xlsx':
        return const Color(0xFF388E3C);
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return const Color(0xFFFF9800);
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return const Color(0xFF00BCD4);
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        return const Color(0xFFE91E63);
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
        return const Color(0xFF9C27B0);
      default:
        return AppTheme.textSecondary.withValues(alpha: 0.6);
    }
  }
}
