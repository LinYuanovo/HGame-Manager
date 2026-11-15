import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;

import '../../../core/models/models.dart';
import '../../../core/models/scrape_review_item.dart';
import '../../../core/repositories/game_repository.dart';
import '../../../core/repositories/tag_repository.dart';
import '../../../core/services/scrape_review_service.dart';
import '../../../core/utils/proxy_client.dart';
import '../../theme/app_theme.dart';

Future<void> showScrapeReviewDialog({
  required BuildContext context,
  required List<ScrapeReviewItem> items,
  required ScrapeMode mode,
  required ScrapeModeConfigs configs,
  required GameRepository repository,
  required TagRepository tagRepository,
  VoidCallback? onChanged,
}) async {
  if (items.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppTheme.getDialogBarrierColor(context),
    builder: (context) => ScrapeReviewDialog(
      items: items,
      configs: configs,
      service: ScrapeReviewService(
        repository: repository,
        tagRepository: tagRepository,
      ),
      onChanged: onChanged,
    ),
  );
}

class ScrapeReviewDialog extends StatefulWidget {
  final List<ScrapeReviewItem> items;
  final ScrapeModeConfigs configs;
  final ScrapeReviewService service;
  final VoidCallback? onChanged;

  const ScrapeReviewDialog({
    super.key,
    required this.items,
    required this.configs,
    required this.service,
    this.onChanged,
  });

  @override
  State<ScrapeReviewDialog> createState() => _ScrapeReviewDialogState();
}

class _ScrapeReviewDialogState extends State<ScrapeReviewDialog> {
  final _selected = <ScrapeReviewItem>{};
  final _destination = TextEditingController();
  int _activeIndex = 0;
  bool _busy = false;
  bool _pickingFolder = false;
  bool _organize = true;
  String? _feedback;
  String? _progress;
  String? _destinationError;

  double get _controlHeight =>
      LayoutConstants.controlHeight +
      MediaQuery.textScalerOf(context).scale(GlassConstants.fontControl) -
      GlassConstants.fontControl;

  ButtonStyle get _buttonStyle => ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, _controlHeight)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: GlassConstants.spacingMedium)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: GlassConstants.fontControl)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
                Radius.circular(GlassConstants.radiusMedium)))),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      );

  ButtonStyle get _iconButtonStyle => IconButton.styleFrom(
        minimumSize: Size.square(_controlHeight),
        padding: EdgeInsets.zero,
        iconSize: GlassConstants.iconControl,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      );

  ScrapeReviewItem get _active => widget.items[_activeIndex];
  bool get _locked => _busy || _pickingFolder;
  int get _saveCount => widget.items
      .where((item) =>
          item.canKeep &&
          !item.applied &&
          !item.recoveryRequired &&
          item.decision == ScrapeReviewDecision.keep)
      .length;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  void _changed() {
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  void _decide(
      Iterable<ScrapeReviewItem> items, ScrapeReviewDecision decision) {
    if (_locked) return;
    for (final item in items) {
      if (item.applied || item.recoveryRequired) continue;
      if (decision == ScrapeReviewDecision.keep && !item.canKeep) continue;
      item.decision = decision;
      item.applyError = null;
    }
    _changed();
  }

  void _decideActive(ScrapeReviewDecision decision) {
    _decide([_active], decision);
    if (_activeIndex < widget.items.length - 1) {
      setState(() => _activeIndex++);
    }
  }

  Future<void> _save() async {
    final pending = widget.items
        .where((item) =>
            item.canKeep &&
            !item.applied &&
            !item.recoveryRequired &&
            item.decision == ScrapeReviewDecision.keep)
        .toList();
    if (pending.isEmpty || _locked) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    var saved = 0;
    var failed = 0;
    final configs =
        _organize ? widget.configs : const ScrapeModeConfigs(configs: {});
    try {
      for (final item in pending) {
        if (!mounted) break;
        setState(() {
          _activeIndex = widget.items.indexOf(item);
          _progress = '正在保存 ${saved + failed + 1}/${pending.length}';
        });
        try {
          await widget.service.apply(item, configs,
              onProgress: (current, total) {
            if (!mounted) return;
            setState(() => _progress =
                '正在保存 ${saved + failed + 1}/${pending.length} · 图片 $current/$total');
          });
          saved++;
        } catch (_) {
          failed++;
        }
        _changed();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _feedback =
              '已保存 $saved 项${failed > 0 ? '，$failed 项失败，可查看原因后重试' : ''}';
        });
      }
    }
  }

  Future<void> _pickDestination() async {
    setState(() => _pickingFolder = true);
    try {
      final destination = await FilePicker.getDirectoryPath(
        dialogTitle: '选择接收游戏子文件夹的目录',
      );
      if (destination != null && mounted) {
        _destination.text = destination;
        setState(() => _destinationError = null);
      }
    } catch (error) {
      if (mounted) setState(() => _feedback = '选择文件夹失败：$error');
    } finally {
      if (mounted) setState(() => _pickingFolder = false);
    }
  }

  Future<void> _move() async {
    if (_locked || _selected.isEmpty) return;
    final destination = _destination.text.trim();
    if (destination.isEmpty) {
      setState(() => _destinationError = '请填写或选择目标文件夹');
      return;
    }
    final selected = widget.items.where(_selected.contains).toList();
    setState(() {
      _busy = true;
      _feedback = null;
    });
    var moved = 0;
    var failed = 0;
    try {
      for (final item in selected) {
        if (!mounted) break;
        setState(() {
          _activeIndex = widget.items.indexOf(item);
          _progress = '正在移动 ${moved + failed + 1}/${selected.length}';
        });
        try {
          await widget.service.move(item, destination, onProgress: (progress) {
            if (!mounted) return;
            setState(() =>
                _progress = '正在移动 ${moved + failed + 1}/${selected.length} · '
                    '${(progress.fraction * 100).toStringAsFixed(0)}%');
          });
          _selected.remove(item);
          moved++;
        } catch (_) {
          failed++;
        }
        _changed();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _feedback =
              '已移动 $moved 项${failed > 0 ? '，$failed 项失败，原因显示在对应条目中' : ''}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOrganization = widget.items.any((item) =>
        widget.configs.shouldRename(item.mode) ||
        widget.configs.shouldMove(item.mode));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_locked) Navigator.of(context).pop();
        },
      },
      child: PopScope(
        canPop: !_locked,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(GlassConstants.spacingLarge),
          child: GlassContainer(
            width: LayoutConstants.reviewDialogWidth,
            height: LayoutConstants.reviewDialogHeight,
            color: AppTheme.getSurfaceColor(context),
            padding: const EdgeInsets.all(GlassConstants.spacingLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('确认刮削结果',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: GlassConstants.fontHeading,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                    IconButton(
                      style: _iconButtonStyle,
                      tooltip: '关闭，稍后继续确认',
                      onPressed: _locked ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text('逐项核对后标记保留或放弃，再保存已保留的结果。放弃将保留游戏原有资料。',
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontSize: GlassConstants.fontBody,
                    )),
                const SizedBox(height: GlassConstants.spacingSmall),
                _buildSelectionTools(),
                const SizedBox(height: GlassConstants.spacingSmall),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    if (constraints.maxWidth >=
                        LayoutConstants.reviewSplitWidth) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: LayoutConstants.detailInfoPanelWidth,
                            child: _buildList(),
                          ),
                          const SizedBox(width: GlassConstants.spacingMedium),
                          Expanded(child: _buildPreview()),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(child: _buildList()),
                        const SizedBox(height: GlassConstants.spacingSmall),
                        Expanded(flex: 2, child: _buildPreview()),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: GlassConstants.spacingSmall),
                if (_progress != null) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  Text(_progress!,
                      style: TextStyle(
                        color: AppTheme.getPrimaryColor(context),
                        fontSize: GlassConstants.fontBody,
                      )),
                ],
                if (_feedback != null)
                  Text(_feedback!,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: GlassConstants.fontBody,
                      )),
                if (hasOrganization)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _organize,
                    onChanged: _locked
                        ? null
                        : (value) => setState(() => _organize = value ?? false),
                    title: const Text('保存后按现有刮削设置重命名、整理目录'),
                  ),
                _buildMoveForm(),
                const SizedBox(height: GlassConstants.spacingSmall),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: GlassConstants.spacingSmall,
                  runSpacing: GlassConstants.spacingSmall,
                  children: [
                    Text(
                        '${widget.items.length} 项 · '
                        '已保存 ${widget.items.where((item) => item.applied).length} 项 · '
                        '待保存 $_saveCount 项',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: GlassConstants.fontBody,
                        )),
                    TextButton(
                      style: _buttonStyle,
                      onPressed: _locked ? null : () => Navigator.pop(context),
                      child: const Text('稍后继续'),
                    ),
                    FilledButton.icon(
                      style: _buttonStyle,
                      key: const ValueKey('save-reviewed-results'),
                      onPressed: _locked || _saveCount == 0 ? null : _save,
                      icon: const Icon(Icons.save_outlined,
                          size: GlassConstants.iconAction),
                      label: Text('保存已保留（$_saveCount）'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionTools() {
    return Wrap(
      spacing: GlassConstants.spacingSmall,
      runSpacing: GlassConstants.spacingTiny,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('已选 ${_selected.length} 项',
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: GlassConstants.fontBody,
            )),
        TextButton(
          style: _buttonStyle,
          onPressed: _locked
              ? null
              : () => setState(() {
                    _selected.clear();
                    _selected.addAll(widget.items);
                  }),
          child: const Text('全选'),
        ),
        TextButton(
          style: _buttonStyle,
          onPressed: _locked ? null : () => setState(() => _selected.clear()),
          child: const Text('清空选择'),
        ),
        TextButton(
          style: _buttonStyle,
          onPressed: _locked
              ? null
              : () => setState(() {
                    _selected.clear();
                    _selected.addAll(widget.items.where((item) =>
                        !item.recoveryRequired &&
                        (item.decision == ScrapeReviewDecision.discard ||
                            !item.canKeep ||
                            item.applyError != null ||
                            item.moveError != null)));
                  }),
          child: const Text('选择放弃和失败项'),
        ),
        OutlinedButton(
          style: _buttonStyle,
          onPressed: _locked ||
                  _selected.every((item) => item.applied || !item.canKeep)
              ? null
              : () => _decide(_selected, ScrapeReviewDecision.keep),
          child: const Text('保留所选'),
        ),
        OutlinedButton(
          style: _buttonStyle,
          onPressed: _locked || _selected.every((item) => item.applied)
              ? null
              : () => _decide(_selected, ScrapeReviewDecision.discard),
          child: const Text('放弃所选'),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        return ListTile(
          key: ValueKey('review-item-$index'),
          selected: _activeIndex == index,
          selectedTileColor:
              AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: GlassConstants.spacingTiny),
          leading: Checkbox(
            semanticLabel:
                '选择${item.originalGame.title ?? path.basename(item.game.path)}',
            value: _selected.contains(item),
            onChanged: _locked
                ? null
                : (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(item);
                      } else {
                        _selected.remove(item);
                      }
                    }),
          ),
          title: Text(
              item.originalGame.title ?? path.basename(item.originalGame.path),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          subtitle: Text(item.candidate?.title ?? item.fetchError ?? '未取得候选资料',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(item.status,
              style: TextStyle(
                fontSize: GlassConstants.fontSmall,
                color: item.applyError != null || !item.canKeep
                    ? AppTheme.errorColor
                    : AppTheme.getTextSecondary(context),
              )),
          onTap: _locked ? null : () => setState(() => _activeIndex = index),
        );
      },
    );
  }

  Widget _buildPreview() {
    final item = _active;
    final info = item.candidate;
    final rawDescription = info?.description?.trim().isNotEmpty == true
        ? info!.description!
        : html_parser.parse(info?.descriptionHtml ?? '').body?.text.trim() ??
            '';
    final description =
        rawDescription.replaceAll(RegExp(r'\[(?:图片|视频):[^\]]+\]'), '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              style: _iconButtonStyle,
              tooltip: '上一项',
              onPressed: _locked || _activeIndex == 0
                  ? null
                  : () => setState(() => _activeIndex--),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
                child: Text(
                    '${_activeIndex + 1}/${widget.items.length} · ${item.status}',
                    textAlign: TextAlign.center)),
            IconButton(
              style: _iconButtonStyle,
              tooltip: '下一项',
              onPressed: _locked || _activeIndex == widget.items.length - 1
                  ? null
                  : () => setState(() => _activeIndex++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey('review-preview-$_activeIndex'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detail(
                    '原游戏',
                    item.originalGame.title ??
                        path.basename(item.originalGame.path)),
                _detail('当前目录', item.game.path),
                _detail('候选标题', info?.title ?? '未取得'),
                _detail('来源', info?.sourceUrl ?? item.game.sourceUrl ?? ''),
                if (info?.maker != null) _detail('厂商', info!.maker!),
                if (info != null)
                  _detail(
                      '标签 / 系列',
                      [...info.tags, if (info.category != null) info.category!]
                          .join('、')),
                if (item.fetchError != null) _notice(item.fetchError!),
                if (item.applyError != null) _notice('保存失败：${item.applyError}'),
                if (item.moveError != null) _notice('移动失败：${item.moveError}'),
                for (final notice in item.notices) _notice(notice),
                if (info != null) ...[
                  _detail('简介',
                      description.isEmpty ? '本次未取得简介，请核对来源。' : description),
                  if (info.screenshots.isNotEmpty) ...[
                    const SizedBox(height: GlassConstants.spacingSmall),
                    Text('图片（${info.screenshots.length}）',
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontSize: GlassConstants.fontBody,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: GlassConstants.spacingSmall),
                    SizedBox(
                      height: LayoutConstants.reviewImageHeight,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: info.screenshots.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: GlassConstants.spacingSmall),
                        itemBuilder: (context, index) => SizedBox(
                          width: LayoutConstants.listThumbnailWidth,
                          child: _ReviewImage(
                            key: ValueKey(info.screenshots[index]),
                            url: info.screenshots[index],
                            sourceUrl: info.sourceUrl,
                            index: index,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: GlassConstants.spacingSmall),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: GlassConstants.spacingSmall,
          runSpacing: GlassConstants.spacingSmall,
          children: [
            if (!item.applied && item.decision != ScrapeReviewDecision.pending)
              TextButton(
                style: _buttonStyle,
                onPressed: _locked
                    ? null
                    : () => _decide([item], ScrapeReviewDecision.pending),
                child: const Text('重新判断'),
              ),
            OutlinedButton(
              style: _buttonStyle,
              key: const ValueKey('discard-review-item'),
              onPressed: _locked || item.applied || item.recoveryRequired
                  ? null
                  : () => _decideActive(ScrapeReviewDecision.discard),
              child: const Text('放弃此项'),
            ),
            FilledButton(
              style: _buttonStyle,
              key: const ValueKey('keep-review-item'),
              onPressed: _locked ||
                      item.applied ||
                      !item.canKeep ||
                      item.recoveryRequired
                  ? null
                  : () => _decideActive(ScrapeReviewDecision.keep),
              child: const Text('保留此项'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassConstants.spacingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: GlassConstants.fontSmall,
              )),
          SelectableText(value.isEmpty ? '—' : value,
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: GlassConstants.fontControl,
              )),
        ],
      ),
    );
  }

  Widget _notice(String message) => Padding(
        padding: const EdgeInsets.only(bottom: GlassConstants.spacingSmall),
        child: Text(message,
            style: const TextStyle(
              color: AppTheme.warningOrange,
              fontSize: GlassConstants.fontBody,
            )),
      );

  Widget _buildMoveForm() {
    final destination = SizedBox(
      height: _controlHeight,
      child: TextField(
        key: const ValueKey('review-move-destination'),
        controller: _destination,
        enabled: !_locked,
        style: const TextStyle(fontSize: GlassConstants.fontControl),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          labelText: '移动所选游戏到文件夹',
          labelStyle: const TextStyle(fontSize: GlassConstants.fontControl),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: GlassConstants.spacingMedium,
              vertical: GlassConstants.spacingMedium),
          enabledBorder: _destinationError == null
              ? null
              : const OutlineInputBorder(
                  borderRadius: BorderRadius.all(
                      Radius.circular(GlassConstants.radiusMedium)),
                  borderSide: BorderSide(color: AppTheme.errorColor)),
        ),
        onChanged: (_) {
          if (_destinationError != null) {
            setState(() => _destinationError = null);
          }
        },
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          style: _iconButtonStyle,
          tooltip: '选择目标文件夹',
          onPressed: _locked ? null : _pickDestination,
          icon: const Icon(Icons.folder_open),
        ),
        const SizedBox(width: GlassConstants.spacingSmall),
        OutlinedButton(
          style: _buttonStyle,
          key: const ValueKey('move-reviewed-games'),
          onPressed: _locked || _selected.isEmpty ? null : _move,
          child: Text('移动所选（${_selected.length}）'),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < LayoutConstants.formCompactWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                destination,
                const SizedBox(height: GlassConstants.spacingSmall),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: destination),
              const SizedBox(width: GlassConstants.spacingSmall),
              actions,
            ],
          );
        }),
        const SizedBox(height: GlassConstants.spacingTiny),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: GlassConstants.spacingMedium),
          child: Semantics(
            liveRegion: _destinationError != null,
            child: Text(_destinationError ?? '保持每个游戏的子目录；同名目录会提示冲突。',
                style: TextStyle(
                  color: _destinationError == null
                      ? AppTheme.getTextSecondary(context)
                      : AppTheme.errorColor,
                  fontSize: GlassConstants.fontSmall,
                )),
          ),
        ),
      ],
    );
  }
}

class _ReviewImage extends StatefulWidget {
  final String url;
  final String sourceUrl;
  final int index;

  const _ReviewImage(
      {super.key,
      required this.url,
      required this.sourceUrl,
      required this.index});

  @override
  State<_ReviewImage> createState() => _ReviewImageState();
}

class _ReviewImageState extends State<_ReviewImage> {
  late final Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() async {
    final uri = Uri.parse(widget.url);
    final client = await createProxyClientFromPrefs(domain: uri.host);
    try {
      final response = await client
          .get(uri, headers: await buildScrapeImageHeaders(widget.sourceUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw StateError('图片预览加载失败');
      }
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }

  Widget _error() => Center(
      child: Text('图片预览加载失败',
          style: TextStyle(
            color: AppTheme.getTextSecondary(context),
            fontSize: GlassConstants.fontBody,
          )));

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _error();
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(snapshot.data!,
              fit: BoxFit.contain,
              semanticLabel: '候选图片 ${widget.index + 1}',
              errorBuilder: (context, error, stackTrace) => _error());
        },
      );
}
