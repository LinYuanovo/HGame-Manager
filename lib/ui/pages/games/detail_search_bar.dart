import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'content_search_engine.dart';

class DetailSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final List<ContentSearchMatch> matches;
  final int currentMatchIndex;
  final bool hasSearched;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<String> onSearch;
  final VoidCallback onClose;

  const DetailSearchBar({
    super.key,
    required this.controller,
    required this.matches,
    required this.currentMatchIndex,
    required this.hasSearched,
    required this.onNext,
    required this.onPrevious,
    required this.onSearch,
    required this.onClose,
  });

  @override
  State<DetailSearchBar> createState() => _DetailSearchBarState();
}

class _DetailSearchBarState extends State<DetailSearchBar> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceColor(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.getBorderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: AppTheme.getTextSecondary(context)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)),
              decoration: InputDecoration(
                hintText: '搜索内容... (Ctrl+F)',
                hintStyle: TextStyle(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: widget.onSearch,
            ),
          ),
          if (widget.matches.isNotEmpty)
            Text(
              '${widget.currentMatchIndex + 1}/${widget.matches.length}',
              style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
            )
          else if (widget.hasSearched)
            const Text(
              '无匹配',
              style: TextStyle(fontSize: 12, color: AppTheme.warningColor),
            ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: Icons.keyboard_arrow_up,
            onPressed: widget.matches.isEmpty ? null : widget.onPrevious,
            tooltip: '上一个',
          ),
          _buildActionButton(
            icon: Icons.keyboard_arrow_down,
            onPressed: widget.matches.isEmpty ? null : widget.onNext,
            tooltip: '下一个',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: widget.onClose,
            color: AppTheme.getTextSecondary(context),
            tooltip: '关闭搜索 (Ctrl+F)',
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        color: AppTheme.getPrimaryColor(context),
        disabledColor: AppTheme.getTextSecondary(context).withValues(alpha: 0.3),
      ),
    );
  }
}
