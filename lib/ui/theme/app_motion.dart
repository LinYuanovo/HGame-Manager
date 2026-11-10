import 'dart:async';

import 'package:flutter/material.dart';

class AppMotion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 300);
  static const shimmer = Duration(milliseconds: 1400);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

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

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    return FadeTransition(
      opacity: AppMotion.reduced(context)
          ? const AlwaysStoppedAnimation(1)
          : animation.drive(CurveTween(curve: AppMotion.curve)),
      child: child,
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
      switchInCurve: AppMotion.curve,
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
            : animation,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: AppMotion.reduced(context)
                ? Offset.zero
                : Offset((1 - animation.value) * 8 * direction, 0),
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
                    offset: Offset(0, (1 - progress) * 6),
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
