import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LayoutReflow extends StatefulWidget {
  const LayoutReflow({super.key, required this.revision, required this.child});
  final Object revision;
  final Widget child;
  @override
  State<LayoutReflow> createState() => _LayoutReflowState();
}

class _LayoutReflowState extends State<LayoutReflow>
    with SingleTickerProviderStateMixin, AppDisplayTicks {
  Offset? _position;
  Offset _shift = Offset.zero;
  Offset _paintedShift = Offset.zero;
  late final _animation =
      AnimationController(vsync: this, duration: AppMotion.medium, value: 1);
  int _measurement = 0;
  @override
  void initState() {
    super.initState();
    _measure(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _animation.value = 1;
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LayoutReflow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _measure(oldWidget.revision != widget.revision);
  }

  void _measure(bool animate) {
    final measurement = ++_measurement;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || measurement != _measurement) return;
      final box = context.findRenderObject() as RenderBox;
      if (!box.hasSize) return;
      final next = box.localToGlobal(Offset.zero);
      final previous = _position;
      _position = next;
      if (animate &&
          previous != null &&
          previous != next &&
          !AppMotion.reduced(context)) {
        _shift = previous + _paintedShift - next;
        _animation.forward(from: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = AppMotion.curve.transform(_animation.value);
        _paintedShift =
            AppMotion.reduced(context) ? Offset.zero : _shift * (1 - value);
        return Transform.translate(offset: _paintedShift, child: child);
      },
      child: widget.child);
}
