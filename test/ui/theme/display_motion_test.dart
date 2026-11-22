import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';

void main() {
  for (final rate in [30.0, 59.94, 60.0, 75.0, 90.0, 120.0, 144.0, 165.0, 240.0]) {
    testWidgets('$rate Hz 转场时长对齐到屏幕帧周期', (tester) async {
      tester.view.display.refreshRate = rate;
      addTearDown(tester.view.display.resetRefreshRate);
      late Duration aligned;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            aligned = AppMotion.frameAlignedDuration(context, AppMotion.slow);
            return const SizedBox();
          },
        ),
      ));

      final frameCount = aligned.inMicroseconds * rate / 1000000;
      expect(frameCount, closeTo(frameCount.round(), 0.001));
      expect(aligned.inMicroseconds,
          closeTo(AppMotion.slow.inMicroseconds, 1000000 / rate / 2));
    });
  }

  for (final rate in [30.0, 59.94, 90.0, 120.0, 144.0, 165.0, 240.0]) {
    testWidgets('$rate Hz 释放按原时长收束，无持续请求帧', (tester) async {
      tester.view.display.refreshRate = rate;
      addTearDown(tester.view.display.resetRefreshRate);
      double painted = 0;
      await tester.pumpWidget(MaterialApp(
          home: AppMotionValue(
        begin: .96,
        target: 1,
        curve: AppMotion.settle,
        builder: (context, value, _) {
          painted = value;
          return const SizedBox();
        },
      )));
      var elapsed = Duration.zero;
      var peak = painted;
      final frame = Duration(microseconds: (1000000 / rate).round());
      while (elapsed < AppMotion.medium + frame * 2) {
        await tester.pump(frame);
        elapsed += frame;
        if (painted > peak) peak = painted;
      }
      expect(peak, inExclusiveRange(1, 1.01));
      expect(painted, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('确定进度的绘制追随数值，朗读立即更新，中途减少动效立即收束', (tester) async {
    final target = ValueNotifier(.2);
    final reduced = ValueNotifier(false);
    addTearDown(target.dispose);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ListenableBuilder(
      listenable: Listenable.merge([target, reduced]),
      builder: (context, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced.value),
        child: AppLinearProgress(value: target.value),
      ),
    )));
    LinearProgressIndicator bar() =>
        tester.widget(find.byType(LinearProgressIndicator));
    target.value = .8;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(bar().value, inExclusiveRange(.2, .8));
    expect(bar().semanticsValue, '80');
    reduced.value = true;
    await tester.pump();
    expect(bar().value, .8);
  });

  testWidgets('主题按钮按下缩小，中断释放后仍响应一次并回到原位', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Center(
            child: ElevatedButton(
                onPressed: () => calls++, child: const Text('应用')))));
    final face = find.descendant(
        of: find.byType(AppControlScale), matching: find.byType(Transform));
    double scale() => tester.widget<Transform>(face).transform.storage[0];
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('应用')));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump(const Duration(milliseconds: 40));
    expect(scale(), lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(scale(), 1);
  });

  testWidgets('深色自绘控件可用键盘激活，禁用立即拒绝点击', (tester) async {
    var calls = 0;
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: ValueListenableBuilder(
              valueListenable: enabled,
              builder: (_, available, child) => AppActionSurface(
                  onTap: available ? () => calls++ : null,
                  child: const Text('翻页'))),
        )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);
    enabled.value = false;
    await tester.pump();
    await tester.tap(find.text('翻页'));
    expect(calls, 1);
  });
}
