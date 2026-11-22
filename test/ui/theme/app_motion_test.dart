import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/markdown_editor.dart';

void main() {
  testWidgets('Markdown 预览切换保持编辑区域宽度', (tester) async {
    final controller = TextEditingController(text: '# 标题\n\n预览正文');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 500,
            child: MarkdownEditor(controller: controller, imagePaths: const []),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SingleChildScrollView)).width, 700);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('切页保留退出页面的状态，退出结束后只销毁一次', (tester) async {
    final selected = ValueNotifier('甲');
    final created = <String>[];
    final disposed = <String>[];
    addTearDown(selected.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: selected,
        builder: (context, page, child) => AppContentSwitcher(
          child: _PageProbe(
            key: ValueKey(page),
            label: page,
            created: created,
            disposed: disposed,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('甲 0'));
    await tester.pump();
    selected.value = '乙';
    await tester.pump();
    expect(created, ['甲', '乙']);
    expect(disposed, isEmpty);
    expect(find.text('甲 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    selected.value = '丙';
    await tester.pump();
    expect(created, ['甲', '乙', '丙']);
    await tester.pumpAndSettle();
    expect(disposed, unorderedEquals(['甲', '乙']));
    expect(find.text('丙 0'), findsOneWidget);
  });

  testWidgets('切换中开启减少动效，立即移除退出内容', (tester) async {
    final reduced = ValueNotifier(false);
    final selected = ValueNotifier('甲');
    addTearDown(reduced.dispose);
    addTearDown(selected.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: reduced,
        builder: (context, disabled, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
          child: ValueListenableBuilder(
            valueListenable: selected,
            builder: (context, page, child) => AppContentSwitcher(
              child: Text(page, key: ValueKey(page)),
            ),
          ),
        ),
      ),
    ));
    selected.value = '乙';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    reduced.value = true;
    await tester.pump();
    expect(find.text('甲'), findsNothing);
    expect(find.text('乙'), findsOneWidget);
  });

  testWidgets('等待入场时取消动效，内容立即可见且可点击', (tester) async {
    final animate = ValueNotifier(true);
    var tapped = false;
    addTearDown(animate.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: animate,
        builder: (context, enabled, child) => AppEntrance(
          animate: enabled,
          delay: const Duration(seconds: 1),
          child: TextButton(
            onPressed: () => tapped = true,
            child: const Text('进入'),
          ),
        ),
      ),
    ));
    animate.value = false;
    await tester.pump();
    await tester.tap(find.text('进入'), warnIfMissed: false);
    expect(tapped, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出内容不能响应点击、键盘焦点或辅助朗读', (tester) async {
    final selected = ValueNotifier(false);
    final focusNode = FocusNode();
    var tapped = false;
    addTearDown(selected.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: selected,
          builder: (context, changed, child) => AppContentSwitcher(
            child: KeyedSubtree(
              key: ValueKey(changed),
              child: changed
                  ? const Text('新页面')
                  : Column(children: [
                      TextButton(
                        onPressed: () => tapped = true,
                        child: const Text('旧按钮'),
                      ),
                      TextField(focusNode: focusNode),
                    ]),
            ),
          ),
        ),
      ),
    ));
    selected.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('旧按钮'), warnIfMissed: false);
    focusNode.requestFocus();
    await tester.pump();
    expect(tapped, isFalse);
    expect(focusNode.hasFocus, isFalse);
    expect(
      tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.label),
      isNot(contains('旧按钮')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('减少动效时标签页点击立即到达目标页', (tester) async {
    final controller = AppTabController(length: 2, vsync: tester);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: Column(children: [
            GlassTabBar(
              controller: controller,
              tabs: const [Tab(text: '标签甲'), Tab(text: '标签乙')],
            ),
            Expanded(
              child: TabBarView(
                controller: controller,
                children: const [Text('内容甲'), Text('内容乙')],
              ),
            ),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('标签乙'));
    await tester.pump();
    expect(controller.animation!.value, 1);
    expect(controller.indexIsChanging, isFalse);
    expect(find.text('内容乙').hitTestable(), findsOneWidget);
  });

  testWidgets('减少动效时弹窗立即打开并正常返回结果', (tester) async {
    Future<bool?>? result;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () {
              result = showAppDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('确认窗口'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('确认'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('打开'),
          );
        })),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pump();
    expect(find.text('确认').hitTestable(), findsOneWidget);
    expect(
      tester
          .widgetList<ScaleTransition>(find.byType(ScaleTransition))
          .last
          .scale
          .value,
      1,
    );
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('普通弹窗以弹柔缩放进入并平稳收束', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showAppDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('弹窗')),
          ),
          child: const Text('打开'),
        );
      })),
    ));

    await tester.tap(find.text('打开'));
    await tester.pump();
    var transition =
        tester.widgetList<ScaleTransition>(find.byType(ScaleTransition)).last;
    expect(transition.scale.value, closeTo(0.92, 0.001));

    await tester.pump(const Duration(milliseconds: 160));
    transition =
        tester.widgetList<ScaleTransition>(find.byType(ScaleTransition)).last;
    expect(transition.scale.value, greaterThan(1));

    await tester.pumpAndSettle();
    transition =
        tester.widgetList<ScaleTransition>(find.byType(ScaleTransition)).last;
    expect(transition.scale.value, 1);
  });

  testWidgets('统一搜索框只显示玻璃容器底色', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GlassSearchBar()),
    ));

    final decoration =
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.filled, isFalse);
    expect(decoration.fillColor, isNull);
    expect(decoration.focusedBorder, InputBorder.none);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final context = tester.element(find.byType(GlassSearchBar));
    final glass = tester.widget<GlassContainer>(find.byType(GlassContainer));
    expect(glass.border!.top.color, AppTheme.getPrimaryColor(context));
  });

  testWidgets('文本选择菜单使用中文标签和项目文字令牌', (tester) async {
    var copied = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: buildAppTextSelectionToolbar(
            context,
            const TextSelectionToolbarAnchors(primaryAnchor: Offset(120, 120)),
            [
              ContextMenuButtonItem(
                type: ContextMenuButtonType.copy,
                onPressed: () => copied = true,
              ),
              const ContextMenuButtonItem(
                type: ContextMenuButtonType.selectAll,
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    final menuTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('复制'), matching: find.byType(ListTile)),
    );
    expect(menuTile.dense, isTrue);
    expect(
      menuTile.contentPadding,
      const EdgeInsets.symmetric(horizontal: GlassConstants.spacingCompact),
    );
    expect(menuTile.onTap, isNotNull);
    final selectAllTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('全选'), matching: find.byType(ListTile)),
    );
    expect(selectAllTile.onTap, isNull);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, isTrue);
  });

  testWidgets('应用级减弱动效覆盖到媒体环境', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          AppMotionVisibility(reduceMotion: true, child: child!),
      home: const Scaffold(body: Text('状态')),
    ));

    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.text('状态'))),
      isTrue,
    );
  });
}

class _PageProbe extends StatefulWidget {
  final String label;
  final List<String> created;
  final List<String> disposed;

  const _PageProbe({
    super.key,
    required this.label,
    required this.created,
    required this.disposed,
  });

  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe> {
  var count = 0;

  @override
  void initState() {
    super.initState();
    widget.created.add(widget.label);
  }

  @override
  void dispose() {
    widget.disposed.add(widget.label);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => count++),
        child: Text('${widget.label} $count'),
      );
}
