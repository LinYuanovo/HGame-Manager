import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/pilipili_service.dart';
import '../../../core/services/fan2d_service.dart';
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
      if (mounted) {
        setState(() => _isSearching = false);
        AppTheme.showGlassToast(context, message: '搜索失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _selectResult(dynamic result) async {
    String? content;
    if (result is PilipiliSearchResult) {
      final service = PilipiliService();
      content = await service.getArticleContent(result.articleId);
    } else if (result is Fan2dGuideResult) {
      final service = ref.read(fan2dServiceProvider);
      content = await service.scrapeGuideContent(result.guideUrl);
    }
    if (content != null && mounted) {
      Navigator.of(context).pop(content);
    } else if (mounted) {
      AppTheme.showGlassToast(context, message: '获取攻略内容失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
    }
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
            ),
            child: DropdownButton<GuideSource>(
              value: _selectedSource,
              underline: const SizedBox(),
              isDense: true,
              items: const [
                DropdownMenuItem(value: GuideSource.pilipili, child: Text('pilipili', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: GuideSource.fan2d, child: Text('2DFan', style: TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _selectedSource = v ?? GuideSource.pilipili),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: 14, color: AppTheme.getDetailTextPrimary(context)),
              decoration: InputDecoration(
                hintText: '输入游戏名搜索攻略...',
                hintStyle: TextStyle(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.5))),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSearching ? null : _search,
            icon: _isSearching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 18),
            label: const Text('搜索'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.getPrimaryColor(context), foregroundColor: Colors.white),
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
        final subtitle = result is PilipiliSearchResult ? '作者: ${result.author} | 阅读: ${result.viewCount}' : '2DFan攻略';
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
                          Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
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
