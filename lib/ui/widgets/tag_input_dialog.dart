import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';

/// 连续录入标签，并从已有标签中搜索选择；确认后统一返回。
class TagInputDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final List<Tag> selectedTags;
  final List<Tag> availableTags;
  final bool showAvailable;
  final String newTagType;

  const TagInputDialog({
    super.key,
    this.title = '添加标签',
    this.hintText = '输入后回车添加，可用逗号分隔多个标签',
    required this.selectedTags,
    required this.availableTags,
    this.showAvailable = true,
    this.newTagType = Tag.typeCustom,
  });

  @override
  State<TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<TagInputDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final List<Tag> _selected = List.of(widget.selectedTags);

  bool _contains(Tag tag) => _selected.any((item) =>
      item.type == tag.type &&
      item.name.toLowerCase() == tag.name.toLowerCase());

  void _addInput() {
    for (final value in _controller.text.split(RegExp(r'[,，、;；\r\n]+'))) {
      final name = value.trim();
      if (name.isEmpty) continue;
      final existing = widget.availableTags
          .where((tag) =>
              tag.name.toLowerCase() == name.toLowerCase() ||
              tag.displayName?.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      final tag = existing ?? Tag(name: name, type: widget.newTagType);
      if (!_contains(tag)) _selected.add(tag);
    }
    _controller.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final candidates = !widget.showAvailable
        ? const <Tag>[]
        : widget.availableTags
            .where((tag) =>
                !_contains(tag) &&
                (query.isEmpty ||
                    tag.name.toLowerCase().contains(query) ||
                    (tag.displayName ?? '').toLowerCase().contains(query)))
            .toList();
    return SizedBox(
      width: GlassConstants.dialogWidth,
      child: Padding(
        padding: const EdgeInsets.all(GlassConstants.spacingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: TextStyle(
                    fontSize: GlassConstants.fontSection,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context))),
            const SizedBox(height: GlassConstants.spacingCompact),
            Flexible(
                child: SingleChildScrollView(
                    child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selected.isNotEmpty) ...[
                  Text('已选标签（${_selected.length}）',
                      style:
                          TextStyle(color: AppTheme.getTextSecondary(context))),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selected
                          .map((tag) => InputChip(
                                label: Text(tag.displayName ?? tag.name),
                                onDeleted: () =>
                                    setState(() => _selected.remove(tag)),
                              ))
                          .toList()),
                  const SizedBox(height: GlassConstants.spacingCompact),
                ],
                TextField(
                  key: const ValueKey('tag-input'),
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _addInput(),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    suffixIcon: IconButton(
                        tooltip: '添加标签',
                        icon: const Icon(Icons.add),
                        onPressed: _addInput),
                  ),
                ),
                if (widget.showAvailable) ...[
                  const SizedBox(height: GlassConstants.spacingCompact),
                  Text('已有标签',
                      style:
                          TextStyle(color: AppTheme.getTextSecondary(context))),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  if (candidates.isEmpty)
                    Text('暂无匹配的标签',
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context)))
                  else
                    Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: candidates
                            .map((tag) => ActionChip(
                                  label: Text(tag.displayName ?? tag.name),
                                  onPressed: () {
                                    setState(() {
                                      _selected.add(tag);
                                      _controller.clear();
                                    });
                                    _focusNode.requestFocus();
                                  },
                                ))
                            .toList()),
                ],
              ],
            ))),
            const SizedBox(height: GlassConstants.spacingComfortable),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              const SizedBox(width: GlassConstants.spacingSmall),
              ElevatedButton(
                  onPressed: () {
                    _addInput();
                    Navigator.pop(context, List<Tag>.of(_selected));
                  },
                  child: const Text('完成')),
            ]),
          ],
        ),
      ),
    );
  }
}
