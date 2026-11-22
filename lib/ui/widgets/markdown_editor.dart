import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/utils/media_reference_parser.dart';
import '../theme/app_theme.dart';

class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final List<String> imagePaths;
  final double fontSize;

  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.imagePaths,
    this.fontSize = GlassConstants.fontControl,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  bool _isPreview = false;
  final _editorFocus = FocusNode();
  final _editorScroll = ScrollController();
  final _previewScroll = ScrollController();
  TextSelection? _editingSelection;

  void _switchMode(bool preview) {
    if (preview == _isPreview) return;
    final from = preview ? _editorScroll : _previewScroll;
    final to = preview ? _previewScroll : _editorScroll;
    final ratio = from.hasClients && from.position.maxScrollExtent > 0
        ? (from.offset / from.position.maxScrollExtent).clamp(0.0, 1.0)
        : 0.0;
    if (preview) _editingSelection = widget.controller.selection;
    setState(() => _isPreview = preview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isPreview != preview) return;
      if (!preview) {
        _editorFocus.requestFocus();
        final selection = _editingSelection;
        if (selection != null &&
            selection.isValid &&
            selection.end <= widget.controller.text.length) {
          widget.controller.selection = selection;
        }
      }
      if (to.hasClients) to.jumpTo(to.position.maxScrollExtent * ratio);
    });
  }

  @override
  void dispose() {
    _editorFocus.dispose();
    _editorScroll.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  String _toPreview(String text) {
    var result = MediaReferenceParser.replaceImageLines(text, (imagePath) {
      var imgPath = imagePath.trim();
      // 如果已经是 file:// 或 http:// 开头，直接使用
      if (imgPath.startsWith('file://') ||
          imgPath.startsWith('http://') ||
          imgPath.startsWith('https://')) {
        return '![]($imgPath)';
      }
      // Windows 路径：含 : 的路径（如 F:/xxx 或 F:\xxx）
      if (RegExp(r'^[A-Za-z]:').hasMatch(imgPath)) {
        imgPath = Uri.file(imgPath, windows: true).toString();
      }
      return '![]($imgPath)';
    });

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
    ctrl.value = TextEditingValue(
        text: text.replaceRange(start, end, replacement),
        selection: TextSelection(
            baseOffset: start + prefix.length,
            extentOffset: start + prefix.length + selected.length));
    _editorFocus.requestFocus();
  }

  void _insertImage(String path) {
    _insert('[图片:$path]');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
      ),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Offstage(
                  offstage: _isPreview,
                  child: ExcludeFocus(
                      excluding: _isPreview, child: _buildEditor())),
              if (_isPreview) AppEntrance(child: _buildPreview()),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: GlassConstants.spacingSmall,
          vertical: GlassConstants.spacingTiny),
      decoration: BoxDecoration(
        color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GlassConstants.radiusSmall)),
      ),
      child: Row(
        children: [
          _toggleButton(
            icon: Icons.edit,
            label: '编辑',
            active: !_isPreview,
            onTap: () => _switchMode(false),
          ),
          _toggleButton(
            icon: Icons.preview,
            label: '预览',
            active: _isPreview,
            onTap: () => _switchMode(true),
          ),
          const SizedBox(width: GlassConstants.spacingSmall),
          Container(
              width: 1,
              height: 20,
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.3)),
          const SizedBox(width: GlassConstants.spacingSmall),
          _formatButton(
              Icons.format_bold, '粗体', () => _insert('**', suffix: '**')),
          _formatButton(
              Icons.format_italic, '斜体', () => _insert('*', suffix: '*')),
          _formatButton(Icons.title, '标题', () => _insert('### ')),
          _formatButton(Icons.format_list_bulleted, '列表', () => _insert('- ')),
          const Spacer(),
          if (widget.imagePaths.isNotEmpty) _imagePickerButton(),
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
    return AppActionSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassConstants.radiusCompact),
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.fast),
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(
            horizontal: GlassConstants.spacingInline,
            vertical: GlassConstants.spacingTight),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(GlassConstants.radiusCompact),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: GlassConstants.iconSmall,
                color: active
                    ? AppTheme.getPrimaryColor(context)
                    : AppTheme.getTextSecondary(context)),
            const SizedBox(width: GlassConstants.spacingTiny),
            Text(
              label,
              style: TextStyle(
                fontSize: GlassConstants.fontSmall,
                color: active
                    ? AppTheme.getPrimaryColor(context)
                    : AppTheme.getTextSecondary(context),
                fontWeight:
                    active ? AppTypography.semibold : AppTypography.regular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: AppActionSurface(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GlassConstants.radiusTight),
        child: Padding(
          padding: const EdgeInsets.all(GlassConstants.spacingTight),
          child: Icon(icon,
              size: GlassConstants.iconAction,
              color: AppTheme.getTextSecondary(context)),
        ),
      ),
    );
  }

  Widget _imagePickerButton() {
    return PopupMenuButton<String>(
      popUpAnimationStyle: AppMotion.overlayStyle(context),
      tooltip: '插入图片',
      onCanceled: () => _editorFocus.requestFocus(),
      onSelected: _insertImage,
      itemBuilder: (_) => widget.imagePaths.map((p) {
        final name = p.split(RegExp(r'[/\\]')).last;
        return PopupMenuItem(
            value: p,
            child: Text(name,
                style: const TextStyle(fontSize: GlassConstants.fontBody)));
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: GlassConstants.spacingSmall,
            vertical: GlassConstants.spacingTiny),
        decoration: BoxDecoration(
          color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(GlassConstants.radiusCompact),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate,
                size: GlassConstants.iconSmall,
                color: AppTheme.getPrimaryColor(context)),
            const SizedBox(width: GlassConstants.spacingTiny),
            Text('图片',
                style: TextStyle(
                    fontSize: GlassConstants.fontSmall,
                    color: AppTheme.getPrimaryColor(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return TextField(
      contextMenuBuilder: buildAppEditableTextContextMenu,
      focusNode: _editorFocus,
      scrollController: _editorScroll,
      controller: widget.controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
          fontSize: widget.fontSize,
          height: AppTypography.readingHeight,
          color: AppTheme.getTextPrimary(context)),
      decoration: InputDecoration(
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(GlassConstants.spacingMedium),
        hintText: '支持 Markdown 语法...',
        hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
      ),
    );
  }

  Widget _buildPreview() {
    final preview = _toPreview(widget.controller.text);
    if (preview.isEmpty) {
      return Center(
        child: Text('暂无内容',
            style: TextStyle(color: AppTheme.getTextSecondary(context))),
      );
    }
    return SingleChildScrollView(
      controller: _previewScroll,
      padding: const EdgeInsets.all(GlassConstants.spacingMedium),
      child: MarkdownBody(
        data: preview,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: TextStyle(
              fontSize: widget.fontSize,
              height: AppTypography.readingHeight,
              color: AppTheme.getTextPrimary(context)),
          h1: TextStyle(
              fontSize: GlassConstants.fontHeadline,
              fontWeight: AppTypography.bold,
              color: AppTheme.getTextPrimary(context)),
          h2: TextStyle(
              fontSize: GlassConstants.fontMarkdownTitle,
              fontWeight: AppTypography.bold,
              color: AppTheme.getTextPrimary(context)),
          h3: TextStyle(
              fontSize: GlassConstants.fontSubtitle,
              fontWeight: AppTypography.semibold,
              color: AppTheme.getTextPrimary(context)),
          listBullet: TextStyle(
              fontSize: widget.fontSize,
              color: AppTheme.getTextPrimary(context)),
        ),
        imageBuilder: (uri, title, alt) {
          final uriStr = uri.toString();
          debugPrint('[MarkdownPreview] Loading image: $uriStr');

          try {
            if (uriStr.startsWith('file:///')) {
              final parsedUri = Uri.parse(uriStr);
              final filePath = parsedUri.toFilePath();
              final file = File(filePath);
              if (file.existsSync()) {
                return Image.file(file,
                    fit: BoxFit.contain, frameBuilder: appImageFrameBuilder);
              }
              debugPrint('[MarkdownPreview] File not found: $filePath');
            } else if (uriStr.startsWith('http://') ||
                uriStr.startsWith('https://')) {
              return Image.network(uriStr,
                  fit: BoxFit.contain, frameBuilder: appImageFrameBuilder);
            } else {
              final file = File(uriStr);
              if (file.existsSync()) {
                return Image.file(file,
                    fit: BoxFit.contain, frameBuilder: appImageFrameBuilder);
              }
            }
          } catch (e) {
            debugPrint('[MarkdownPreview] Image load error: $e');
          }

          return Container(
            padding: const EdgeInsets.symmetric(
                vertical: GlassConstants.spacingTiny),
            child: Text('[图片加载失败]',
                style: TextStyle(
                    fontSize: GlassConstants.fontSmall,
                    color: AppTheme.errorColor.withValues(alpha: 0.7))),
          );
        },
      ),
    );
  }
}
