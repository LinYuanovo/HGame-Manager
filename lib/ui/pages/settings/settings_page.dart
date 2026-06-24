import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/app_paths.dart';
import '../../../core/utils/proxy_client.dart';
import '../../../core/services/webdav_service.dart';
import '../../../scraper/html_parser.dart';
import '../../theme/app_theme.dart';
import '../../../core/utils/app_settings.dart';
import 'context_menu_manager_dialog.dart';

Future<void> showSettingsDialog(BuildContext context, WidgetRef ref) async {
  await showGlassDialog(
    context: context,
    child: const SettingsDialogContent(),
  );
}

class SettingsDialogContent extends ConsumerStatefulWidget {
  const SettingsDialogContent({super.key});

  @override
  ConsumerState<SettingsDialogContent> createState() => _SettingsDialogContentState();
}

class _SettingsDialogContentState extends ConsumerState<SettingsDialogContent> {
  List<String> _libraryPaths = [];
  Map<String, String> _sortedPaths = {};
  late TextEditingController _proxyUrlController;
  late TextEditingController _proxyTestUrlController;
  late TextEditingController _cookieAcgyingController;
  late TextEditingController _cookieFeixueController;
  late TextEditingController _cookieVikacgController;
  late TextEditingController _domainAcgyingController;
  late TextEditingController _domainFeixueController;
  late TextEditingController _domainVikacgController;
  late TextEditingController _domain2dfanController;
  bool _isDetecting2dfanDomain = false;
  late TextEditingController _webdavUrlController;
  late TextEditingController _webdavUsernameController;
  late TextEditingController _webdavPasswordController;
  String _proxyMode = 'none';
  bool _isTestingProxy = false;
  String? _proxyTestResult;
  String _selectedFont = '';
  double _fontSize = 14.0;
  double _detailFontSize = 14.0;
  bool _webdavPasswordVisible = false;
  bool _isBackingUp = false;
  bool _isLoadingBackups = false;
  List<WebDavFile>? _backupFiles;
  List<Map<String, String>> _xpathConfigs = [];
  bool _autoRenameFolders = false;
  bool _isRenamingFolders = false;
  bool _noImageMode = false;
  bool _keepPlayedInGames = false;

  int _selectedSidebarIndex = 0;

  static const List<_SidebarCategory> _categories = [
    _SidebarCategory(
      label: '通用',
      icon: Icons.tune,
      items: ['游戏库设置', '忽略文件夹', '双击启动游戏', '已玩游戏保留库中', '无图模式', '字体设置'],
    ),
    _SidebarCategory(
      label: '管理',
      icon: Icons.admin_panel_settings_outlined,
      items: ['右键菜单管理', '黑名单管理'],
    ),
    _SidebarCategory(
      label: '刮削',
      icon: Icons.description_outlined,
      items: ['刮削后游戏文件夹重命名', '论坛自定义域名', 'Cookie设置', '自定义解析器'],
    ),
    _SidebarCategory(
      label: '网络',
      icon: Icons.language,
      items: ['网络代理设置'],
    ),
    _SidebarCategory(
      label: '备份',
      icon: Icons.backup_outlined,
      items: ['本地备份', 'WebDav云备份'],
    ),
    _SidebarCategory(
      label: '关于',
      icon: Icons.info_outline,
      items: ['关于'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final prefs = ref.read(sharedPreferencesProvider);
    final proxyMode = prefs.getString('proxy_mode') ?? 'none';
    final proxyUrl = prefs.getString('proxy_url') ?? '';
    final font = prefs.getString('font_family') ?? '';
    final fontSize = prefs.getDouble('font_size') ?? 14.0;
    final detailFontSize = prefs.getDouble('detail_font_size') ?? 14.0;

    final cookieAcgying = prefs.getString('cookie_acgying') ?? '';
    final cookieFeixue = prefs.getString('cookie_feixue') ?? '';
    final cookieVikacg = prefs.getString('cookie_vikacg') ?? '';

    // Library path migration
    final rawLib = prefs.getString('library_path') ?? '';
    if (rawLib.startsWith('[')) {
      try {
        final List<dynamic> list = jsonDecode(rawLib);
        _libraryPaths = list.whereType<String>().where((s) => s.isNotEmpty).toList();
      } catch (_) {
        _libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
      }
    } else {
      _libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
    }

    // Sorted paths migration
    final rawSorted = prefs.getString('sorted_paths') ?? '';
    if (rawSorted.startsWith('{')) {
      try {
        final decoded = jsonDecode(rawSorted) as Map<String, dynamic>;
        _sortedPaths = decoded.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      } catch (_) {
        _sortedPaths = {};
      }
    } else {
      final oldSorted = prefs.getString('sorted_path') ?? '';
      if (oldSorted.isNotEmpty && _libraryPaths.isNotEmpty) {
        _sortedPaths = {_libraryPaths.first: oldSorted};
      }
    }

    _proxyUrlController = TextEditingController(text: proxyUrl);
    _proxyTestUrlController = TextEditingController(text: prefs.getString('proxy_test_url') ?? '');
    _cookieAcgyingController = TextEditingController(text: cookieAcgying);
    _cookieFeixueController = TextEditingController(text: cookieFeixue);
    _cookieVikacgController = TextEditingController(text: cookieVikacg);
    _domainAcgyingController = TextEditingController(text: prefs.getString('domain_acgying') ?? '');
    _domainFeixueController = TextEditingController(text: prefs.getString('domain_feixue') ?? '');
    _domainVikacgController = TextEditingController(text: prefs.getString('domain_vikacg') ?? '');
    _domain2dfanController = TextEditingController(text: prefs.getString('domain_2dfan') ?? '');
    _webdavUrlController = TextEditingController(text: prefs.getString('webdav_url') ?? '');
    _webdavUsernameController = TextEditingController(text: prefs.getString('webdav_username') ?? '');
    _webdavPasswordController = TextEditingController(text: prefs.getString('webdav_password') ?? '');
    _proxyMode = proxyMode;
    _selectedFont = font;
    _fontSize = fontSize;
    _detailFontSize = detailFontSize;

    _autoRenameFolders = prefs.getBool(AppSettings.autoRenameFoldersKey) ?? false;
    _noImageMode = prefs.getBool(AppSettings.noImageModeKey) ?? false;
    _keepPlayedInGames = prefs.getBool(AppSettings.keepPlayedInGamesKey) ?? false;

    _loadXpathConfigs();
  }

  void _loadXpathConfigs() {
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonStr = prefs.getString('xpath_parsers');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        _xpathConfigs = list
            .whereType<Map<String, dynamic>>()
            .map((m) => m.map((k, v) => MapEntry(k, v?.toString() ?? '')))
            .toList();
      } catch (_) {
        _xpathConfigs = [];
      }
    }
  }

  Future<void> _saveXpathConfigs() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonStr = jsonEncode(_xpathConfigs);
    await prefs.setString('xpath_parsers', jsonStr);
    await HtmlScraper.reloadXpathParsers();
  }

  @override
  void dispose() {
    _proxyUrlController.dispose();
    _proxyTestUrlController.dispose();
    _cookieAcgyingController.dispose();
    _cookieFeixueController.dispose();
    _cookieVikacgController.dispose();
    _domainAcgyingController.dispose();
    _domainFeixueController.dispose();
    _domainVikacgController.dispose();
    _domain2dfanController.dispose();
    _webdavUrlController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.6;
    final dialogHeight = screenSize.height * 0.8;

    return SizedBox(
      width: dialogWidth,
      height: dialogHeight,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings, color: AppTheme.primaryColor, size: 22),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
            child: const Text(
              '设置',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.2)),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedSidebarIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              child: InkWell(
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                onTap: () => setState(() => _selectedSidebarIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withValues(alpha: 0.15),
                              AppTheme.secondaryColor.withValues(alpha: 0.15),
                            ],
                          )
                        : null,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        cat.icon,
                        color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        cat.label,
                        style: TextStyle(
                          color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    final cat = _categories[_selectedSidebarIndex];
    final widgets = <Widget>[];
    for (final item in cat.items) {
      widgets.add(_buildSectionForItem(item));
      widgets.add(const SizedBox(height: 16));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  Widget _buildSectionForItem(String item) {
    switch (item) {
      case '游戏库设置':
        return _buildLibrarySection();
      case '忽略文件夹':
        return _buildIgnoreFoldersSection();
      case '双击启动游戏':
        return _buildDoubleClickSection();
      case '已玩游戏保留库中':
        return _buildKeepPlayedSection();
      case '无图模式':
        return _buildNoImageModeSection();
      case '字体设置':
        return _buildFontSection();
      case '右键菜单管理':
        return _buildContextMenuSection();
      case '黑名单管理':
        return _buildBlacklistSection();
      case '刮削后游戏文件夹重命名':
        return _buildFolderRenameSection();
      case '论坛自定义域名':
        return _buildForumDomainSection();
      case 'Cookie设置':
        return _buildCookieSection();
      case '自定义解析器':
        return _buildXpathSection();
      case '网络代理设置':
        return _buildProxySection();
      case '本地备份':
        return _buildLocalBackupSection();
      case 'WebDav云备份':
        return _buildWebdavSection();
      case '关于':
        return _buildAboutSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () async {
              await _saveSettings();
              if (mounted) Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLibrarySection() {
    return _buildSection(
      title: '游戏库设置',
      icon: Icons.folder_outlined,
      children: [
        Text(
          '游戏库目录',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_libraryPaths.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            child: Text(
              '未配置游戏库目录',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 13),
            ),
          ),
        ..._libraryPaths.asMap().entries.map((entry) {
          final idx = entry.key;
          final libPath = entry.value;
          final sortedPath = _sortedPaths[libPath] ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                          border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          libPath,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                      onPressed: () => _removeLibraryPath(idx),
                      tooltip: '移除',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, size: 16, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: sortedPath.isNotEmpty
                            ? Row(
                                children: [
                                  Icon(Icons.check_circle, size: 14, color: AppTheme.successColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      sortedPath,
                                      style: TextStyle(color: AppTheme.successColor.withValues(alpha: 0.8), fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                '未设置整理目录（刮削后不移动）',
                                style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 12),
                              ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 28,
                        child: OutlinedButton(
                          onPressed: () => _selectSortedPath(idx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('选择', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                      if (sortedPath.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 28,
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() => _sortedPaths.remove(libPath));
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.errorColor,
                              side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('清除', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addLibraryPath,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加目录', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _scanNow,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('扫描游戏库'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addLibraryPath() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择游戏库目录');
    if (result != null && !_libraryPaths.contains(result)) {
      setState(() => _libraryPaths.add(result));
    }
  }

  void _removeLibraryPath(int idx) {
    final removed = _libraryPaths.removeAt(idx);
    _sortedPaths.remove(removed);
    setState(() {});
  }

  Future<void> _selectSortedPath(int libIdx) async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择整理目录');
    if (result != null) {
      setState(() => _sortedPaths[_libraryPaths[libIdx]] = result);
    }
  }

  Widget _buildIgnoreFoldersSection() {
    return _buildSection(
      title: '忽略文件夹',
      icon: Icons.folder_off_outlined,
      children: [
        Text('扫描忽略', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text('扫描游戏库时将跳过这些文件夹', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _getIgnoreFolders('scan_ignore_folders').map((folder) => Chip(
            label: Text(folder, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
            backgroundColor: AppTheme.backgroundColor.withValues(alpha: 0.3),
            side: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onDeleted: () => _removeIgnoreFolder('scan_ignore_folders', folder),
            deleteIcon: Icon(Icons.close, size: 14),
            deleteIconColor: AppTheme.textSecondary.withValues(alpha: 0.5),
          )).toList(),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _addIgnoreFolderFromPicker('scan_ignore_folders'),
            icon: Icon(Icons.folder_open, size: 16),
            label: Text('选择文件夹', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('刮削忽略', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text('刮削时将跳过这些文件夹', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _getIgnoreFolders('scrape_ignore_folders').map((folder) => Chip(
            label: Text(folder, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
            backgroundColor: AppTheme.backgroundColor.withValues(alpha: 0.3),
            side: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onDeleted: () => _removeIgnoreFolder('scrape_ignore_folders', folder),
            deleteIcon: Icon(Icons.close, size: 14),
            deleteIconColor: AppTheme.textSecondary.withValues(alpha: 0.5),
          )).toList(),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _addIgnoreFolderFromPicker('scrape_ignore_folders'),
            icon: Icon(Icons.folder_open, size: 16),
            label: Text('选择文件夹', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
      ],
    );
  }

  List<String> _getIgnoreFolders(String key) {
    final prefs = ref.read(sharedPreferencesProvider);
    final str = prefs.getString(key) ?? '';
    return str.split(',').where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _addIgnoreFolderFromPicker(String key) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: key == 'scan_ignore_folders' ? '选择扫描忽略的文件夹' : '选择刮削忽略的文件夹',
    );
    if (result != null) {
      final folderName = result.split(RegExp(r'[/\\]')).last;
      final folders = _getIgnoreFolders(key);
      if (!folders.contains(folderName)) {
        folders.add(folderName);
        final prefs = ref.read(sharedPreferencesProvider);
        prefs.setString(key, folders.join(','));
      }
      setState(() {});
    }
  }

  void _removeIgnoreFolder(String key, String folder) {
    final folders = _getIgnoreFolders(key);
    folders.remove(folder);
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(key, folders.join(','));
    setState(() {});
  }

  Widget _buildDoubleClickSection() {
    return _buildSection(
      title: '双击启动游戏',
      icon: Icons.touch_app_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('双击游戏卡片直接启动游戏', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    '开启后双击游戏列表中的游戏将直接启动',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            Switch(
              value: ref.watch(doubleClickLaunchProvider),
              onChanged: (value) async {
                ref.read(doubleClickLaunchProvider.notifier).state = value;
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool('double_click_launch', value);
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeepPlayedSection() {
    return _buildSection(
      title: '已玩游戏保留库中',
      icon: Icons.library_books_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('已玩游戏保留在游戏库中', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    '开启后，玩过的游戏同时在"游戏"页面和"已玩"页面显示，并在游戏左上角标记"玩过"',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Switch(
              value: _keepPlayedInGames,
              onChanged: (value) async {
                setState(() => _keepPlayedInGames = value);
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool(AppSettings.keepPlayedInGamesKey, value);
                ref.invalidate(allGamesProvider);
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFolderRenameSection() {
    return _buildSection(
      title: '游戏文件夹重命名',
      icon: Icons.drive_file_rename_outline,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自动重命名文件夹', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    '开启后后续刮削会将游戏文件夹名修改为: [游戏ID] [游戏类型] 游戏标题 游戏版本',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '提示：由于可能存在中文路径问题，请谨慎开启',
                    style: TextStyle(fontSize: 11, color: Colors.orange.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            Switch(
              value: _autoRenameFolders,
              onChanged: (value) async {
                setState(() => _autoRenameFolders = value);
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool(AppSettings.autoRenameFoldersKey, value);
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isRenamingFolders ? null : _renameAllFolders,
            icon: _isRenamingFolders
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.drive_file_rename_outline, size: 18),
            label: Text(_isRenamingFolders ? '重命名中...' : '立即重命名所有游戏文件夹'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _renameAllFolders() async {
    final renameService = ref.read(folderRenameServiceProvider);
    final renamableCount = await renameService.countRenamableGames();

    if (renamableCount == 0) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '没有需要重命名的游戏');
      }
      return;
    }

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确认重命名', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text('预计将重命名 $renamableCount 个游戏文件夹为:\n[游戏ID] [游戏类型] 游戏标题 游戏版本\n\n此操作不可撤销，是否继续？',
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('确认重命名'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRenamingFolders = true);
    try {
      final count = await renameService.renameAllGameFolders();
      if (mounted) {
        AppTheme.showGlassToast(context, message: '重命名完成，共处理 $count 个游戏');
        ref.invalidate(allGamesProvider);
        ref.invalidate(playedGamesProvider);
        ref.invalidate(favoriteGamesProvider);
        ref.invalidate(clearedGamesProvider);
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '重命名失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isRenamingFolders = false);
    }
  }

  Widget _buildProxySection() {
    return _buildSection(
      title: '网络代理设置',
      icon: Icons.language,
      children: [
        Row(
          children: [
            GlassChip(
              label: '不使用代理',
              isSelected: _proxyMode == 'none',
              onTap: () => setState(() => _proxyMode = 'none'),
            ),
            const SizedBox(width: 8),
            GlassChip(
              label: '使用系统代理',
              isSelected: _proxyMode == 'system',
              onTap: () => setState(() => _proxyMode = 'system'),
            ),
            const SizedBox(width: 8),
            GlassChip(
              label: '自定义代理',
              isSelected: _proxyMode == 'custom',
              onTap: () => setState(() => _proxyMode = 'custom'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _proxyTestUrlController,
                decoration: InputDecoration(
                  hintText: '默认: feixueacg.org',
                  hintStyle: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isTestingProxy ? null : _testProxy,
              icon: _isTestingProxy
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.network_check, size: 18),
              label: const Text('测试连接'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        if (_proxyTestResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _proxyTestResult!,
              style: TextStyle(
                color: _proxyTestResult!.contains('成功') ? AppTheme.successColor : AppTheme.errorColor,
                fontSize: 13,
              ),
            ),
          ),
        if (_proxyMode == 'custom') ...[
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('代理地址', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _proxyUrlController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '例如: 127.0.0.1:7890',
                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildForumDomainSection() {
    return _buildSection(
      title: '论坛自定义域名',
      icon: Icons.language,
      children: [
        Text(
          '自定义论坛域名，修改后搜索和刮削将使用新域名访问对应论坛',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildDomainInput(
          label: 'ACG嘤嘤怪',
          controller: _domainAcgyingController,
          hint: '默认: acgyyg.ru',
        ),
        const SizedBox(height: 12),
        _buildDomainInput(
          label: '飞雪ACG',
          controller: _domainFeixueController,
          hint: '默认: feixueacg.org',
        ),
        const SizedBox(height: 12),
        _buildDomainInput(
          label: '维咔ACG',
          controller: _domainVikacgController,
          hint: '默认: vikacg.com',
        ),
        const SizedBox(height: 12),
        _build2dfanDomainInput(),
      ],
    );
  }

  Widget _build2dfanDomainInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('2DFan', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _domain2dfanController,
                style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '默认: 留空自动检测',
                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 11),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: _isDetecting2dfanDomain ? null : _detect2dfanDomain,
                icon: _isDetecting2dfanDomain
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search, size: 16),
                label: Text(_isDetecting2dfanDomain ? '检测中...' : '检测可用域名', style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _detect2dfanDomain() async {
    setState(() => _isDetecting2dfanDomain = true);
    try {
      final service = ref.read(fan2dServiceProvider);
      final domain = await service.detectAndSaveDomain();
      if (mounted) {
        _domain2dfanController.text = domain;
        AppTheme.showGlassToast(context, message: '检测成功: $domain', icon: Icons.check_circle, iconColor: AppTheme.successColor);
      }
    } catch (e) {
      if (mounted) AppTheme.showGlassToast(context, message: '检测失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
    } finally {
      if (mounted) setState(() => _isDetecting2dfanDomain = false);
    }
  }

  Widget _buildDomainInput({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 11),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildCookieSection() {
    return _buildSection(
      title: 'Cookie 设置',
      icon: Icons.cookie_outlined,
      children: [
        const Text(
          '部分网站需要登录才能查看内容，请从浏览器中复制 Cookie 粘贴到对应网站的输入框中',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildCookieInput(
          label: 'ACG嘤嘤怪 (acgyyg.ru)',
          controller: _cookieAcgyingController,
          hint: '登录 acgyyg.ru 后复制 Cookie',
        ),
        const SizedBox(height: 12),
        _buildCookieInput(
          label: '飞雪ACG (feixueacg.org)',
          controller: _cookieFeixueController,
          hint: '登录 feixueacg.org 后复制 Cookie',
        ),
        const SizedBox(height: 12),
        _buildCookieInput(
          label: '微咔ACG (vikacg.com) - Authorization',
          controller: _cookieVikacgController,
          hint: '输入 Authorization Token（如 Bearer xxx）',
        ),
        const SizedBox(height: 8),
        Text(
          'ACG嘤嘤怪/飞雪ACG 获取方法：浏览器按F12 → Network → 刷新页面 → 点击第一个请求 → 复制Request Headers中的Cookie值',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          '微咔ACG 获取方法：浏览器按F12 → Network → 点击任意请求 → 复制Request Headers中的Authorization值',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildCookieInput({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 11),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildXpathSection() {
    return _buildSection(
      title: '自定义解析器 (XPath)',
      icon: Icons.code_outlined,
      children: [
        Text(
          '当内置解析器无法覆盖新站点时，可通过配置 XPath 来实现自定义解析。',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '在浏览器中按 F12 打开开发者工具，右键元素 → Copy → Copy XPath 即可获取。',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
        ),
        const SizedBox(height: 16),
        if (_xpathConfigs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: Text(
              '暂无自定义解析器配置',
              style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 13),
            ),
          ),
        ..._xpathConfigs.asMap().entries.map((entry) {
          final idx = entry.key;
          final cfg = entry.value;
          return _buildXpathConfigCard(idx, cfg);
        }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addXpathConfig,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加站点', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildXpathConfigCard(int index, Map<String, String> cfg) {
    final prefs = ref.read(sharedPreferencesProvider);
    final userFont = prefs.getString('font_family') ?? '';
    final domain = cfg['domain'] ?? '';
    final name = cfg['name'] ?? '';
    final fields = [
      MapEntry('title', '标题'),
      MapEntry('cookie', 'Cookie'),
      MapEntry('description', '内容/介绍'),
      MapEntry('images', '图片'),
      MapEntry('downloadLinks', '下载链接'),
      MapEntry('tags', '标签'),
      MapEntry('signUnzipCode', '签名/解压码'),
      MapEntry('version', '版本'),
      MapEntry('changelog', '更新日志'),
      MapEntry('features', '游戏特点'),
    ];

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withValues(alpha: 0.3),
      border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.language, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name.isNotEmpty ? '$name ($domain)' : domain,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  color: AppTheme.primaryColor,
                  tooltip: '编辑',
                  onPressed: () => _editXpathConfig(index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: AppTheme.errorColor,
                  tooltip: '删除',
                  onPressed: () => _removeXpathConfig(index),
                ),
              ],
            ),
          ),
          ...fields.map((f) {
            final value = cfg[f.key];
            if (value == null || value.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      f.value,
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textPrimary,
                      fontFamily: userFont.isNotEmpty ? userFont : 'monospace',
                    ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _addXpathConfig() {
    showGlassDialog(
      context: context,
      child: _XpathConfigDialog(
        onSave: (config) {
          setState(() {
            _xpathConfigs.add(config);
          });
          _saveXpathConfigs();
        },
      ),
    );
  }

  void _editXpathConfig(int index) {
    showGlassDialog(
      context: context,
      child: _XpathConfigDialog(
        initialConfig: _xpathConfigs[index],
        onSave: (config) {
          setState(() {
            _xpathConfigs[index] = config;
          });
          _saveXpathConfigs();
        },
      ),
    );
  }

  void _removeXpathConfig(int index) {
    setState(() {
      _xpathConfigs.removeAt(index);
    });
    _saveXpathConfigs();
  }

  Widget _buildNoImageModeSection() {
    return _buildSection(
      title: '无图模式',
      icon: Icons.image_not_supported_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('开启无图模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    '开启后，游戏列表中的海报图片将不再显示，但详情页仍可正常查看图片',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Switch(
              value: _noImageMode,
              onChanged: (value) async {
                setState(() => _noImageMode = value);
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool(AppSettings.noImageModeKey, value);
                ref.read(noImageModeProvider.notifier).state = value;
              },
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFontSection() {
    return _buildSection(
      title: '字体设置',
      icon: Icons.font_download_outlined,
      children: [
        Row(
          children: [
            const Text(
              '字体',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
                ),
                child: DropdownButton<String>(
                  value: _selectedFont.isEmpty ? null : _selectedFont,
                  hint: const Text('默认 (Microsoft YaHei)', style: TextStyle(fontSize: 14)),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppTheme.surfaceColor,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('默认 (Microsoft YaHei)', style: TextStyle(fontSize: 14))),
                    const DropdownMenuItem(value: 'MapleMonoNL-NF-CN', child: Text('MapleMonoNL-NF-CN', style: TextStyle(fontSize: 14, fontFamily: 'MapleMonoNL-NF-CN'))),
                    ..._getCustomFontItems(),
                  ],
                  onChanged: (v) => setState(() => _selectedFont = v ?? ''),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _importFont,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('导入 TTF 字体', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              '字号',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_fontSize.toStringAsFixed(1)} px',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () {
                      if (_fontSize > 10.0) {
                        setState(() => _fontSize -= 0.5);
                      }
                    },
                    color: AppTheme.textSecondary,
                    tooltip: '减小字号',
                  ),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 10.0,
                      max: 24.0,
                      divisions: 28,
                      label: '${_fontSize.toStringAsFixed(1)} px',
                      onChanged: (value) {
                        setState(() => _fontSize = value);
                      },
                      activeColor: AppTheme.primaryColor,
                      inactiveColor: AppTheme.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () {
                      if (_fontSize < 24.0) {
                        setState(() => _fontSize += 0.5);
                      }
                    },
                    color: AppTheme.textSecondary,
                    tooltip: '增大字号',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '预览 AaBbCc 中文 123',
                style: TextStyle(
                  fontSize: _fontSize,
                  fontFamily: _selectedFont.isNotEmpty ? _selectedFont : null,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              '详情页文章字号',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_detailFontSize.toStringAsFixed(1)} px',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () {
                      if (_detailFontSize > 10.0) {
                        setState(() => _detailFontSize -= 0.5);
                      }
                    },
                    color: AppTheme.textSecondary,
                    tooltip: '减小字号',
                  ),
                  Expanded(
                    child: Slider(
                      value: _detailFontSize,
                      min: 10.0,
                      max: 24.0,
                      divisions: 28,
                      label: '${_detailFontSize.toStringAsFixed(1)} px',
                      onChanged: (value) {
                        setState(() => _detailFontSize = value);
                      },
                      activeColor: AppTheme.primaryColor,
                      inactiveColor: AppTheme.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () {
                      if (_detailFontSize < 24.0) {
                        setState(() => _detailFontSize += 0.5);
                      }
                    },
                    color: AppTheme.textSecondary,
                    tooltip: '增大字号',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '预览 AaBbCc 中文 123',
                style: TextStyle(
                  fontSize: _detailFontSize,
                  fontFamily: _selectedFont.isNotEmpty ? _selectedFont : null,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '选择后需点击"保存"并重启应用生效',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _getCustomFontItems() {
    final prefs = ref.read(sharedPreferencesProvider);
    final existingFonts = prefs.getString('custom_fonts') ?? '';
    if (existingFonts.isEmpty) return [];

    return existingFonts.split(',').where((f) => f.isNotEmpty).map((fontPath) {
      final fontName = fontPath.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');
      return DropdownMenuItem(
        value: fontName,
        child: Text(fontName, style: const TextStyle(fontSize: 14)),
      );
    }).toList();
  }

  Future<void> _importFont() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择 TTF 字体文件',
      type: FileType.custom,
      allowedExtensions: ['ttf'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final fileName = result.files.first.name;

    final fontsDir = Directory('${await AppPaths.rootDir}${Platform.pathSeparator}fonts');
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }

    final targetPath = '${fontsDir.path}${Platform.pathSeparator}$fileName';
    await file.copy(targetPath);

    final fontName = fileName.replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');

    final prefs = ref.read(sharedPreferencesProvider);
    final existingFonts = prefs.getString('custom_fonts') ?? '';
    final fonts = existingFonts.isEmpty ? <String>[] : existingFonts.split(',');
    if (!fonts.contains(targetPath)) {
      fonts.add(targetPath);
      await prefs.setString('custom_fonts', fonts.join(','));
    }

    setState(() {
      _selectedFont = fontName;
    });

    if (mounted) {
      AppTheme.showGlassToast(context, message: '字体 "$fontName" 已导入，保存设置后重启应用生效');
    }
  }

  Widget _buildContextMenuSection() {
    return _buildSection(
      title: '右键菜单管理',
      icon: Icons.menu,
      children: [
        const Text('管理游戏列表右键菜单中显示的选项', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _showContextMenuManager,
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('打开菜单管理'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
              foregroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlacklistSection() {
    return _buildSection(
      title: '黑名单管理',
      icon: Icons.block,
      children: [
        const Text('管理扫描时忽略的游戏路径', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _showBlacklistDialog,
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('编辑黑名单'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFA000).withValues(alpha: 0.15),
              foregroundColor: const Color(0xFFFFA000),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    const currentVersion = '1.3.9';

    return _buildSection(
      title: '关于',
      icon: Icons.info_outline,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('应用名称', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('HGame Manager', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 32),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('当前版本', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('v$currentVersion', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(width: 32),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('描述', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('本地游戏管理工具', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
              ],
            ),
            const SizedBox(width: 32),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('作者', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse('https://space.bilibili.com/345721873');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      '临渊',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _testProxy() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('proxy_mode', _proxyMode);
    await prefs.setString('proxy_url', _proxyUrlController.text);

    final customUrl = _proxyTestUrlController.text.trim();
    String testUrl;
    String displayLabel;

    if (customUrl.isNotEmpty) {
      if (!customUrl.startsWith('http://') && !customUrl.startsWith('https://')) {
        testUrl = 'https://$customUrl';
      } else {
        testUrl = customUrl;
      }
      displayLabel = testUrl;
    } else {
      testUrl = 'https://feixueacg.org/';
      displayLabel = 'feixueacg.org';
    }

    setState(() {
      _isTestingProxy = true;
      _proxyTestResult = null;
    });

    final ok = await testProxyConnection(testUrl);

    if (mounted) {
      setState(() {
        _isTestingProxy = false;
        _proxyTestResult = ok ? '连接成功 ($displayLabel)' : '连接失败，请检查代理设置';
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = ref.read(sharedPreferencesProvider);

    await prefs.setString('library_path', jsonEncode(_libraryPaths));
    await prefs.setString('sorted_paths', jsonEncode(_sortedPaths));
    await prefs.setString('proxy_mode', _proxyMode);
    await prefs.setString('proxy_url', _proxyUrlController.text);
    await prefs.setString('proxy_test_url', _proxyTestUrlController.text.trim());
    await prefs.setString('cookie_acgying', _cookieAcgyingController.text.trim());
    await prefs.setString('cookie_feixue', _cookieFeixueController.text.trim());
    await prefs.setString('cookie_vikacg', _cookieVikacgController.text.trim());
    await prefs.setString('domain_acgying', _domainAcgyingController.text.trim());
    await prefs.setString('domain_feixue', _domainFeixueController.text.trim());
    await prefs.setString('domain_vikacg', _domainVikacgController.text.trim());
    await prefs.setString('domain_2dfan', _domain2dfanController.text.trim());
    await prefs.setString('webdav_url', _webdavUrlController.text.trim());
    await prefs.setString('webdav_username', _webdavUsernameController.text.trim());
    await prefs.setString('webdav_password', _webdavPasswordController.text);
    await prefs.setString('font_family', _selectedFont);
    await prefs.setDouble('font_size', _fontSize);
    await prefs.setDouble('detail_font_size', _detailFontSize);
    await prefs.setBool(AppSettings.noImageModeKey, _noImageMode);
    await prefs.setBool(AppSettings.keepPlayedInGamesKey, _keepPlayedInGames);

    if (!mounted) return;

    ref.invalidate(fontSizeProvider);
    ref.invalidate(detailFontSizeProvider);
    ref.invalidate(pageSizeProvider);

    await HtmlScraper.reloadCustomDomains();

    if (mounted) {
      AppTheme.showGlassToast(context, message: '设置已保存');
    }
  }

  void _showBlacklistDialog() {
    showGlassDialog(
      context: context,
      child: _BlacklistDialog(),
    );
  }

  void _showContextMenuManager() {
    showDialog(
      context: context,
      builder: (context) => const ContextMenuManagerDialog(),
    );
  }

  Future<void> _scanNow() async {
    if (_libraryPaths.isEmpty) {
      AppTheme.showGlassToast(context, message: '请先配置游戏库目录', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      return;
    }

    await _saveSettings();

    try {
      final scanner = ref.read(gameScannerServiceProvider);
      final ignoreFolders = _getIgnoreFolders('scan_ignore_folders');
      final blacklistStr = ref.read(sharedPreferencesProvider).getString('game_blacklist') ?? '';
      final blacklistPaths = blacklistStr.split('\n').where((s) => s.trim().isNotEmpty).toList();
      await scanner.scanMultipleLibraries(_libraryPaths, ignoreFolders: ignoreFolders, blacklistPaths: blacklistPaths);

      ref.invalidate(allGamesProvider);

      if (mounted) {
        AppTheme.showGlassToast(context, message: '扫描完成');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '扫描失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Widget _buildLocalBackupSection() {
    return _buildSection(
      title: '本地备份',
      icon: Icons.folder_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportLocalBackup,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导出备份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _importLocalBackup,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导入备份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.warningColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWebdavSection() {
    return _buildSection(
      title: 'WebDAV 云备份',
      icon: Icons.cloud_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoadingBackups ? null : _showBackupList,
                icon: _isLoadingBackups
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_queue, size: 18),
                label: const Text('查看备份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _backupToWebdav,
                icon: _isBackingUp
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.backup, size: 18),
                label: const Text('备份数据'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.warningColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildWebdavTextField(
          controller: _webdavUrlController,
          label: '服务地址',
          hint: 'https://your-webdav-server.com/remote.php/dav/files/username/',
          icon: Icons.link,
        ),
        const SizedBox(height: 12),
        _buildWebdavTextField(
          controller: _webdavUsernameController,
          label: '用户名',
          hint: 'WebDAV 账号',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        _buildWebdavPasswordField(),
      ],
    );
  }

  Widget _buildWebdavTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildWebdavPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('密码', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _webdavPasswordController,
          obscureText: !_webdavPasswordVisible,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'WebDAV 密码',
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(Icons.lock_outline, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
            suffixIcon: IconButton(
              icon: Icon(
                _webdavPasswordVisible ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
              ),
              onPressed: () => setState(() => _webdavPasswordVisible = !_webdavPasswordVisible),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _exportLocalBackup() async {
    final dbPath = await DatabaseHelper.getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '数据库文件不存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
      return;
    }

    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final result = await FilePicker.saveFile(
      dialogTitle: '导出备份',
      fileName: 'hgame_manager_$timestamp.zip',
    );

    if (result == null) return;

    try {
      final settingsPath = await AppPaths.settingsFile;
      final settingsFile = File(settingsPath);

      final archive = Archive();
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));
      if (await settingsFile.exists()) {
        final settingsBytes = await settingsFile.readAsBytes();
        archive.addFile(ArchiveFile('settings.json', settingsBytes.length, settingsBytes));
      }

      final zipBytes = ZipEncoder().encode(archive);
      await File(result).writeAsBytes(zipBytes);

      if (mounted) {
        AppTheme.showGlassToast(context, message: '导出成功: $result');
      }
    } catch (e) {
      debugPrint('Export backup error: $e');
      if (mounted) {
        AppTheme.showGlassToast(context, message: '导出失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _importLocalBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('确认导入备份', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('导入备份将替换当前数据库和设置。导入后需要重启应用才能生效。', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定导入', style: TextStyle(color: AppTheme.warningColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      allowMultiple: false,
      allowedExtensions: ['zip', 'db'],
    );

    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    try {
      final dbPath = await DatabaseHelper.getDatabasePath();
      final settingsPath = await AppPaths.settingsFile;

      if (sourcePath.endsWith('.zip')) {
        final zipBytes = await File(sourcePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(zipBytes);

        await DatabaseHelper.close();

        for (final file in archive) {
          if (file.name == 'database.db') {
            final dbFile = File(dbPath);
            if (await dbFile.exists()) await dbFile.delete();
            await dbFile.writeAsBytes(file.content as List<int>);
          } else if (file.name == 'settings.json') {
            final settingsFile = File(settingsPath);
            await settingsFile.writeAsBytes(file.content as List<int>);
            await ref.read(sharedPreferencesProvider).reload();
          }
        }
      } else {
        await DatabaseHelper.close();
        final dbFile = File(dbPath);
        if (await dbFile.exists()) await dbFile.delete();
        await File(sourcePath).copy(dbPath);
      }

      if (mounted) {
        AppTheme.showGlassToast(context, message: '导入成功！请重启应用使数据生效。');
      }
    } catch (e) {
      debugPrint('Import local backup error: $e');
      if (mounted) {
        AppTheme.showGlassToast(context, message: '导入失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  void _showBackupList() async {
    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '请先填写完整的 WebDAV 配置', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return;
    }

    setState(() => _isLoadingBackups = true);

    final service = ref.read(webdavServiceProvider);
    final files = await service.listBackups(
      serverUrl: url,
      username: username,
      password: password,
    );

    if (mounted) {
      setState(() {
        _isLoadingBackups = false;
        _backupFiles = files;
      });
      _showBackupDialog();
    }
  }

  void _showBackupDialog() {
    final files = _backupFiles ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusLarge)),
        title: Row(
          children: [
            const Icon(Icons.cloud_queue, color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 8),
            const Text('云端备份列表', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () {
                Navigator.of(ctx).pop();
                _showBackupList();
              },
              tooltip: '刷新',
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 780,
          child: files.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('暂无备份文件', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              : SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 16,
                    headingTextStyle: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    dataTextStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    columns: const [
                      DataColumn(label: Text('文件名')),
                      DataColumn(label: Text('大小')),
                      DataColumn(label: Text('备份日期')),
                      DataColumn(label: Text('操作'), numeric: false),
                    ],
                    rows: files.where((f) => f.sizeBytes > 0).map((f) {
                      return DataRow(cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(
                              f.name,
                              softWrap: true,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(f.sizeFormatted)),
                        DataCell(Text(f.modifiedDate != null
                            ? '${f.modifiedDate!.year}-${f.modifiedDate!.month.toString().padLeft(2, '0')}-${f.modifiedDate!.day.toString().padLeft(2, '0')} ${f.modifiedDate!.hour.toString().padLeft(2, '0')}:${f.modifiedDate!.minute.toString().padLeft(2, '0')}'
                            : '-')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MiniIconButton(
                                icon: Icons.download,
                                tooltip: '下载',
                                color: AppTheme.primaryColor,
                                onTap: () => _downloadBackupFile(f.name),
                              ),
                              const SizedBox(width: 4),
                              _MiniIconButton(
                                icon: Icons.file_download_outlined,
                                tooltip: '导入',
                                color: AppTheme.successColor,
                                onTap: () => _importBackupFile(f.name),
                              ),
                              const SizedBox(width: 4),
                              _MiniIconButton(
                                icon: Icons.delete_outline,
                                tooltip: '删除',
                                color: AppTheme.errorColor,
                                onTap: () => _deleteBackupWithConfirm(f.name),
                              ),
                            ],
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _backupToWebdav() async {
    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '请先填写完整的 WebDAV 配置', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return;
    }

    setState(() => _isBackingUp = true);

    try {
      final dbPath = await DatabaseHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        if (mounted) {
          setState(() => _isBackingUp = false);
          AppTheme.showGlassToast(context, message: '数据库文件不存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }

      final settingsPath = await AppPaths.settingsFile;
      final settingsFile = File(settingsPath);

      final archive = Archive();
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));
      if (await settingsFile.exists()) {
        final settingsBytes = await settingsFile.readAsBytes();
        archive.addFile(ArchiveFile('settings.json', settingsBytes.length, settingsBytes));
      }
      final zipBytes = ZipEncoder().encode(archive);

      final tempDir = Directory.systemTemp;
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final tempZipPath = '${tempDir.path}${Platform.pathSeparator}hgame_manager_$timestamp.zip';
      await File(tempZipPath).writeAsBytes(zipBytes);

      final service = ref.read(webdavServiceProvider);
      final ok = await service.uploadBackup(
        serverUrl: url,
        username: username,
        password: password,
        localFilePath: tempZipPath,
      );

      final tempFile = File(tempZipPath);
      if (await tempFile.exists()) await tempFile.delete();

      if (mounted) {
        setState(() => _isBackingUp = false);
        if (ok) {
          AppTheme.showGlassToast(context, message: '备份成功');
        } else {
          AppTheme.showGlassToast(context, message: '备份失败，请检查配置和服务器状态', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
      }
    } catch (e) {
      debugPrint('WebDAV backup error: $e');
      if (mounted) {
        setState(() => _isBackingUp = false);
        AppTheme.showGlassToast(context, message: '备份失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _downloadBackupFile(String fileName) async {
    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择保存位置');
    if (result == null) return;

    final localPath = '$result${Platform.pathSeparator}$fileName';
    final service = ref.read(webdavServiceProvider);
    final ok = await service.downloadBackup(
      serverUrl: url,
      username: username,
      password: password,
      remoteFileName: fileName,
      localPath: localPath,
    );

    if (mounted) {
      if (ok) {
        AppTheme.showGlassToast(context, message: '下载成功: $localPath');
      } else {
        AppTheme.showGlassToast(context, message: '下载失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _importBackupFile(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('确认导入备份', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '导入备份将替换当前数据库和设置。导入后需要重启应用才能生效。\n\n确定要导入 "$fileName" 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定导入', style: TextStyle(color: AppTheme.warningColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    final dbPath = await DatabaseHelper.getDatabasePath();
    final service = ref.read(webdavServiceProvider);
    final tempPath = await service.importBackup(
      serverUrl: url,
      username: username,
      password: password,
      remoteFileName: fileName,
      localDbPath: dbPath,
    );

    bool ok = false;
    if (tempPath != null) {
      try {
        final tempFile = File(tempPath);
        if (!await tempFile.exists()) {
          if (mounted) {
            AppTheme.showGlassToast(context, message: '导入失败：临时文件不存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
          }
          return;
        }

        await DatabaseHelper.close();

        if (fileName.endsWith('.zip')) {
          final zipBytes = await tempFile.readAsBytes();
          final archive = ZipDecoder().decodeBytes(zipBytes);

          for (final file in archive) {
            if (file.name == 'database.db') {
              final dbFile = File(dbPath);
              if (await dbFile.exists()) await dbFile.delete();
              await dbFile.writeAsBytes(file.content as List<int>);
            } else if (file.name == 'settings.json') {
              final settingsPath = await AppPaths.settingsFile;
              final settingsFile = File(settingsPath);
              await settingsFile.writeAsBytes(file.content as List<int>);
              await ref.read(sharedPreferencesProvider).reload();
            }
          }
        } else {
          final dbFile = File(dbPath);
          if (await dbFile.exists()) await dbFile.delete();
          await tempFile.copy(dbPath);
        }

        if (await tempFile.exists()) await tempFile.delete();

        ok = true;
      } catch (e) {
        debugPrint('Failed to import backup: $e');
        try {
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    }

    if (mounted) {
      if (ok) {
        AppTheme.showGlassToast(context, message: '导入成功！请重启应用使数据生效。');
      } else {
        AppTheme.showGlassToast(context, message: '导入失败', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _deleteBackupWithConfirm(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('确认删除', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定要删除云端备份 "$fileName" 吗？此操作不可撤销。', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final url = _webdavUrlController.text.trim();
    final username = _webdavUsernameController.text.trim();
    final password = _webdavPasswordController.text;

    final service = ref.read(webdavServiceProvider);
    final ok = await service.deleteBackup(
      serverUrl: url,
      username: username,
      password: password,
      remoteFileName: fileName,
    );

    if (mounted && ok) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showBackupList();
    }
  }
}

class _SidebarCategory {
  final String label;
  final IconData icon;
  final List<String> items;

  const _SidebarCategory({
    required this.label,
    required this.icon,
    required this.items,
  });
}

class _BlacklistDialog extends ConsumerStatefulWidget {
  const _BlacklistDialog();

  @override
  ConsumerState<_BlacklistDialog> createState() => _BlacklistDialogState();
}

class _BlacklistDialogState extends ConsumerState<_BlacklistDialog> {
  List<String> _paths = [];

  @override
  void initState() {
    super.initState();
    _loadBlacklist();
  }

  void _loadBlacklist() {
    final prefs = ref.read(sharedPreferencesProvider);
    final str = prefs.getString('game_blacklist') ?? '';
    _paths = str.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _removePath(int index) async {
    setState(() {
      _paths.removeAt(index);
    });
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('game_blacklist', _paths.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.block, color: Color(0xFFFFA000), size: 22),
                const SizedBox(width: 12),
                const Text(
                  '黑名单管理',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '黑名单中的路径在扫描游戏库时将被跳过，不会自动入库',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _paths.isEmpty
                  ? Center(
                      child: Text(
                        '黑名单为空',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _paths.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppTheme.borderColor.withValues(alpha: 0.2),
                      ),
                      itemBuilder: (_, index) {
                        final path = _paths[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: const Icon(Icons.folder_outlined, size: 18, color: AppTheme.textSecondary),
                          title: Text(
                            path,
                            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16, color: AppTheme.errorColor),
                            tooltip: '移除',
                            onPressed: () => _removePath(index),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _XpathConfigDialog extends StatefulWidget {
  final Map<String, String>? initialConfig;
  final void Function(Map<String, String>) onSave;

  const _XpathConfigDialog({this.initialConfig, required this.onSave});

  @override
  State<_XpathConfigDialog> createState() => _XpathConfigDialogState();
}

class _XpathConfigDialogState extends State<_XpathConfigDialog> {
  late final TextEditingController _domainController;
  late final TextEditingController _nameController;
  late final TextEditingController _cookieController;
  late final Map<String, TextEditingController> _fieldControllers;

  static const _fieldDefs = [
    MapEntry('title', '标题 XPath *'),
    MapEntry('description', '内容/介绍 XPath'),
    MapEntry('images', '图片 XPath (/@src)'),
    MapEntry('downloadLinks', '下载链接区域 XPath'),
    MapEntry('tags', '标签 XPath'),
    MapEntry('signUnzipCode', '签名/解压码区域 XPath'),
    MapEntry('version', '版本 XPath'),
    MapEntry('changelog', '更新日志 XPath'),
    MapEntry('features', '游戏特点 XPath'),
  ];

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig ?? {};
    _domainController = TextEditingController(text: cfg['domain'] ?? '');
    _nameController = TextEditingController(text: cfg['name'] ?? '');
    _cookieController = TextEditingController(text: cfg['cookie'] ?? '');
    _fieldControllers = {
      for (final def in _fieldDefs)
        def.key: TextEditingController(text: cfg[def.key] ?? ''),
    };
  }

  @override
  void dispose() {
    _domainController.dispose();
    _nameController.dispose();
    _cookieController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      AppTheme.showGlassToast(context, message: '请填写域名', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      return;
    }
    final titleXpath = _fieldControllers['title']!.text.trim();
    if (titleXpath.isEmpty) {
      AppTheme.showGlassToast(context, message: '请填写标题 XPath', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      return;
    }

    final config = <String, String>{
      'domain': domain,
      'name': _nameController.text.trim(),
    };
    for (final def in _fieldDefs) {
      final val = _fieldControllers[def.key]!.text.trim();
      if (val.isNotEmpty) {
        config[def.key] = val;
      }
    }

    final cookieVal = _cookieController.text.trim();
    if (cookieVal.isNotEmpty) {
      config['cookie'] = cookieVal;
    }

    widget.onSave(config);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialConfig != null;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 600,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.code_outlined, color: AppTheme.primaryColor, size: 22),
                const SizedBox(width: 12),
                Text(
                  isEdit ? '编辑解析器配置' : '添加解析器配置',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '填写站点域名和各字段的 XPath 表达式。带 * 的为必填项。',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField('域名 *', _domainController, '例如: newgameforum.com'),
                    const SizedBox(height: 12),
                    _buildTextField('站点名称', _nameController, '例如: 新游戏论坛 (可选)'),
                    const SizedBox(height: 12),
                    _buildTextField('Cookie (可选)', _cookieController, '粘贴浏览器 Cookie，刮削时携带'),
                    const SizedBox(height: 16),
                    ..._fieldDefs.map((def) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildTextField(def.value, _fieldControllers[def.key]!, 'XPath 表达式'),
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.primaryColor,
                  ),
                  child: Text(isEdit ? '保存' : '添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 11),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }
}
