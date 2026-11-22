import 'dart:async';
import 'package:flutter/material.dart';

class AppMotion {
  static const fast = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 310);
  static const slow = Duration(milliseconds: 420);
  static const shimmer = Duration(milliseconds: 1400);
  static const curve = Curves.easeOutCubic;
  static const settle = Cubic(0.20, 0.88, 0.27, 1.20);
  static const press = Duration(milliseconds: 100);

  static AnimationStyle overlayStyle(BuildContext context) => AnimationStyle(
        duration: duration(context, medium),
        reverseDuration: duration(context, fast),
        curve: curve,
        reverseCurve: Curves.easeInCubic,
      );

  static Widget buttonFace(
          BuildContext context, Set<WidgetState> states, Widget? child) =>
      AppControlScale(
        pressed: states.contains(WidgetState.pressed),
        hovered: states.contains(WidgetState.hovered),
        enabled: !states.contains(WidgetState.disabled),
        child: child ?? const SizedBox.shrink(),
      );

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  static Duration frameAlignedDuration(
      BuildContext context, Duration duration) {
    final effectiveDuration = AppMotion.duration(context, duration);
    if (effectiveDuration == Duration.zero) return effectiveDuration;

    final refreshRate = View.of(context).display.refreshRate;
    if (!refreshRate.isFinite || refreshRate <= 1) return effectiveDuration;

    final frameCount =
        (effectiveDuration.inMicroseconds * refreshRate / 1e6).round();
    return Duration(
        microseconds: (frameCount * 1e6 / refreshRate).round());
  }

  static void scrollTo(
      BuildContext context, ScrollController controller, double offset) {
    if (!controller.hasClients) return;
    if (reduced(context)) {
      controller.jumpTo(offset);
    } else {
      controller.animateTo(offset, duration: slow, curve: curve);
    }
  }
}

class AppMotionVisibility extends StatefulWidget {
  const AppMotionVisibility({super.key, required this.child, this.reduceMotion = false});
  final Widget child;
  final bool reduceMotion;
  @override
  State<AppMotionVisibility> createState() => _AppMotionVisibilityState();
}

class _AppMotionVisibilityState extends State<AppMotionVisibility>
    with WidgetsBindingObserver {
  late AppLifecycleState? _state = WidgetsBinding.instance.lifecycleState;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setState(() => _state = state);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          disableAnimations: media.disableAnimations || widget.reduceMotion),
      child: TickerMode(
        enabled: _state == null ||
            _state == AppLifecycleState.resumed ||
            _state == AppLifecycleState.inactive,
        child: widget.child,
      ),
    );
  }
}

class AppDialogTransition extends StatefulWidget {
  const AppDialogTransition({
    super.key,
    required this.animation,
    required this.child,
    this.initialScale = 0.92,
  });

  final Animation<double> animation;
  final Widget child;
  final double initialScale;

  @override
  State<AppDialogTransition> createState() => _AppDialogTransitionState();
}

class _AppDialogTransitionState extends State<AppDialogTransition> {
  late CurvedAnimation _curve = _createCurve();

  CurvedAnimation _createCurve() => CurvedAnimation(
        parent: widget.animation,
        curve: AppMotion.settle,
        reverseCurve: Curves.easeInCubic,
      );

  @override
  void didUpdateWidget(AppDialogTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      _curve.dispose();
      _curve = _createCurve();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    const stationary = AlwaysStoppedAnimation(1.0);
    return FadeTransition(
      opacity: reduced ? stationary : widget.animation,
      child: ScaleTransition(
        scale: reduced
            ? stationary
            : _curve.drive(Tween<double>(begin: widget.initialScale, end: 1)),
        child: widget.child,
      ),
    );
  }
}

class AppSelectedMark extends StatelessWidget {
  const AppSelectedMark(
      {super.key, required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppMotionValue(
      target: selected ? 1 : 0,
      curve: AppMotion.settle,
      builder: (context, value, child) =>
          Transform.scale(scale: 1 + .36 * value * (1 - value), child: child),
      child: child);
}

class AppMotionValue extends StatefulWidget {
  const AppMotionValue(
      {super.key,
      required this.target,
      this.begin,
      this.duration = AppMotion.medium,
      this.curve = AppMotion.curve,
      required this.builder,
      this.child});
  final double target;
  final double? begin;
  final Duration duration;
  final Curve curve;
  final ValueWidgetBuilder<double> builder;
  final Widget? child;

  @override
  State<AppMotionValue> createState() => _AppMotionValueState();
}

class _AppMotionValueState extends State<AppMotionValue>
    with SingleTickerProviderStateMixin {
  late final _value = AnimationController.unbounded(
      vsync: this, value: widget.begin ?? widget.target);
  bool _instant = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _instant =
        AppMotion.reduced(context) || !TickerMode.valuesOf(context).enabled;
    if (_instant || !_value.isAnimating) _update();
  }

  @override
  void didUpdateWidget(AppMotionValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target ||
        widget.duration != oldWidget.duration) {
      _update();
    }
  }

  void _update() {
    if (_instant || widget.duration == Duration.zero) {
      _value.value = widget.target;
    } else if (_value.value != widget.target || _value.isAnimating) {
      _value.animateTo(widget.target,
          duration: widget.duration, curve: widget.curve);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _value,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, _value.value, child));

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }
}

class AppControlScale extends StatelessWidget {
  const AppControlScale(
      {super.key,
      required this.child,
      this.pressed = false,
      this.hovered = false,
      this.enabled = true});
  final Widget child;
  final bool pressed, hovered, enabled;

  @override
  Widget build(BuildContext context) => AppMotionValue(
      target: !enabled
          ? 1
          : pressed
              ? .96
              : hovered
                  ? 1.018
                  : 1,
      duration: !enabled
          ? Duration.zero
          : pressed
              ? AppMotion.press
              : AppMotion.medium,
      curve: pressed ? AppMotion.curve : AppMotion.settle,
      builder: (context, scale, child) => Transform.scale(
          scale: AppMotion.reduced(context) ? 1 : scale,
          transformHitTests: false,
          child: child),
      child: child);
}

class AppActionSurface extends StatefulWidget {
  const AppActionSurface(
      {super.key,
      this.onTap,
      this.onDoubleTap,
      this.onSecondaryTapUp,
      this.borderRadius,
      required this.child});
  final VoidCallback? onTap, onDoubleTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final BorderRadius? borderRadius;
  final Widget child;

  @override
  State<AppActionSurface> createState() => _AppActionSurfaceState();
}

class _AppActionSurfaceState extends State<AppActionSurface> {
  bool _pressed = false, _hovered = false;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      borderRadius: widget.borderRadius,
      onHighlightChanged: (value) => setState(() => _pressed = value),
      onHover: (value) => setState(() => _hovered = value),
      child: AppControlScale(
          pressed: _pressed,
          hovered: _hovered,
          enabled: widget.onTap != null ||
              widget.onDoubleTap != null ||
              widget.onSecondaryTapUp != null,
          child: widget.child));
}

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final reduced = AppMotion.reduced(context);
    return FadeTransition(
      opacity: reduced
          ? const AlwaysStoppedAnimation(1)
          : animation.drive(CurveTween(curve: AppMotion.curve)),
      child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) => Transform.translate(
              offset: Offset(
                  0,
                  reduced
                      ? 0
                      : (1 - AppMotion.settle.transform(animation.value)) * 8),
              child: child)),
    );
  }
}

class AppTabController extends TabController {
  bool reducedMotion = false;

  AppTabController({required super.length, required super.vsync})
      : super(animationDuration: AppMotion.medium);

  @override
  Duration get animationDuration =>
      reducedMotion ? Duration.zero : super.animationDuration;

  @override
  void animateTo(int value, {Duration? duration, Curve curve = Curves.ease}) {
    super.animateTo(value,
        duration: reducedMotion ? Duration.zero : duration ?? AppMotion.medium,
        curve: AppMotion.curve);
  }
}

class AppContentSwitcher extends StatelessWidget {
  final Widget child;
  final double direction;

  const AppContentSwitcher(
      {super.key, required this.child, this.direction = 1});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.medium),
      reverseDuration: AppMotion.duration(context, AppMotion.fast),
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [
          for (final page in [
            if (!AppMotion.reduced(context)) ...previousChildren,
            if (currentChild != null) currentChild,
          ])
            ExcludeFocus(
              key: page.key,
              excluding: page != currentChild,
              child: ExcludeSemantics(
                excluding: page != currentChild,
                child: IgnorePointer(
                  ignoring: page != currentChild,
                  child: TickerMode(enabled: page == currentChild, child: page),
                ),
              ),
            ),
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: AppMotion.reduced(context)
            ? const AlwaysStoppedAnimation(1)
            : animation.drive(CurveTween(curve: AppMotion.curve)),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: AppMotion.reduced(context)
                ? Offset.zero
                : Offset(
                    (1 - AppMotion.settle.transform(animation.value)) *
                        8 *
                        direction,
                    0),
            child: child,
          ),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class AppEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final bool animate;

  const AppEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.animate = true,
  });

  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.medium);
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate ||
        AppMotion.reduced(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _delay?.cancel();
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      if (widget.delay == Duration.zero) {
        _controller.forward();
      } else {
        _delay = Timer(widget.delay, () {
          if (mounted) _controller.forward();
        });
      }
    }
  }

  @override
  void didUpdateWidget(AppEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) {
      _delay?.cancel();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = AppMotion.curve.transform(_controller.value);
          return ExcludeFocus(
            excluding: progress == 0,
            child: ExcludeSemantics(
              excluding: progress == 0,
              child: IgnorePointer(
                ignoring: progress == 0,
                child: FadeTransition(
                  opacity:
                      _controller.drive(CurveTween(curve: AppMotion.curve)),
                  child: Transform.translate(
                    offset: Offset(
                        0,
                        (1 - AppMotion.settle.transform(_controller.value)) *
                            6),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
        child: widget.child,
      );
}
