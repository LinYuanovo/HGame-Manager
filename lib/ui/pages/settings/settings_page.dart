import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/proxy_client.dart';
import '../../theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _libraryPathController;
  late TextEditingController _sortedPathController;
  late TextEditingController _proxyUrlController;
  late TextEditingController _cookieAcgyingController;
  late TextEditingController _cookieFeixueController;
  late TextEditingController _cookieVikacgController;
  late TextEditingController _customSeriesController;
  String _proxyMode = 'none';
  bool _isTestingProxy = false;
  String? _proxyTestResult;
  String _selectedFont = '';
  double _fontSize = 14.0;
  double _detailFontSize = 14.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final prefs = ref.read(sharedPreferencesProvider);
    final libraryPath = prefs.getString('library_path') ?? '';
    final sortedPath = prefs.getString('sorted_path') ?? '';
    final proxyMode = prefs.getString('proxy_mode') ?? 'none';
    final proxyUrl = prefs.getString('proxy_url') ?? '';
    final font = prefs.getString('font_family') ?? '';
    final fontSize = prefs.getDouble('font_size') ?? 14.0;
    final detailFontSize = prefs.getDouble('detail_font_size') ?? 14.0;

    final cookieAcgying = prefs.getString('cookie_acgying') ?? '';
    final cookieFeixue = prefs.getString('cookie_feixue') ?? '';
    final cookieVikacg = prefs.getString('cookie_vikacg') ?? '';

    _libraryPathController = TextEditingController(text: libraryPath);
    _sortedPathController = TextEditingController(text: sortedPath);
    _proxyUrlController = TextEditingController(text: proxyUrl);
    _cookieAcgyingController = TextEditingController(text: cookieAcgying);
    _cookieFeixueController = TextEditingController(text: cookieFeixue);
    _cookieVikacgController = TextEditingController(text: cookieVikacg);
    _customSeriesController = TextEditingController();
    _proxyMode = proxyMode;
    _selectedFont = font;
    _fontSize = fontSize;
    _detailFontSize = detailFontSize;
  }

  @override
  void dispose() {
    _libraryPathController.dispose();
    _sortedPathController.dispose();
    _proxyUrlController.dispose();
    _cookieAcgyingController.dispose();
    _cookieFeixueController.dispose();
    _cookieVikacgController.dispose();
    _customSeriesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          _buildActionsSection(),
          const SizedBox(height: 32),
          _buildLibrarySection(),
          const SizedBox(height: 24),
          _buildIgnoreFoldersSection(),
          const SizedBox(height: 24),
          _buildSeriesSection(),
          const SizedBox(height: 24),
          _buildProxySection(),
          const SizedBox(height: 24),
          _buildCookieSection(),
          const SizedBox(height: 24),
          _buildFontSection(),
          const SizedBox(height: 24),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          Icons.settings,
          color: AppTheme.primaryColor,
          size: 28,
        ),
        const SizedBox(width: 12),
        ShaderMask(
          shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
          child: const Text(
            '设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildPathSetting({
    required String label,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onBrowse,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(
                    color: AppTheme.textSecondary.withValues(alpha:0.2),
                  ),
                ),
                child: Text(
                  controller.text.isEmpty ? hint : controller.text,
                  style: TextStyle(
                    color: controller.text.isEmpty
                        ? AppTheme.textSecondary.withValues(alpha:0.5)
                        : AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onBrowse,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor.withValues(alpha:0.15),
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                ),
              ),
              child: const Text('浏览'),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ],
    );
  }

  Widget _buildActionsSection() {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flash_on, color: AppTheme.accentColor, size: 22),
              SizedBox(width: 12),
              Text(
                '快捷操作',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.save,
                  label: '保存设置',
                  color: AppTheme.primaryColor,
                  onPressed: _saveSettings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.folder_open,
                  label: '扫描游戏库',
                  color: AppTheme.successColor,
                  onPressed: _scanNow,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.block,
                  label: '黑名单管理',
                  color: const Color(0xFFFFA000),
                  onPressed: _showBlacklistDialog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibrarySection() {
    return _buildSection(
      title: '游戏库设置',
      icon: Icons.folder_outlined,
      children: [
        _buildPathSetting(
          label: '游戏库目录',
          hint: '选择包含 source_url.txt 的游戏文件夹',
          controller: _libraryPathController,
          onBrowse: () => _selectDirectory(_libraryPathController),
        ),
        const SizedBox(height: 20),
        _buildPathSetting(
          label: '整理目录 (Sorted)',
          hint: '刮削成功后，游戏文件夹会自动移动到此目录',
          controller: _sortedPathController,
          onBrowse: () => _selectDirectory(_sortedPathController),
          trailing: _sortedPathController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: AppTheme.errorColor),
                  onPressed: () {
                    setState(() {
                      _sortedPathController.text = '';
                    });
                  },
                  tooltip: '清除',
                )
              : null,
        ),
        if (_sortedPathController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '刮削完成后自动将游戏移动到: ${_sortedPathController.text}\\{游戏名}',
            style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildIgnoreFoldersSection() {
    return _buildSection(
      title: '忽略文件夹',
      icon: Icons.folder_off_outlined,
      children: [
        // Scan ignore folders
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
        // Scrape ignore folders
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
            if (_proxyTestResult != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  _proxyTestResult!,
                  style: TextStyle(
                    color: _proxyTestResult!.contains('成功') ? AppTheme.successColor : AppTheme.errorColor,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
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
                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha:0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium), borderSide: BorderSide(color: AppTheme.textSecondary.withValues(alpha:0.2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
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
          label: '微咔ACG (vikacg.com)',
          controller: _cookieVikacgController,
          hint: '登录 vikacg.com 后复制 Cookie',
        ),
        const SizedBox(height: 8),
        Text(
          '获取方法：浏览器按F12 → Network → 刷新页面 → 点击第一个请求 → 复制Request Headers中的Cookie值',
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
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontFamily: 'monospace'),
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
                  color: Colors.white.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(color: AppTheme.textSecondary.withValues(alpha:0.2)),
                ),
                child: DropdownButton<String>(
                  value: _selectedFont.isEmpty ? null : _selectedFont,
                  hint: const Text('默认 (Microsoft YaHei)', style: TextStyle(fontSize: 14)),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppTheme.surfaceColor,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('默认 (Microsoft YaHei)', style: TextStyle(fontSize: 14))),
                    DropdownMenuItem(value: 'MapleMonoNL-NF-CN', child: Text('MapleMonoNL-NF-CN', style: TextStyle(fontSize: 14, fontFamily: 'MapleMonoNL-NF-CN'))),
                  ],
                  onChanged: (v) => setState(() => _selectedFont = v ?? ''),
                ),
              ),
            ),
          ],
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
                color: AppTheme.primaryColor.withValues(alpha:0.15),
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
                      inactiveColor: AppTheme.textSecondary.withValues(alpha:0.2),
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
                color: AppTheme.backgroundColor.withValues(alpha:0.3),
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
                color: AppTheme.primaryColor.withValues(alpha:0.15),
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
                      inactiveColor: AppTheme.textSecondary.withValues(alpha:0.2),
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
                color: AppTheme.backgroundColor.withValues(alpha:0.3),
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
          '选择后需点击"保存设置"并重启应用生效',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha:0.6), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSeriesSection() {
    final defaultTypes = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS'];
    final customTypes = _getCustomSeriesTypes();

    return _buildSection(
      title: '系列类型',
      icon: Icons.category_outlined,
      children: [
        Text('默认系列类型（不可删除）', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: defaultTypes.map((type) => Chip(
            label: Text(type, style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
            side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )).toList(),
        ),
        if (customTypes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('自定义系列类型', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: customTypes.map((type) => Chip(
              label: Text(type, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
              backgroundColor: AppTheme.backgroundColor.withValues(alpha: 0.3),
              side: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onDeleted: () => _removeCustomSeriesType(type),
            )).toList(),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customSeriesController,
                decoration: InputDecoration(
                  hintText: '添加系列类型',
                  hintStyle: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: AppTheme.backgroundColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                onSubmitted: (_) => _addCustomSeriesType(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.add_circle, color: AppTheme.primaryColor, size: 22),
              onPressed: () => _addCustomSeriesType(),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _getCustomSeriesTypes() {
    final prefs = ref.read(sharedPreferencesProvider);
    final str = prefs.getString('custom_series_types') ?? '';
    return str.split(',').where((s) => s.trim().isNotEmpty).toList();
  }

  void _addCustomSeriesType() {
    final type = _customSeriesController.text.trim().toUpperCase();
    if (type.isEmpty) return;
    final defaultTypes = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS'];
    if (defaultTypes.contains(type)) return;
    final types = _getCustomSeriesTypes();
    if (!types.contains(type)) {
      types.add(type);
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString('custom_series_types', types.join(','));
    }
    _customSeriesController.clear();
    setState(() {});
  }

  void _removeCustomSeriesType(String type) {
    final types = _getCustomSeriesTypes();
    types.remove(type);
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString('custom_series_types', types.join(','));
    setState(() {});
  }

  Widget _buildAboutSection() {
    const currentVersion = '1.0.0';

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
          ],
        ),
      ],
    );
  }

  Future<void> _selectDirectory(TextEditingController controller) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: '选择文件夹',
      initialDirectory: controller.text.isNotEmpty ? controller.text : null,
    );
    if (result != null) {
      setState(() {
        controller.text = result;
      });
    }
  }

  Future<void> _testProxy() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('proxy_mode', _proxyMode);
    await prefs.setString('proxy_url', _proxyUrlController.text);

    setState(() {
      _isTestingProxy = true;
      _proxyTestResult = null;
    });

    final ok = await testProxyConnection('https://feixueacg.org/');

    if (mounted) {
      setState(() {
        _isTestingProxy = false;
        _proxyTestResult = ok ? '连接成功 (feixueacg.org)' : '连接失败，请检查代理设置';
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = ref.read(sharedPreferencesProvider);

    await prefs.setString('library_path', _libraryPathController.text);
    await prefs.setString('sorted_path', _sortedPathController.text);
    await prefs.setString('proxy_mode', _proxyMode);
    await prefs.setString('proxy_url', _proxyUrlController.text);
    await prefs.setString('cookie_acgying', _cookieAcgyingController.text.trim());
    await prefs.setString('cookie_feixue', _cookieFeixueController.text.trim());
    await prefs.setString('cookie_vikacg', _cookieVikacgController.text.trim());
    await prefs.setString('font_family', _selectedFont);
    await prefs.setDouble('font_size', _fontSize);
    await prefs.setDouble('detail_font_size', _detailFontSize);

    ref.invalidate(fontSizeProvider);
    ref.invalidate(detailFontSizeProvider);
    ref.invalidate(pageSizeProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  void _showBlacklistDialog() {
    showGlassDialog(
      context: context,
      child: _BlacklistDialog(),
    );
  }

  Future<void> _scanNow() async {
    if (_libraryPathController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先配置游戏库目录'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    await _saveSettings();

    try {
      final scanner = ref.read(gameScannerServiceProvider);
      final ignoreFolders = _getIgnoreFolders('scan_ignore_folders');
      final blacklistStr = ref.read(sharedPreferencesProvider).getString('game_blacklist') ?? '';
      final blacklistPaths = blacklistStr.split('\n').where((s) => s.trim().isNotEmpty).toList();
      await scanner.scanGameLibrary(_libraryPathController.text, ignoreFolders: ignoreFolders, blacklistPaths: blacklistPaths);

      ref.invalidate(allGamesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('扫描完成'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(
              color: color.withValues(alpha:0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  void _removePath(int index) {
    setState(() {
      _paths.removeAt(index);
    });
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString('game_blacklist', _paths.join('\n'));
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
