import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class DetailScrollButtons extends StatefulWidget {
  final ScrollController scrollController;

  const DetailScrollButtons({super.key, required this.scrollController});

  @override
  State<DetailScrollButtons> createState() => _DetailScrollButtonsState();
}

class _DetailScrollButtonsState extends State<DetailScrollButtons> {
  bool _showTop = false;
  bool _showBottom = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateButtons);
    _updateButtons();
  }

  @override
  void didUpdateWidget(DetailScrollButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateButtons);
      widget.scrollController.addListener(_updateButtons);
      _updateButtons();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateButtons);
    super.dispose();
  }

  void _updateButtons() {
    if (!mounted) return;
    
    final controller = widget.scrollController;
    if (!controller.hasClients) return;

    final position = controller.position;
    final maxScroll = position.maxScrollExtent;
    
    if (maxScroll <= 0) {
      setState(() {
        _showTop = false;
        _showBottom = false;
      });
      return;
    }

    final currentScroll = controller.offset;
    const threshold = 100.0;

    setState(() {
      _showTop = currentScroll > threshold;
      _showBottom = currentScroll < maxScroll - threshold;
    });
  }

  void _scrollToTop() {
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom() {
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    widget.scrollController.animateTo(
      maxScroll,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_showTop && !_showBottom) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showTop)
              _buildButton(
                icon: Icons.keyboard_arrow_up,
                onPressed: _scrollToTop,
                tooltip: '滚动到顶部',
              ),
            const SizedBox(height: 8),
            if (_showBottom)
              _buildButton(
                icon: Icons.keyboard_arrow_down,
                onPressed: _scrollToBottom,
                tooltip: '滚动到底部',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Builder(
      builder: (context) => Tooltip(
        message: tooltip,
        child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.getBorderColor(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          color: AppTheme.getPrimaryColor(context),
        ),
      ),
    ),
    );
  }
}
