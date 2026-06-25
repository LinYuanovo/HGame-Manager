import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';

class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final List<String> imagePaths;
  final double fontSize;

  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.imagePaths,
    this.fontSize = 14,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  bool _isPreview = false;

  String _toPreview(String text) {
    var result = text.replaceAllMapped(
      RegExp(r'\[图片:([^\]]+)\]'),
      (m) {
        var imgPath = m[1]!.trim();
        // 如果已经是 file:// 或 http:// 开头，直接使用
        if (imgPath.startsWith('file://') || imgPath.startsWith('http://') || imgPath.startsWith('https://')) {
          return '![]($imgPath)';
        }
        // Windows 路径：含 : 的路径（如 F:/xxx 或 F:\xxx）
        if (RegExp(r'^[A-Za-z]:').hasMatch(imgPath)) {
          imgPath = 'file:///${imgPath.replaceAll('\\', '/')}';
        }
        return '![]($imgPath)';
      },
    );

    // 处理换行：单个 \n 转换为两个空格 + \n（Markdown 强制换行）
    result = result.replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), '  \n');

    return result;
  }

  void _insert(String prefix, {String suffix = ''}) {
    final ctrl = widget.controller;
    final sel = ctrl.selection;
    final text = ctrl.text;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final selected = text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    ctrl.text = text.substring(0, start) + replacement + text.substring(end);
    ctrl.selection = TextSelection.collapsed(offset: start + prefix.length + selected.length);
  }

  void _insertImage(String path) {
    _insert('[图片:$path]');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: _isPreview ? _buildPreview() : _buildEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          _toggleButton(
            icon: Icons.edit,
            label: '编辑',
            active: !_isPreview,
            onTap: () => setState(() => _isPreview = false),
          ),
          _toggleButton(
            icon: Icons.preview,
            label: '预览',
            active: _isPreview,
            onTap: () => setState(() => _isPreview = true),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(width: 8),
          _formatButton(Icons.format_bold, '粗体', () => _insert('**', suffix: '**')),
          _formatButton(Icons.format_italic, '斜体', () => _insert('*', suffix: '*')),
          _formatButton(Icons.title, '标题', () => _insert('### ')),
          _formatButton(Icons.format_list_bulleted, '列表', () => _insert('- ')),
          const Spacer(),
          if (widget.imagePaths.isNotEmpty)
            _imagePickerButton(),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? AppTheme.primaryColor : AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? AppTheme.primaryColor : AppTheme.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatButton( IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _imagePickerButton() {
    return PopupMenuButton<String>(
      tooltip: '插入图片',
      onSelected: _insertImage,
      itemBuilder: (_) => widget.imagePaths.map((p) {
        final name = p.split(RegExp(r'[/\\]')).last;
        return PopupMenuItem(value: p, child: Text(name, style: const TextStyle(fontSize: 13)));
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate, size: 16, color: AppTheme.primaryColor),
            SizedBox(width: 4),
            Text('图片', style: TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: widget.controller,
      maxLines: null,
      expands: true,
      style: TextStyle(fontSize: widget.fontSize, height: 1.7, color: AppTheme.textPrimary),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
        hintText: '支持 Markdown 语法...',
        hintStyle: TextStyle(color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildPreview() {
    final preview = _toPreview(widget.controller.text);
    if (preview.isEmpty) {
      return const Center(
        child: Text('暂无内容', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    return Markdown(
      data: preview,
      padding: const EdgeInsets.all(16),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(fontSize: widget.fontSize, height: 1.7, color: AppTheme.textPrimary),
        h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        h2: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        h3: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        listBullet: TextStyle(fontSize: widget.fontSize, color: AppTheme.textPrimary),
      ),
      imageBuilder: (uri, title, alt) {
        final uriStr = uri.toString();
        debugPrint('[MarkdownPreview] Loading image: $uriStr');
        
        try {
          if (uriStr.startsWith('file:///')) {
            // file:///F:/path -> F:/path
            final filePath = Uri.parse(uriStr).toFilePath();
            final file = File(filePath);
            if (file.existsSync()) {
              return Image.file(file, fit: BoxFit.contain);
            }
            debugPrint('[MarkdownPreview] File not found: $filePath');
          } else if (uriStr.startsWith('http://') || uriStr.startsWith('https://')) {
            return Image.network(uriStr, fit: BoxFit.contain);
          } else {
            // 尝试直接作为本地路径
            final file = File(uriStr);
            if (file.existsSync()) {
              return Image.file(file, fit: BoxFit.contain);
            }
          }
        } catch (e) {
          debugPrint('[MarkdownPreview] Image load error: $e');
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('[图片加载失败: ${uriStr.length > 50 ? '${uriStr.substring(0, 50)}...' : uriStr}]', 
            style: TextStyle(fontSize: 12, color: AppTheme.errorColor.withValues(alpha: 0.7))),
        );
      },
    );
  }
}
