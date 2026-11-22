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
  String? _duplicate;
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
      if (_contains(tag)) {
        _duplicate = '已添加「${tag.displayName ?? tag.name}」';
      } else {
        _selected.add(tag);
        _duplicate = null;
      }
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
    final controlHeight = LayoutConstants.controlHeight +
        MediaQuery.textScalerOf(context).scale(GlassConstants.fontControl) -
        GlassConstants.fontControl;
    final labelStyle = TextStyle(
        fontSize: GlassConstants.fontControl,
        color: AppTheme.getTextPrimary(context));
    const chipPadding =
        EdgeInsets.symmetric(horizontal: GlassConstants.spacingTiny);
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
            Text(widget.title, style: AppTypography.dialogTitle(context)),
            const SizedBox(height: GlassConstants.spacingCompact),
            Flexible(
                child: SingleChildScrollView(
                    child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selected.isNotEmpty) ...[
                  Text('已选标签（${_selected.length}）',
                      style: TextStyle(
                          fontSize: GlassConstants.fontBody,
                          color: AppTheme.getTextSecondary(context))),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  Wrap(
                      spacing: GlassConstants.spacingTight,
                      runSpacing: GlassConstants.spacingTight,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _selected
                          .map((tag) => AppEntrance(
                              key: ObjectKey(tag),
                              child: InputChip(
                                label: Text(tag.displayName ?? tag.name,
                                    style: labelStyle),
                                padding: chipPadding,
                                labelPadding: const EdgeInsets.symmetric(
                                    horizontal: GlassConstants.spacingTiny),
                                deleteIcon: const Icon(Icons.close,
                                    size: GlassConstants.iconAction),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.standard,
                                onDeleted: () =>
                                    setState(() => _selected.remove(tag)),
                              )))
                          .toList()),
                  const SizedBox(height: GlassConstants.spacingCompact),
                ],
                SizedBox(
                  height: controlHeight,
                  child: TextField(
                    key: const ValueKey('tag-input'),
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    style: labelStyle,
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: (_) => setState(() => _duplicate = null),
                    onSubmitted: (_) => _addInput(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: GlassConstants.spacingCompact),
                      labelStyle: labelStyle,
                      hintStyle: TextStyle(
                          fontSize: GlassConstants.fontControl,
                          color: AppTheme.getTextSecondary(context)),
                      labelText:
                          widget.newTagType == Tag.typeSeries ? '系列名称' : '标签名称',
                      hintText: widget.hintText,
                      helperText: _duplicate,
                      suffixIconConstraints: BoxConstraints.tightFor(
                          width: controlHeight, height: controlHeight),
                      suffixIcon: IconButton(
                          key: const ValueKey('tag-add-input'),
                          tooltip: '添加标签',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.add,
                              size: GlassConstants.iconAction),
                          onPressed: _addInput),
                    ),
                  ),
                ),
                if (widget.showAvailable) ...[
                  const SizedBox(height: GlassConstants.spacingCompact),
                  Text('已有标签',
                      style: TextStyle(
                          fontSize: GlassConstants.fontBody,
                          color: AppTheme.getTextSecondary(context))),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  if (candidates.isEmpty)
                    Text('暂无匹配的标签',
                        style: TextStyle(
                            fontSize: GlassConstants.fontBody,
                            color: AppTheme.getTextSecondary(context)))
                  else
                    Wrap(
                        spacing: GlassConstants.spacingTight,
                        runSpacing: GlassConstants.spacingTight,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: candidates
                            .map((tag) => ActionChip(
                                  label: Text(tag.displayName ?? tag.name,
                                      style: labelStyle),
                                  padding: chipPadding,
                                  labelPadding: const EdgeInsets.symmetric(
                                      horizontal: GlassConstants.spacingTiny),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.standard,
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
                  key: const ValueKey('tag-cancel'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              const SizedBox(width: GlassConstants.spacingSmall),
              ElevatedButton(
                  key: const ValueKey('tag-complete'),
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
