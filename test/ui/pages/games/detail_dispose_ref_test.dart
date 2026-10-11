import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 回归测试：详情页 dispose 中禁止使用 ref（Riverpod 规则）。
/// 旧写法（dispose 里 ref.read）会抛出 "Cannot use ref after the widget was disposed"，
/// 修复后改为 initState 缓存实例、dispose 用缓存调用。
void main() {
  final counterProvider = Provider<int>((ref) => 0);

  testWidgets('dispose 中直接使用 ref.read 会抛异常（旧写法回归验证）', (tester) async {
    Object? caught;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      caught ??= details.exception;
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _BadPatternWidget(provider: counterProvider),
        ),
      ),
    );
    // 卸载触发 dispose
    await tester.pumpWidget(const SizedBox.shrink());
    expect(caught.toString(), contains('Cannot use "ref"'));
  });

  testWidgets('initState 缓存实例后 dispose 正常调用（当前修复写法）', (tester) async {
    Object? caught;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      caught ??= details.exception;
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _GoodPatternWidget(provider: counterProvider),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(caught, isNull);
  });
}

/// 旧写法：dispose 中调用 ref.read（会抛异常）
class _BadPatternWidget extends ConsumerStatefulWidget {
  final Provider<int> provider;
  const _BadPatternWidget({required this.provider});

  @override
  ConsumerState<_BadPatternWidget> createState() => _BadPatternWidgetState();
}

class _BadPatternWidgetState extends ConsumerState<_BadPatternWidget> {
  @override
  void dispose() {
    // Riverpod 禁止在 dispose 中使用 ref
    ref.read(widget.provider);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 修复写法：initState 缓存，dispose 用缓存
class _GoodPatternWidget extends ConsumerStatefulWidget {
  final Provider<int> provider;
  const _GoodPatternWidget({required this.provider});

  @override
  ConsumerState<_GoodPatternWidget> createState() => _GoodPatternWidgetState();
}

class _GoodPatternWidgetState extends ConsumerState<_GoodPatternWidget> {
  late final int _cached;

  @override
  void initState() {
    super.initState();
    _cached = ref.read(widget.provider);
  }

  @override
  void dispose() {
    // 使用缓存值，不触碰 ref
    debugPrint('cached=$_cached');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
