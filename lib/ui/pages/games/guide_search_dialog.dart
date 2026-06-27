import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/pilipili_service.dart';
import '../../../core/services/fan2d_service.dart';
import '../../../core/utils/proxy_client.dart';
import '../../theme/app_theme.dart';

enum GuideSource { pilipili, fan2d }

class GuideSearchDialog extends ConsumerStatefulWidget {
  final Game game;
  final String initialKeyword;

  const GuideSearchDialog({super.key, required this.game, required this.initialKeyword});

  @override
  ConsumerState<GuideSearchDialog> createState() => _GuideSearchDialogState();
}

class _GuideSearchDialogState extends ConsumerState<GuideSearchDialog> {
  late TextEditingController _searchController;
  GuideSource _selectedSource = GuideSource.pilipili;
  bool _isSearching = false;
  List<dynamic> _results = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    setState(() { _isSearching = true; _results = []; });
    try {
      if (_selectedSource == GuideSource.pilipili) {
        final service = PilipiliService();
        final results = await service.searchArticles(keyword);
        if (mounted) setState(() { _results = results; _isSearching = false; });
      } else {
        final service = ref.read(fan2dServiceProvider);
        final results = await service.searchGuides(keyword);
        if (mounted) setState(() { _results = results; _isSearching = false; });
      }
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() => _isSearching = false);
        AppTheme.showGlassToast(context, message: errorMsg, icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _selectResult(dynamic result) async {
    String? content;
    try {
      if (result is PilipiliSearchResult) {
        final service = PilipiliService();
        content = await service.getArticleContent(result.articleId);
      } else if (result is Fan2dGuideResult) {
        final service = ref.read(fan2dServiceProvider);
        final scrapeResult = await service.scrapeGuideContent(result.guideUrl);

        // 如果有多个walkthrough，让用户选择
        if (scrapeResult.hasWalkthroughs) {
          if (!mounted) return;
          final selectedWalkthrough = await _showWalkthroughDialog(scrapeResult.walkthroughs);
          if (selectedWalkthrough == null) {
            if (mounted) {
              AppTheme.showGlassToast(context, message: '未选择攻略', icon: Icons.info_outline, iconColor: AppTheme.getTextSecondary(context));
            }
            return;
          }
          if (!mounted) return;
          content = await service.scrapeWalkthrough(selectedWalkthrough.url);
        } else {
          content = scrapeResult.content;
        }
      }

      // 下载图片并替换URL为本地路径
      if (content != null && content.isNotEmpty) {
        content = await _downloadGuideImages(content);
      }
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        AppTheme.showGlassToast(context, message: errorMsg, icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
      return;
    }

    if (content != null && mounted) {
      Navigator.of(context).pop(content);
    } else if (mounted && content == null) {
      AppTheme.showGlassToast(context, message: '获取攻略内容失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
    }
  }

  /// 下载攻略中的图片并替换为本地路径
  Future<String> _downloadGuideImages(String content) async {
    // 提取所有图片URL - 支持 ![图片](url) 和 [图片:url] 两种格式
    final imagePattern = RegExp(r'!\[图片\]\(([^)]+)\)|\[图片:([^\]]+)\]');
    final matches = imagePattern.allMatches(content).toList();

    if (matches.isEmpty) return content;

    final imageUrls = <String>[];
    for (final match in matches) {
      final url = match.group(1) ?? match.group(2) ?? '';
      if (url.isNotEmpty && url.startsWith('http')) {
        imageUrls.add(url);
      }
    }

    if (imageUrls.isEmpty) return content;

    if (mounted) {
      AppTheme.showGlassToast(context, message: '正在下载 ${imageUrls.length} 张图片...', icon: Icons.cloud_download, iconColor: AppTheme.getPrimaryColor(context));
    }

    // 创建图片目录
    final gamePath = widget.game.path;
    final imagesDir = Directory('$gamePath${Platform.pathSeparator}images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 下载图片并保存为 guide_xx.xx 格式
    final localPaths = <String>[];
    final client = await createProxyClientFromPrefs(domain: 'i0.hdslb.com');
    try {
      for (int i = 0; i < imageUrls.length; i++) {
        final url = imageUrls[i];
        try {
          final response = await client.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://www.bilibili.com/',
            },
          ).timeout(const Duration(seconds: 30));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            // 从URL获取扩展名
            final uri = Uri.parse(url);
            final pathSegments = uri.pathSegments;
            var ext = '.jpg';
            if (pathSegments.isNotEmpty) {
              final lastSegment = pathSegments.last;
              if (lastSegment.contains('.')) {
                ext = '.${lastSegment.split('.').last}';
              }
            }

            final fileName = 'guide_${(i + 1).toString().padLeft(2, '0')}$ext';
            final filePath = '$gamePath${Platform.pathSeparator}images${Platform.pathSeparator}$fileName';
            await File(filePath).writeAsBytes(response.bodyBytes, flush: true);
            localPaths.add(filePath);
            if (kDebugMode) debugPrint('[Guide] 下载图片: $fileName');
          } else {
            localPaths.add(url);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Guide] 下载图片失败: $url, $e');
          localPaths.add(url);
        }
      }
    } finally {
      client.close();
    }

    // 替换内容中的URL为本地路径 - 使用 [图片:path] 格式
    String result = content;
    int urlIndex = 0;
    result = result.replaceAllMapped(imagePattern, (match) {
      if (urlIndex < localPaths.length) {
        final localPath = localPaths[urlIndex];
        urlIndex++;
        return '[图片:$localPath]';
      }
      return match.group(0)!;
    });

    return result;
  }

  Future<Fan2dWalkthrough?> _showWalkthroughDialog(List<Fan2dWalkthrough> walkthroughs) async {
    return showGlassDialog<Fan2dWalkthrough>(
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
                  const Icon(Icons.menu_book, color: AppTheme.primaryColor, size: 22),
                  const SizedBox(width: 10),
                  Text('选择攻略', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                ],
              ),
              const SizedBox(height: 8),
              Text('找到 ${walkthroughs.length} 个攻略，请选择：', style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 13)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: walkthroughs.length,
                  itemBuilder: (context, index) {
                    final wt = walkthroughs[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                          onTap: () => Navigator.pop(context, wt),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                              border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.article_outlined, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 12),
                                Expanded(child: Text(wt.title, style: TextStyle(fontSize: 14, color: AppTheme.getDetailTextPrimary(context)), overflow: TextOverflow.ellipsis)),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.getSurfaceColor(context),
            borderRadius: BorderRadius.circular(GlassConstants.radiusXLarge),
            border: Border.all(color: AppTheme.getBorderColor(context)),
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              Divider(height: 1, color: AppTheme.getBorderColor(context)),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        children: [
          Icon(Icons.menu_book, color: AppTheme.getPrimaryColor(context), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text('搜索攻略', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), color: AppTheme.getTextSecondary(context), onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<GuideSource>(
                value: _selectedSource,
                isDense: true,
                dropdownColor: AppTheme.getSurfaceColor(context),
                borderRadius: BorderRadius.circular(8),
                items: const [
                  DropdownMenuItem(value: GuideSource.pilipili, child: Text('pilipili', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: GuideSource.fan2d, child: Text('2DFan', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _selectedSource = v ?? GuideSource.pilipili),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 14, color: AppTheme.getDetailTextPrimary(context)),
                decoration: InputDecoration(
                  hintText: '输入游戏名搜索攻略...',
                  hintStyle: TextStyle(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.5))),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _isSearching ? null : _search,
              icon: _isSearching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 18),
              label: const Text('搜索'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.getPrimaryColor(context), foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) return Center(child: Text('无搜索结果', style: TextStyle(color: AppTheme.getTextSecondary(context))));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final title = result is PilipiliSearchResult ? result.title : (result as Fan2dGuideResult).title;
        final subtitle = result is PilipiliSearchResult ? result.summary : '2DFan攻略';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            child: InkWell(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              onTap: () => _selectResult(result),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 14, color: AppTheme.getDetailTextPrimary(context)), overflow: TextOverflow.ellipsis),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.getTextSecondary(context)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
