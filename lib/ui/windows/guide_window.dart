import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/utils/app_settings.dart';
import '../../core/utils/guide_window_state.dart';
import '../../core/utils/media_reference_parser.dart';
import '../theme/app_theme.dart';

/// 攻略浮窗子窗口入口。
///
/// desktop_multi_window 创建的子窗口会以新引擎运行 main()，
/// 入口参数固定为 {"multi_window", windowId, arguments}。
Future<void> runGuideWindow(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final windowId = args.length > 1 ? args[1] : '';
  Map<String, dynamic> arguments = {};
  if (args.length > 2 && args[2].isNotEmpty) {
    try {
      final decoded = jsonDecode(args[2]);
      if (decoded is Map<String, dynamic>) arguments = decoded;
    } catch (_) {}
  }

  final prefs = await AppSettings.load();
  await _loadCustomFonts(prefs);

  runApp(GuideWindowApp(
    windowId: windowId,
    arguments: arguments,
    prefs: prefs,
  ));
}

/// 与主窗口一致地加载自定义字体
Future<void> _loadCustomFonts(AppSettings prefs) async {
  final customFonts = prefs.getString('custom_fonts') ?? '';
  if (customFonts.isEmpty) return;
  for (final fontPath in customFonts.split(',')) {
    if (fontPath.isEmpty) continue;
    try {
      final fontFile = File(fontPath);
      if (await fontFile.exists()) {
        final fontName = fontPath
            .split(RegExp(r'[/\\]'))
            .last
            .replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');
        final fontData = await fontFile.readAsBytes();
        final fontLoader = FontLoader(fontName);
        fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
        await fontLoader.load();
      }
    } catch (e) {
      debugPrint('Failed to load custom font: $e');
    }
  }
}

class GuideWindowApp extends StatelessWidget {
  final String windowId;
  final Map<String, dynamic> arguments;
  final AppSettings prefs;

  const GuideWindowApp({
    super.key,
    required this.windowId,
    required this.arguments,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final fontFamily = prefs.getString('font_family') ?? '';
    final isDark = prefs.getString(AppSettings.themeModeKey) == 'dark';
    return MaterialApp(
      title: '攻略',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(fontFamily: fontFamily.isEmpty ? null : fontFamily),
      darkTheme: AppTheme.darkTheme(fontFamily: fontFamily.isEmpty ? null : fontFamily),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: GuideWindowPage(
        windowId: windowId,
        arguments: arguments,
        fontSize: prefs.getDouble('detail_font_size') ?? 14.0,
      ),
    );
  }
}

class GuideWindowPage extends StatefulWidget {
  final String windowId;
  final Map<String, dynamic> arguments;
  final double fontSize;

  const GuideWindowPage({
    super.key,
    required this.windowId,
    required this.arguments,
    required this.fontSize,
  });

  @override
  State<GuideWindowPage> createState() => _GuideWindowPageState();
}

class _GuideWindowPageState extends State<GuideWindowPage>
    with WindowListener {
  final _scrollController = ScrollController();

  GuideWindowState _state = GuideWindowState();
  String _title = '';
  String _content = '';
  String _gameKey = '';
  String _mainWindowId = '';
  bool _alwaysOnTop = false;
  bool _isMaximized = false;
  bool _closing = false;
  bool _settingsOpen = false;
  double _opacity = 1.0;
  double? _fontSizeOverride;
  Timer? _boundsSaveTimer;
  Timer? _scrollSaveTimer;

  double get _fontSize => _fontSizeOverride ?? widget.fontSize;

  @override
  void initState() {
    super.initState();
    _applyArguments(widget.arguments);
    _initWindow();
    _scrollController.addListener(_onScroll);
  }

  void _applyArguments(Map<String, dynamic> args) {
    _title = args['title'] as String? ?? '';
    _content = args['content'] as String? ?? '';
    _gameKey = args['gameKey'] as String? ?? '';
    _mainWindowId = args['mainWindowId'] as String? ?? '';
  }

  Future<void> _initWindow() async {
    _state = await GuideWindowState.load();
    _alwaysOnTop = _state.alwaysOnTop;
    _opacity = _state.opacity ?? 1.0;
    _fontSizeOverride = _state.fontSize;

    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(
      GuideWindowState.minWidth,
      GuideWindowState.minHeight,
    ));
    await windowManager.setSize(Size(
      _state.width ?? GuideWindowState.defaultWidth,
      _state.height ?? GuideWindowState.defaultHeight,
    ));
    if (_state.x != null && _state.y != null) {
      await windowManager.setPosition(Offset(_state.x!, _state.y!));
    } else {
      await windowManager.center();
    }
    if (_alwaysOnTop) {
      await windowManager.setAlwaysOnTop(true);
    }
    if (_opacity < 1.0) {
      await windowManager.setOpacity(_opacity);
    }

    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    try {
      await _registerMethodHandler();
    } catch (e) {
      // 消息通道注册失败不阻塞浮窗展示（仅失去主窗口联动能力）
      debugPrint('[GuideWindow] register method handler error: $e');
    }

    await windowManager.show();
    await windowManager.focus();

    if (mounted) setState(() {});
    _restoreScroll();
  }

  /// 注册来自主窗口的消息处理
  Future<void> _registerMethodHandler() async {
    if (widget.windowId.isEmpty) return;
    final controller = WindowController.fromWindowId(widget.windowId);
    await controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'updateContent':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          if (args != null) {
            setState(() {
              _title = args['title'] as String? ?? _title;
              _content = args['content'] as String? ?? '';
              _gameKey = args['gameKey'] as String? ?? _gameKey;
            });
            _restoreScroll();
          }
          return true;
        case 'scroll':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          final delta = (args?['delta'] as num?)?.toDouble() ?? 0;
          _scrollBy(delta);
          return true;
        case 'togglePin':
          await _togglePin();
          return true;
        case 'closeWindow':
          await _handleClose();
          return true;
        case 'focus':
          await windowManager.show();
          await windowManager.focus();
          return true;
      }
      return null;
    });
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target =
        (_scrollController.offset + delta).clamp(0.0, position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _togglePin() async {
    _alwaysOnTop = !_alwaysOnTop;
    await windowManager.setAlwaysOnTop(_alwaysOnTop);
    _state.alwaysOnTop = _alwaysOnTop;
    await _state.save();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  void _onScroll() {
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveScrollRatio();
    });
  }

  void _saveScrollRatio() {
    if (!_scrollController.hasClients || _gameKey.isEmpty) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    _state.scrollPositions[_gameKey] =
        (_scrollController.offset / max).clamp(0.0, 1.0);
    _state.save();
  }

  /// 恢复当前游戏的滚动位置（内容布局需要时间，做多次尝试）
  void _restoreScroll() {
    final ratio = _state.scrollRatioFor(_gameKey);
    if (ratio <= 0) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }
    var retries = 0;
    void attempt() {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) {
        if (retries < 10) {
          retries++;
          Future.delayed(const Duration(milliseconds: 100), attempt);
        }
        return;
      }
      _scrollController.jumpTo((ratio * max).clamp(0.0, max));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
  }

  void _scheduleSaveBounds() {
    _boundsSaveTimer?.cancel();
    _boundsSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      if (await windowManager.isMaximized()) return;
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      _state.width = size.width;
      _state.height = size.height;
      _state.x = position.dx;
      _state.y = position.dy;
      await _state.save();
    });
  }

  /// 请求关闭浮窗：保存状态后走系统 WM_CLOSE 流程，让 Windows 正常销毁窗口。
  ///
  /// 注意：不能使用 windowManager.destroy()——其 Windows 实现是
  /// PostQuitMessage(0)，会退出整个进程消息循环，导致主程序被一并关闭。
  Future<void> _handleClose() async {
    if (_closing) return;
    _closing = true;
    _boundsSaveTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _saveScrollRatio();
    await _state.save();
    // 通知主窗口浮窗已关闭
    if (_mainWindowId.isNotEmpty) {
      try {
        await WindowController.fromWindowId(_mainWindowId)
            .invokeMethod('guideWindowClosed');
      } catch (_) {}
    }
    windowManager.removeListener(this);
    // 解除拦截后重新触发关闭，由系统驱动窗口销毁（引擎随窗口安全销毁）
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    _handleClose();
  }

  @override
  void onWindowResize() => _scheduleSaveBounds();

  @override
  void onWindowMove() => _scheduleSaveBounds();

  @override
  void onWindowMaximize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isMaximized = true);
    });
  }

  @override
  void onWindowUnmaximize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isMaximized = false);
    });
  }

  @override
  void dispose() {
    _boundsSaveTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _scrollController.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundColor(context),
      // stretch 让内容占满整宽：默认 center 在宽松约束下会把内容块水平居中
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: _buildGuideContent(),
                ),
              ),
            ],
          ),
          if (_settingsOpen) ...[
            // 点击其他区域自动关闭并保存
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeSettingsPanel,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 44,
              right: 8,
              child: _buildSettingsPanel(),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleSettingsPanel() {
    if (_settingsOpen) {
      _closeSettingsPanel();
    } else {
      setState(() => _settingsOpen = true);
    }
  }

  /// 关闭设置面板并保存透明度/字号
  void _closeSettingsPanel() {
    if (!_settingsOpen) return;
    setState(() => _settingsOpen = false);
    _state.opacity = _opacity;
    _state.fontSize = _fontSizeOverride;
    _state.save();
  }

  Widget _buildSettingsPanel() {
    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(color: AppTheme.getBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSliderRow(
            label: '透明度',
            value: _opacity,
            min: 0.3,
            max: 1.0,
            valueText: '${(_opacity * 100).round()}%',
            onChanged: (v) {
              setState(() => _opacity = v);
              windowManager.setOpacity(v);
            },
          ),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: '文字大小',
            value: _fontSize,
            min: 10,
            max: 24,
            valueText: '${_fontSize.round()}',
            onChanged: (v) => setState(() => _fontSizeOverride = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String valueText,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.7),
          border: Border(
            bottom: BorderSide(
              color: AppTheme.getBorderColor(context).withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.menu_book,
                size: 16, color: AppTheme.getPrimaryColor(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _title.isEmpty ? '攻略' : '$_title - 攻略',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ),
            _TitleBarButton(
              icon: Icons.tune,
              iconSize: 15,
              tooltip: '透明度 / 文字大小',
              isActive: _settingsOpen,
              onPressed: _toggleSettingsPanel,
            ),
            _TitleBarButton(
              icon: _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
              iconSize: 15,
              tooltip: _alwaysOnTop ? '取消置顶' : '置顶',
              isActive: _alwaysOnTop,
              onPressed: _togglePin,
            ),
            _TitleBarButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onPressed: () => windowManager.minimize(),
            ),
            _TitleBarButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              iconSize: 13,
              tooltip: _isMaximized ? '还原' : '最大化',
              onPressed: _toggleMaximize,
            ),
            _TitleBarButton(
              icon: Icons.close,
              tooltip: '关闭',
              isClose: true,
              onPressed: _handleClose,
            ),
          ],
        ),
      ),
    );
  }

  /// 只读攻略内容渲染：文本段落 + 图片，与详情页攻略展示保持一致
  Widget _buildGuideContent() {
    if (_content.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '暂无攻略内容',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
        ),
      );
    }

    final widgets = <Widget>[];
    var textBuffer = <String>[];

    void flushText() {
      if (textBuffer.isEmpty) return;
      widgets.add(
        SelectableText(
          textBuffer.join('\n'),
          style: TextStyle(
            fontSize: _fontSize,
            height: 1.7,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
      );
      textBuffer = [];
    }

    for (final line in _content.split('\n')) {
      final imagePath = MediaReferenceParser.parseImageLine(line);
      if (imagePath != null) {
        flushText();
        widgets.add(_buildImage(imagePath));
      } else if (MediaReferenceParser.parseVideoLine(line) != null) {
        // 浮窗不播放视频，跳过视频标签行
      } else {
        textBuffer.add(line.trimRight());
      }
    }
    flushText();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildImage(String imagePath) {
    final isRemote =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    if (!isRemote && !File(imagePath).existsSync()) {
      return const SizedBox.shrink();
    }
    final image = isRemote
        ? Image.network(
            imagePath,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          )
        : Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          child: image,
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;
  final bool isActive;
  final double iconSize;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
    this.isActive = false,
    this.iconSize = 16,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            width: 40,
            height: 40,
            color: _isHovered
                ? (widget.isClose
                    ? AppTheme.accentColor.withValues(alpha: 0.8)
                    : AppTheme.getSurfaceColor(context).withValues(alpha: 0.15))
                : Colors.transparent,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _isHovered && widget.isClose
                  ? AppTheme.getTextColorOnPrimary(context)
                  : widget.isActive
                      ? AppTheme.getPrimaryColor(context)
                      : AppTheme.getTextSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}
