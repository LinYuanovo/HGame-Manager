import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/scrape_mode_config.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';

class ScrapeModeConfigDialog extends ConsumerStatefulWidget {
  const ScrapeModeConfigDialog({super.key});

  @override
  ConsumerState<ScrapeModeConfigDialog> createState() => _ScrapeModeConfigDialogState();
}

class _ScrapeModeConfigDialogState extends ConsumerState<ScrapeModeConfigDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabLabels = ['快速刮削', '重新刮削', '刮削中心', '单个添加', '批量添加'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: ScrapeMode.values.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _resetToDefaults() {
    ref.read(scrapeModeConfigsProvider.notifier).resetToDefaults();
  }

  void _saveAndClose() {
    ref.read(scrapeModeConfigsProvider.notifier).save();
    Navigator.pop(context, true);
    AppTheme.showGlassToast(
      context,
      message: '刮削行为配置已保存',
      icon: Icons.check_circle,
      iconColor: AppTheme.successColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        height: 500,
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(color: AppTheme.getBorderColor(context)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(child: _buildTabContent()),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(Icons.tune, color: AppTheme.getPrimaryColor(context), size: 24),
          const SizedBox(width: 12),
          Text(
            '刮削行为配置',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundColor(context),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      ),
      child: Row(
        children: List.generate(
          ScrapeMode.values.length,
          (index) => Expanded(child: _buildTabItem(index, _tabLabels[index])),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label) {
    final isSelected = _tabController.index == index;
    return _TabItemWidget(
      label: label,
      isSelected: isSelected,
      onTap: () => _tabController.animateTo(index),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: ScrapeMode.values.map((mode) => _ConfigTab(mode: mode)).toList(),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _resetToDefaults,
            child: Text('恢复默认', style: TextStyle(color: AppTheme.getTextSecondary(context))),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _saveAndClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.getPrimaryColor(context),
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _TabItemWidget extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabItemWidget({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TabItemWidget> createState() => _TabItemWidgetState();
}

class _TabItemWidgetState extends State<_TabItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: GlassConstants.animFast,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppTheme.getPrimaryColor(context)
                : _isHovered
                    ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? AppTheme.getTextColorOnPrimary(context) : AppTheme.getTextSecondary(context),
              fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfigTab extends ConsumerWidget {
  final ScrapeMode mode;

  static const _modeHints = {
    ScrapeMode.quickScrape: '游戏详情页顶部输入URL/ID回车触发',
    ScrapeMode.rescrape: '游戏详情页刷新按钮，用已有来源重新抓取',
    ScrapeMode.scraperCenter: '刮削页面，扫描含source_url.txt的文件夹后批量刮削',
    ScrapeMode.singleAdd: '游戏列表页"+"按钮，选择单个文件夹导入',
    ScrapeMode.batchAdd: '游戏列表页"创建文件夹"按钮，选择父目录批量导入',
  };

  const _ConfigTab({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(scrapeModeConfigsProvider).getConfig(mode);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppTheme.getPrimaryColor(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _modeHints[mode] ?? '',
                    style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSwitchTile(
            context: context,
            ref: ref,
            value: config.renameFolder,
            onChanged: (value) => ref.read(scrapeModeConfigsProvider.notifier).updateConfig(
              mode,
              config.copyWith(renameFolder: value),
            ),
            title: '刮削后重命名游戏文件夹',
            subtitle: '根据刮削到的标题自动重命名游戏文件夹',
          ),
          const SizedBox(height: 8),
          _buildSwitchTile(
            context: context,
            ref: ref,
            value: config.moveToSorted,
            onChanged: (value) => ref.read(scrapeModeConfigsProvider.notifier).updateConfig(
              mode,
              config.copyWith(moveToSorted: value),
            ),
            title: '刮削后移动到整理目录',
            subtitle: '将游戏自动移动到对应游戏库的整理目录',
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required WidgetRef ref,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.getPrimaryColor(context),
            inactiveThumbColor: AppTheme.getTextSecondary(context),
            inactiveTrackColor: AppTheme.getBorderColor(context),
          ),
        ],
      ),
    );
  }
}
